from data.simulation.products_inventory import record_transfer_transaction

def create_product_transfer(connection, work_order_id, factory_id, product_id,
            quantity, shipped_date, received_date):
    cursor = connection.cursor()

    warehouse_lookupQ = '''
        SELECT w.warehouse_id, w.storage_capacity_units
        FROM factory_warehouse_links fwl
        JOIN warehouses w ON w.warehouse_id = fwl.warehouse_id
        WHERE fwl.factory_id = %s AND fwl.role = 'primary';
    '''
    cursor.execute(warehouse_lookupQ, (factory_id,))
    warehouses = cursor.fetchall()  # [(warehouse_id, storage_capacity_units), ...]

    if not warehouses:
        cursor.close()
        raise ValueError(f"No primary warehouses found for factory {factory_id}")

    total_capacity = sum(capacity for _, capacity in warehouses)
    if total_capacity <= 0:
        cursor.close()
        raise ValueError(f"Primary warehouses for factory {factory_id} have zero total capacity")

    insert_transfer_query = '''
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

    remaining_quantity = quantity
    for i, (warehouse_id, capacity) in enumerate(warehouses):
        if i == len(warehouses) - 1:
            # Last warehouse absorbs any rounding remainder so totals match exactly
            wh_quantity = remaining_quantity
        else:
            wh_quantity = quantity * (capacity / total_capacity)
            remaining_quantity -= wh_quantity

        cursor.execute(insert_transfer_query, (
            work_order_id,
            factory_id,
            warehouse_id,
            product_id,
            wh_quantity,
            shipped_date,
            received_date,
        ))
        transfer_id = cursor.fetchone()[0]

        record_transfer_transaction(connection, product_id, wh_quantity, transfer_id)

    cursor.close()