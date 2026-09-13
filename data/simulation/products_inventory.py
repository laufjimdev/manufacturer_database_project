import math
from database.db_connection import get_connection


def get_inventory_balances(connection):
    """
    Computes the current net quantity_on_hand per (product_id, warehouse_id)
    directly from the product_inventory_transactions ledger — the source of
    truth for finished goods inventory. Used both to refresh the
    products_inventory snapshot table and to give sales order generation a
    live starting point for checking stock availability before committing
    sales, since a stale snapshot could allow overselling.

    Returns: {(product_id, warehouse_id): net_quantity}
    """
    cursor = connection.cursor()

    cursor.execute('''
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
    ''')
    rows = cursor.fetchall()
    cursor.close()

    return {(product_id, warehouse_id): int(net_quantity) for product_id, warehouse_id, net_quantity in rows}

def record_transfer_transaction(connection, product_id, quantity, transfer_id):
    """
    Records finished goods arriving at a warehouse via a factory-to-warehouse
    product transfer. `quantity` should be passed as a positive number —
    this function does NOT negate it, since a transfer is an inbound
    addition to warehouse stock (unlike record_sale_transaction, which
    negates because a sale is an outbound deduction).
    Called from data.simulation.product_transfers.
    """
    cursor = connection.cursor()

    cursor.execute('''
        INSERT INTO product_inventory_transactions
            (transaction_type, product_id, quantity, transfer_id)
        VALUES ('product_transfer', %s, %s, %s)
    ''', (product_id, quantity, transfer_id))

    cursor.close()

def record_sale_transaction(connection, product_id, quantity, sales_order_id):
    """
    Records a product sold out of warehouse inventory. `quantity` should be
    passed as a positive number — this function negates it before storing,
    consistent with record_consumption_transaction's sign convention in
    raw_materials_inventory.py. warehouse_id isn't stored on this row
    directly: it's derived downstream via the sales_order_id -> sales_orders
    join, the same way every other transaction type in this ledger works.
    Called from data.simulation.sales_orders_n_items.
    """
    cursor = connection.cursor()

    cursor.execute('''
        INSERT INTO product_inventory_transactions
            (transaction_type, product_id, quantity, sales_order_id)
        VALUES ('sale', %s, %s, %s)
    ''', (product_id, -abs(quantity), sales_order_id))

    cursor.close()


def recompute_products_inventory_balances(connection):
    """
    Rebuilds quantity_on_hand and last_updated for every (product_id,
    warehouse_id) pair by summing the full ledger. Mirrors
    recompute_inventory_balances() in raw_materials_inventory.py.
    Requires the products_inventory_product_warehouse_key unique
    constraint on (product_id, warehouse_id) for ON CONFLICT to work.
    """
    balances = get_inventory_balances(connection)

    cursor = connection.cursor()

    upsert_query = '''
        INSERT INTO products_inventory
            (warehouse_id, product_id, quantity_on_hand, last_updated)
        VALUES (%s, %s, %s, LOCALTIMESTAMP)
        ON CONFLICT (product_id, warehouse_id)
        DO UPDATE SET
            quantity_on_hand = EXCLUDED.quantity_on_hand,
            last_updated = EXCLUDED.last_updated;
    '''

    for (product_id, warehouse_id), quantity_on_hand in balances.items():
        cursor.execute(upsert_query, (warehouse_id, product_id, quantity_on_hand))

    cursor.close()


def simulate_products_inventory():
    """
    Standalone Airflow task entry point: refreshes the products_inventory
    snapshot from the ledger. Safe to call repeatedly — each call fully
    re-syncs the snapshot to the ledger's current state.
    """
    connection = get_connection()
    try:
        recompute_products_inventory_balances(connection)
        connection.commit()
    except Exception as e:
        connection.rollback()
        print(f"Failed to recompute products_inventory, rolled back: {e}")
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    simulate_products_inventory()