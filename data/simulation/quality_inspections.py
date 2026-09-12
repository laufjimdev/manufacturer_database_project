import random
from data.simulation.data_configs.quality_inspection_config import QUALITY_INSPECTION_POLICY


def get_qc_inspector_lookup(connection):
    """
    Returns {factory_id: [employee_id, ...]} for employees in the
    Quality Control department at each factory.
    """
    cursor = connection.cursor()
    cursor.execute('''
        SELECT e.factory_id, e.employee_id
        FROM employees e
        JOIN departments d ON e.department_id = d.department_id
        WHERE d.department_name = 'Quality Control';
    ''')
    rows = cursor.fetchall()
    cursor.close()

    lookup = {}
    for factory_id, employee_id in rows:
        lookup.setdefault(factory_id, []).append(employee_id)
    return lookup


def _split_into_lots(quantity, lot_size):
    lots = []
    remaining = quantity
    while remaining > 0:
        lot_qty = min(lot_size, remaining)
        lots.append(lot_qty)
        remaining -= lot_qty
    return lots


def _inspect_lot(lot_quantity, policy, allow_rework=True):
    sample_size = max(policy["min_sample_size"], round(lot_quantity * policy["sample_rate"]))
    sample_size = min(sample_size, lot_quantity)

    acceptance_number = max(1, round(sample_size * policy["acceptance_rate"]))
    defect_count = sum(1 for _ in range(sample_size) if random.random() < policy["defect_rate"])

    if defect_count <= acceptance_number:
        return "passed", defect_count, "none", 0

    if not allow_rework:
        return "failed", defect_count, "scrap", lot_quantity

    scrap_threshold = max(acceptance_number + 1, round(sample_size * policy["scrap_rate"]))
    disposition = "scrap" if defect_count > scrap_threshold else "rework"
    return "failed", defect_count, disposition, lot_quantity


def simulate_quality_inspections(connection, work_order_id, factory_id, production_line_id,
                                  product_id, wo_quantity, inspection_date, inspector_lookup,
                                  policy=None, allow_rework=True):
    """
    Splits a work order's produced quantity into inspection lots, simulates
    a sample-based pass/fail check per lot, and inserts quality_inspections
    rows.

    `policy` defaults to QUALITY_INSPECTION_POLICY. Callers re-inspecting a
    rework batch should pass REWORK_INSPECTION_POLICY and allow_rework=False,
    since a rework batch that fails again is scrapped, not reworked again.

    Returns (net_shippable_quantity, rework_lots).
    - net_shippable_quantity excludes both 'scrap' and 'rework' dispositions
      — scrap is lost, rework isn't shippable yet.
    - rework_lots is a list of dicts, one per lot that came back 'rework':
      {"factory_id", "product_id", "production_line_id", "quantity",
      "inspection_date"} — enough for a caller to batch these into new
      rework work orders.
    """
    policy = policy or QUALITY_INSPECTION_POLICY
    lots = _split_into_lots(wo_quantity, policy["lot_size"])

    inspectors = inspector_lookup.get(factory_id)
    if not inspectors:
        raise ValueError(f"No Quality Control employees found for factory {factory_id}")

    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO quality_inspections
        (
            product_id,
            factory_id,
            production_line_id,
            work_order_id,
            inspection_date,
            inspector_employee_id,
            result,
            defect_count,
            disposition,
            quantity_affected
        )
        VALUES
        (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
        );
    '''

    net_shippable_quantity = wo_quantity
    rework_lots = []

    for lot_quantity in lots:
        result, defect_count, disposition, quantity_affected = _inspect_lot(
            lot_quantity, policy, allow_rework=allow_rework
        )
        inspector_employee_id = random.choice(inspectors)

        cursor.execute(insert_query, (
            product_id, factory_id, production_line_id, work_order_id,
            inspection_date, inspector_employee_id,
            result, defect_count, disposition, quantity_affected,
        ))

        net_shippable_quantity -= quantity_affected

        if disposition == 'rework':
            rework_lots.append({
                "factory_id": factory_id,
                "product_id": product_id,
                "production_line_id": production_line_id,
                "quantity": quantity_affected,
                "inspection_date": inspection_date,
            })

    cursor.close()
    return net_shippable_quantity, rework_lots