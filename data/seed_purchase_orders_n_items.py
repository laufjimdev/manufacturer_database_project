from database.db_connection import get_connection
from data.data_configs.product_bom_config import calculate_required_materials
from data.seed_raw_material_suppliers import get_supplier_lookup, get_random_supplier
from datetime import date, timedelta
from faker import Faker

fake = Faker()

FACTORY_BASE_QUANTITIES = {
    "F1": 1000,
    "F2": 800,
    "F3": 500,
}


def generate_purchase_order_data():
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
    required_materials = calculate_required_materials(FACTORY_BASE_QUANTITIES)
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
        order_date = fake.date_between(date(2026, 1, 1), date(2026, 1, 23))
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


def seed_purchase_orders(purchase_orders_data, connection):
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

    for po in purchase_orders_data:
        cursor.execute(insert_query, (
            po["supplier_id"],
            po["order_date"],
            po["expected_date"],
            po["total_cost"],
            po["factory_id"],
        ))
        po["purchase_order_id"] = cursor.fetchone()[0]


    cursor.execute('SELECT COUNT(*) FROM purchase_orders;')
    po_rows = cursor.fetchone()[0]

    cursor.close()

    print(f"{po_rows} purchase orders inserted successfully.")


def seed_purchase_order_items(purchase_orders_data, connection):
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
            line_total
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s
        );
    '''

    rows = []

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
            ))

    cursor.executemany(insert_query, rows)

    cursor.execute('SELECT COUNT(*) FROM purchase_order_items;')
    item_rows = cursor.fetchone()[0]

    cursor.close()

    print(f"{item_rows} purchase order items inserted successfully.")

def seed_purchase_orders_n_items():
    connection = get_connection()

    try:
        purchase_orders_data = generate_purchase_order_data()
        seed_purchase_orders(purchase_orders_data, connection)
        seed_purchase_order_items(purchase_orders_data, connection)

        connection.commit()
        print("Purchase orders and items committed successfully.")

    except Exception as e:
        connection.rollback()
        print(f"Failed to seed purchase orders and items, rolled back: {e}")
        raise

    finally:
        connection.close()

if __name__ == "__main__":
    seed_purchase_orders_n_items()