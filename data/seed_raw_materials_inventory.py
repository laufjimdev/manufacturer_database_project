from database.db_connection import get_connection

def get_received_items(cursor):

    cursor.execute('''
                    SELECT 
                        i.material_id, i.quantity_received,
                        o.factory_id, o.expected_date
                    FROM purchase_order_items i
                    JOIN purchase_orders o
                    ON i.purchase_order_id = o.purchase_order_id
                    ORDER BY o.factory_id, i.material_id;
''')
    received_items = cursor.fetchall()

    return received_items  # Returns material_id, quantity_received, factory_id, expected_date


def seed_raw_materials_inventory():
    connection = get_connection()
    cursor = connection.cursor()

    received_items = get_received_items(cursor)

    # key: (material_id, factory_id) -> {"quantity": total, "last_date": latest expected_date}
    aggregated = {}

    for material_id, quantity_received, factory_id, expected_date in received_items:
        if not material_id or not factory_id:
            continue

        key = (material_id, factory_id)

        if key not in aggregated:
            aggregated[key] = {
                "quantity": quantity_received,
                "last_date": expected_date
            }
        else:
            aggregated[key]["quantity"] += quantity_received
            if expected_date and expected_date > aggregated[key]["last_date"]:
                aggregated[key]["last_date"] = expected_date

    insert_query = '''
            INSERT INTO raw_materials_inventory
                (material_id, factory_id, quantity_on_hand, last_updated)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (material_id, factory_id)
            DO UPDATE SET
                quantity_on_hand = EXCLUDED.quantity_on_hand,
                last_updated = EXCLUDED.last_updated;
'''

    for (material_id, factory_id), data in aggregated.items():
        cursor.execute(insert_query, (
            material_id, 
            factory_id, 
            data["quantity"], 
            data["last_date"]))

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM raw_materials_inventory WHERE DATE(last_updated) = CURRENT_DATE;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} materials inventory updated successfully today.")