from database.db_connection import get_connection
from data.seed.data_configs.product_bom_config import calculate_required_materials
from data.seed.raw_material_suppliers import get_supplier_lookup, get_random_supplier
from datetime import date, timedelta
from faker import Faker

'''
This module simulates purchase orders for each factory based on the quantity defined for the first product (product_id = 1), the rest of the products purchase orders are automatically calculated as ratio of this initial defined value.
'''

fake = Faker()

def generate_purchase_order_data(factory_quantities, purchase_start_date, purchase_end_date):
    """
    Returns:
        [
            {
                "factory_id": str,
                "supplier_id": int,
                "order_date": date,
                "expected_date": date,
                "total_cost": float,
                "items": [(material_id, quantity, unit_cost), ...]
            },
            ...
        ]
    """
    required_materials = calculate_required_materials(factory_quantities)
    supplier_lookup = get_supplier_lookup()

    grouped = {}

    for factory_id in required_materials:
        for material_id, quantity in required_materials[factory_id]:
            _material_id, supplier_id, _factory_id, unit_cost, lead_time_days = get_random_supplier(
                supplier_lookup, material_id, factory_id
            )

            key = (factory_id, supplier_id)
            grouped.setdefault(key, []).append(
                (material_id, quantity, unit_cost, lead_time_days)
            )

    purchase_orders_data = []

    for (factory_id, supplier_id), items in grouped.items():
        order_date = fake.date_between(purchase_start_date, purchase_end_date)
        max_lead_time = max(item[3] for item in items)
        expected_date = order_date + timedelta(days=max_lead_time)
        total_cost = sum(quantity * unit_cost for _material_id, quantity, unit_cost, _lead in items)

        purchase_orders_data.append({
            "factory_id": factory_id,
            "supplier_id": supplier_id,
            "order_date": order_date,
            "expected_date": expected_date,
            "total_cost": total_cost,
            "items": [
                (material_id, quantity, unit_cost)
                for material_id, quantity, unit_cost, _lead in items
            ],
        })

    return purchase_orders_data


def simulate_purchase_orders(purchase_orders_data, connection):
    """
    Inserts purchase_orders rows from already-generated data.
    """
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO purchase_orders
        (
            supplier_id,
            order_date,
            expected_date,
            total_cost,
            factory_id,
            status
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            'received'
        )
        RETURNING purchase_order_id;
    '''
    po_counter = 0
    for po in purchase_orders_data:
        cursor.execute(insert_query, (
            po["supplier_id"],
            po["order_date"],
            po["expected_date"],
            po["total_cost"],
            po["factory_id"],
        ))
        po["purchase_order_id"] = cursor.fetchone()[0]
        po_counter += 1


    cursor.close()

    print(f"{po_counter} purchase orders inserted successfully.")
    return purchase_orders_data


def simulate_purchase_order_items(purchase_orders_data, connection):
    """
    Inserts purchase_order_items rows using the SAME already-generated
    """
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO purchase_order_items
        (
            purchase_order_id,
            material_id,
            quantity,
            unit_cost,
            line_total,
            quantity_received
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s
        );
    '''

    rows = []
    poi_counter = 0
    for po in purchase_orders_data:
        purchase_order_id = po["purchase_order_id"]
        for material_id, quantity, unit_cost in po["items"]:
            line_total = round(quantity * unit_cost, 2)
            rows.append((
                purchase_order_id,
                material_id,
                quantity,
                unit_cost,
                line_total,
                quantity
            ))
            poi_counter += 1

    cursor.executemany(insert_query, rows)


    print(f"{poi_counter} purchase order items inserted successfully.")
    cursor.close()



if __name__ == "__main__":
    from datetime import date

    connection = get_connection()
    try:
        data = generate_purchase_order_data(
            {"F1": 1000, "F2": 800, "F3": 500},
            date(2026, 1, 1),
            date(2026, 1, 23),
        )
        data = simulate_purchase_orders(data, connection)
        simulate_purchase_order_items(data, connection)
        connection.commit()
    except Exception as e:
        connection.rollback()
        raise Exception(f"Test run failed: {e}")
    finally:
        connection.close()