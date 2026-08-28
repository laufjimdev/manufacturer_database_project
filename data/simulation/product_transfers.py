from database.db_connection import get_connection

def create_product_transfer(connection,work_order_id, factory_id, product_id,
            quantity, shipped_date, received_date):
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO product_transfers
        (
            work_order_id,
            factory_id,
            warehouse_id,
            product_id,
            quantity,
            shipped_date,
            received_date,
            status
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            'received'
        );
'''
    warehouse_lookupQ = "SELECT warehouse_id FROM factory_warehouse_links WHERE factory_id = %s AND role = 'primary';"

    cursor.execute(warehouse_lookupQ, (factory_id, ))
    warehouse_id = cursor.fetchone()[0]

    cursor.execute(insert_query, (
        work_order_id,
        factory_id,
        warehouse_id,
        product_id,
        quantity,
        shipped_date,
        received_date,
    ))

    cursor.close()
