from database.db_connection import get_connection


def get_unprocessed_received_items():
    """
    Returns purchase order items that have NOT yet been turned into
    a RECEIPT transaction.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('''
        SELECT
            i.purchase_order_item_id, i.material_id, i.quantity_received,
            o.factory_id, o.expected_date
        FROM purchase_order_items i
        JOIN purchase_orders o
            ON i.purchase_order_id = o.purchase_order_id
        LEFT JOIN inventory_transactions t
            ON t.purchase_order_item_id = i.purchase_order_item_id
        WHERE t.transaction_id IS NULL
        ORDER BY o.factory_id, i.material_id;
    ''')
    items = cursor.fetchall()

    cursor.close()
    connection.close()
    return items  # purchase_order_item_id, material_id, quantity_received, factory_id, expected_date


def record_receipt_transactions():
    """
    Turns any not-yet-processed purchase order items into RECEIPT
    rows in the ledger.
    """
    items = get_unprocessed_received_items()
    if not items:
        return 0

    connection = get_connection()
    cursor = connection.cursor()

    for purchase_order_item_id, material_id, quantity_received, factory_id, expected_date in items:
        cursor.execute('''
            INSERT INTO inventory_transactions
                (material_id, factory_id, quantity, transaction_type,
                 purchase_order_item_id, transaction_date)
            VALUES (%s, %s, %s, 'RECEIPT', %s, %s)
        ''', (material_id, factory_id, quantity_received,
              purchase_order_item_id, expected_date))

    connection.commit()
    cursor.close()
    connection.close()
    return len(items)


def record_consumption_transaction(material_id, factory_id, quantity, work_order_id=None, notes=None):
    """
    Records material used up in manufacturing. `quantity` should be
    passed as a positive number here — this function negates it
    before storing, so callers don't have to remember the sign convention.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('''
        INSERT INTO inventory_transactions
            (material_id, factory_id, quantity, transaction_type,
             work_order_id, notes)
        VALUES (%s, %s, %s, 'CONSUMPTION', %s, %s)
    ''', (material_id, factory_id, -abs(quantity), work_order_id, notes))

    connection.commit()
    cursor.close()
    connection.close()


def recompute_inventory_balances():
    """
    Rebuilds quantity_on_hand and last_updated for every
    (material_id, factory_id) pair by summing the full ledger.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('''
        INSERT INTO raw_materials_inventory
            (material_id, factory_id, quantity_on_hand, last_updated)
        SELECT
            material_id,
            factory_id,
            SUM(quantity),
            MAX(transaction_date)
        FROM inventory_transactions
        GROUP BY material_id, factory_id
        ON CONFLICT (material_id, factory_id)
        DO UPDATE SET
            quantity_on_hand = EXCLUDED.quantity_on_hand,
            last_updated = EXCLUDED.last_updated;
    ''')

    connection.commit()
    cursor.close()
    connection.close()


def seed_raw_materials_inventory():
    """
    Initial bootstrap AND ongoing updates use the same two steps:
    1. Turn any new purchase order items into ledger rows.
    2. Recompute balances from the full ledger.
    Safe to call on a fresh empty table or repeatedly afterward —
    already-processed purchases are skipped automatically.
    """
    record_receipt_transactions()
    recompute_inventory_balances()