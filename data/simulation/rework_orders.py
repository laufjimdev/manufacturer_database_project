import math
from datetime import timedelta
from data.simulation.quality_inspections import simulate_quality_inspections
from data.simulation.product_transfers import create_product_transfer
from data.simulation.data_configs.quality_inspection_config import REWORK_INSPECTION_POLICY


def _group_rework_lots(rework_lots):
    """
    Groups rework lots by (factory_id, product_id): sums quantity, tracks
    every contributing production line, and tracks the latest inspection
    date (a combined rework order can't start before ALL of its
    contributing lots have actually been inspected).
    """
    groups = {}
    for lot in rework_lots:
        key = (lot["factory_id"], lot["product_id"])
        group = groups.setdefault(key, {
            "quantity": 0,
            "latest_inspection_date": lot["inspection_date"],
            "production_line_ids": set(),
        })
        group["quantity"] += lot["quantity"]
        group["latest_inspection_date"] = max(group["latest_inspection_date"], lot["inspection_date"])
        group["production_line_ids"].add(lot["production_line_id"])

    return groups


def _select_rework_line(candidate_line_ids, lines_capacity_dict):
    """
    Picks the fastest (highest-capacity) line among the ones that produced
    the reworked lots, to minimize the rework's added lead time.
    Simplification: a real plant might instead route rework back to the
    original line for process consistency — worth revisiting if that
    matters more to you than speed.
    """
    return max(candidate_line_ids, key=lambda line_id: lines_capacity_dict[line_id])


def simulate_rework_orders(connection, rework_lots, lines_capacity_dict, inspector_lookup):
    """
    Consolidates 'rework' lots (already scoped to one (factory_id, product_id)
    by the caller, typically) into as few new work orders as possible,
    re-inspects each with REWORK_INSPECTION_POLICY, and transfers whatever
    passes. Anything that fails this second pass is scrapped outright
    (allow_rework=False) — rework is attempted once per lot, never twice.

    No consumption transactions are recorded: this quantity's materials
    were already fully consumed at the original work order.

    Returns (wo_counter, net_transferred_quantity).
    """
    if not rework_lots:
        return 0, 0

    groups = _group_rework_lots(rework_lots)

    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO work_orders
        (
            factory_id,
            production_line_id,
            product_id,
            quantity,
            start_date,
            due_date,
            status,
            priority,
            completed_at,
            reworked
        )
        VALUES
        (
            %s, %s, %s, %s, %s, %s, 'completed', 'high', %s, TRUE
        )
        RETURNING work_order_id;
    '''

    wo_counter = 0
    net_transferred = 0

    for (factory_id, product_id), group in groups.items():
        production_line_id = _select_rework_line(group["production_line_ids"], lines_capacity_dict)
        line_capacity = lines_capacity_dict[production_line_id]
        quantity = group["quantity"]

        start_date = group["latest_inspection_date"] + timedelta(days=1)
        due_date = start_date + timedelta(days=math.ceil(quantity / line_capacity))

        cursor.execute(insert_query, (
            factory_id, production_line_id, product_id,
            quantity, start_date, due_date, due_date
        ))
        work_order_id = cursor.fetchone()[0]
        wo_counter += 1

        net_qty, _ = simulate_quality_inspections(
            connection, work_order_id, factory_id, production_line_id,
            product_id, quantity, due_date, inspector_lookup,
            policy=REWORK_INSPECTION_POLICY, allow_rework=False,
        )

        if net_qty > 0:
            shipped_date = due_date + timedelta(days=2)
            received_date = shipped_date + timedelta(days=2)
            create_product_transfer(
                connection, work_order_id, factory_id, product_id,
                net_qty, shipped_date, received_date
            )
            net_transferred += net_qty
        else:
            print(f"Rework work order {work_order_id}: scrapped on re-inspection, no transfer created.")

    cursor.close()
    return wo_counter, net_transferred