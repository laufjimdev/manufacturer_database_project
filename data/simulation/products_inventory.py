from database.db_connection import get_connection

def simulate_products_inventory():
    connection = get_connection()
    cursor = connection.cursor()

    fetch_data_Q = '''
        SELECT 
            pi.product_id,
            COALESCE(pt.warehouse_id, s.warehouse_id, r.warehouse_id) AS warehouse_id,
            SUM(pi.quantity) AS net_quantity
        FROM public.product_inventory_transactions pi
        LEFT JOIN public.product_transfers pt
            ON pi.transfer_id = pt.transfer_id
        LEFT JOIN public.sales_orders s
            ON pi.sales_order_id = s.sales_order_id
        LEFT JOIN public.returns r
            ON pi.return_id = r.return_id
        GROUP BY pi.product_id, COALESCE(pt.warehouse_id, s.warehouse_id, r.warehouse_id)
        ORDER BY pi.product_id, warehouse_id;
'''
    cursor.execute(fetch_data_Q)
    inventory = cursor.fetchall()

    insert_query = '''
        INSERT INTO products_inventory
        (
           warehouse_id,
           product_id,
           quantity_on_hand,
           last_updated
        )
        VALUES
        (
            %s,
            %s,
            %s,
            LOCALTIMESTAMP
        );
'''
    
    for product_id, warehouse_id, quantity_on_hand in inventory:
        cursor.execute(insert_query,(
            warehouse_id,
            product_id,
            quantity_on_hand 
        ))

    cursor.close()
    connection.commit()
    connection.close()

if __name__ == "__main__":
    simulate_products_inventory()