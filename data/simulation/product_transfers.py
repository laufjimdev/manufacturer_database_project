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
        )
        RETURNING transfer_id;
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

    transfer_id = cursor.fetchone()[0]

    #Create product_inventory_transaction

    p_i_t_Q = '''
        INSERT INTO product_inventory_transactions
        (
            transaction_type,
            product_id,
            quantity,
            transfer_id
        )
        VALUES
        (
            'product_transfer',
            %s,
            %s,
            %s,
        );
'''
    cursor.execute(p_i_t_Q, (
        product_id,
        quantity,
        transfer_id
    ))

    cursor.close()
