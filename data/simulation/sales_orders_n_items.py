import math
from database.db_connection import get_connection
from data.seed.data_configs.warehouse_regions_config import get_state_to_warehouse_map
from data.seed.data_configs.product_bom_config import PRODUCT_RATIOS
from data.simulation.products_inventory import get_inventory_balances, record_sale_transaction
from data.simulation.shipments import create_shipment
from faker import Faker
import random

fake = Faker()

LINE_ITEM_QUANTITY_RANGE = (1, 6)  # tables per order line — placeholder, tune freely

# Caps how much of a product's available warehouse stock this batch of
# sales orders is allowed to draw down, so a simulation run sells slightly
# less than what's been produced rather than draining stock to zero.
MAX_SELLABLE_RATIO = 0.85


def get_customers_by_warehouse():
    """
    Groups customers by warehouse using each customer's state and the
    static state-to-warehouse regional map, so a sales order is only ever
    assigned to a customer the warehouse actually serves.

    Returns: {warehouse_id: [(customer_id, shipping_address), ...]}
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('''
        SELECT customer_id, billing_address_st, city, state, zipcode
        FROM customers;
    ''')
    customers_data = cursor.fetchall()

    cursor.close()
    connection.close()

    state_to_warehouse = get_state_to_warehouse_map()

    customers_by_warehouse = {}
    for customer_id, street, city, state, zipcode in customers_data:
        warehouse_id = state_to_warehouse.get(state)
        if warehouse_id is None:
            continue  # state not covered by any region (shouldn't occur for continental customers)
        shipping_address = f"{street}, {city}, {state}, {zipcode}"
        customers_by_warehouse.setdefault(warehouse_id, []).append(
            (customer_id, shipping_address)
        )

    return customers_by_warehouse


def get_product_price_lookup():
    """
    Returns {product_id: selling_price} pulled from the products table.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('SELECT product_id, selling_price FROM products;')
    prices = cursor.fetchall()

    cursor.close()
    connection.close()

    return {product_id: float(selling_price) for product_id, selling_price in prices}


def get_sellable_inventory(connection):
    """
    Reads live ledger balances and applies MAX_SELLABLE_RATIO to get a
    sellable cap per (product_id, warehouse_id) for this batch.

    Returns: {(product_id, warehouse_id): sellable_quantity}
    """
    balances = get_inventory_balances(connection)
    return {
        key: max(0, math.floor(quantity * MAX_SELLABLE_RATIO))
        for key, quantity in balances.items()
    }


def _choose_order_products(price_lookup, available_balances, warehouse_id, max_line_items=3):
    """
    Picks up to max_line_items DISTINCT products for a single order,
    weighted by PRODUCT_RATIOS — the same relative scale already used to
    size production, so product_id 12 (ratio 0.08) shows up far less often
    than product_id 1 (ratio 1.0). R

    available_balances is mutated in place: chosen quantities are deducted
    immediately so later orders in the same batch see reduced stock and
    can't oversell it. Products with zero sellable stock for this warehouse
    are skipped rather than forced into the order.

    Returns a list of (product_id, quantity, unit_price) — may be shorter
    than max_line_items, or empty, if this warehouse is out of sellable
    stock for the products drawn.
    """
    remaining_ids = list(PRODUCT_RATIOS.keys())
    remaining_weights = list(PRODUCT_RATIOS.values())

    line_item_count = min(random.randint(1, max_line_items), len(remaining_ids))

    chosen_products = []
    for _ in range(line_item_count):
        if not remaining_ids:
            break

        product_id = random.choices(remaining_ids, weights=remaining_weights, k=1)[0]
        idx = remaining_ids.index(product_id)
        remaining_ids.pop(idx)
        remaining_weights.pop(idx)

        key = (product_id, warehouse_id)
        sellable = available_balances.get(key, 0)
        if sellable <= 0:
            continue  # out of sellable stock for this product at this warehouse

        desired_quantity = random.randint(*LINE_ITEM_QUANTITY_RANGE)
        quantity = min(desired_quantity, sellable)

        available_balances[key] = sellable - quantity
        unit_price = price_lookup[product_id]
        chosen_products.append((product_id, quantity, unit_price))

    return chosen_products


def generate_sales_order_data(sales_orders_by_warehouse, customers_by_warehouse_count,
                               sale_start_date, sale_end_date, connection):
    """
    sales_orders_by_warehouse: {"W1": 500, "W2": 300, ...} — how many sales
        orders to ATTEMPT generating for each warehouse. Orders that end up
        with zero sellable line items (warehouse out of stock for every
        product drawn) are skipped, so actual counts may come in lower.
    customers_by_warehouse_count: {"W1": 150, "W2": 90, ...} — how many
        distinct customers, drawn from that warehouse's regional pool, to
        spread those orders across.
    connection: used to read current ledger inventory balances before
        generating orders, so sales never exceed what's actually on hand.

    Returns:
        [
            {
                "customer_id": int,
                "warehouse_id": str,
                "order_date": date,
                "shipping_address": str,
                "total_amount": float,
                "items": [(product_id, quantity, unit_price), ...],
            },
            ...
        ]
    """
    customers_by_warehouse = get_customers_by_warehouse()
    price_lookup = get_product_price_lookup()
    available_balances = get_sellable_inventory(connection)

    sales_orders_data = []
    skipped_orders = 0

    for warehouse_id, order_count in sales_orders_by_warehouse.items():
        available_customers = customers_by_warehouse.get(warehouse_id)
        if not available_customers:
            raise ValueError(f"No customers found in the region served by warehouse {warehouse_id}")

        customer_count = min(
            customers_by_warehouse_count.get(warehouse_id, len(available_customers)),
            len(available_customers)
        )
        selected_customers = random.sample(available_customers, customer_count)

        for _ in range(order_count):
            items = _choose_order_products(price_lookup, available_balances, warehouse_id)

            if not items:
                skipped_orders += 1
                continue  # warehouse had no sellable stock left for any product drawn

            customer_id, shipping_address = random.choice(selected_customers)
            order_date = fake.date_between(sale_start_date, sale_end_date)
            total_amount = round(sum(quantity * unit_price for _pid, quantity, unit_price in items), 2)

            sales_orders_data.append({
                "customer_id": customer_id,
                "warehouse_id": warehouse_id,
                "order_date": order_date,
                "shipping_address": shipping_address,
                "total_amount": total_amount,
                "items": items,
            })

    if skipped_orders:
        print(f"{skipped_orders} sales orders skipped: no sellable stock available.")

    return sales_orders_data


def simulate_sales_orders(sales_orders_data, connection):
    """
    Inserts sales_orders rows from already-generated data.
    """
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO sales_orders
        (
            customer_id,
            order_date,
            status,
            total_amount,
            warehouse_id,
            shipping_address
        )
        VALUES
        (
            %s,
            %s,
            'delivered',
            %s,
            %s,
            %s
        )
        RETURNING sales_order_id;
    '''

    so_counter = 0
    for order in sales_orders_data:
        customer_id = order["customer_id"]
        order_date = order["order_date"]
        total_amount = order["total_amount"]
        warehouse_id = order["warehouse_id"]
        shipping_address = order["shipping_address"]

        cursor.execute(insert_query, (
            customer_id,
            order_date,
            total_amount,
            warehouse_id,
            shipping_address,
        ))

        sales_order_id = cursor.fetchone()[0]
        order["sales_order_id"] = sales_order_id

        create_shipment(connection, sales_order_id, warehouse_id, order_date)
        so_counter += 1

    cursor.close()

    print(f"{so_counter} sales orders inserted successfully.")
    return sales_orders_data

def simulate_sales_order_items(sales_orders_data, connection):
    """
    Inserts sales_order_items rows and records the matching outbound
    ledger entry for each line item in product_inventory_transactions.
    Availability was already checked and reserved against
    available_balances during generation — this just persists that
    decision. Not executemany'd, since each row insert is paired with its
    own ledger write, same as consumption transactions in work_orders.py.
    """
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO sales_order_items
        (
            sales_order_id,
            product_id,
            quantity,
            unit_price,
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

    soi_counter = 0
    for order in sales_orders_data:
        sales_order_id = order["sales_order_id"]
        for product_id, quantity, unit_price in order["items"]:
            line_total = round(quantity * unit_price, 2)
            cursor.execute(insert_query, (
                sales_order_id,
                product_id,
                quantity,
                unit_price,
                line_total,
            ))
            record_sale_transaction(connection, product_id, quantity, sales_order_id)
            soi_counter += 1

    print(f"{soi_counter} sales order items inserted successfully.")
    cursor.close()


if __name__ == "__main__":
    from datetime import date

    connection = get_connection()
    try:
        sales_orders_by_warehouse = {"W1": 500, "W2": 250, "W3": 200, "W4": 180}
        customers_by_warehouse_count = {"W1": 150, "W2": 90, "W3": 70, "W4": 60}

        data = generate_sales_order_data(
            sales_orders_by_warehouse,
            customers_by_warehouse_count,
            date(2026, 3, 1),
            date(2026, 3, 30),
            connection,
        )
        data = simulate_sales_orders(data, connection)
        simulate_sales_order_items(data, connection)
        connection.commit()
    except Exception as e:
        connection.rollback()
        raise Exception(f"Test run failed: {e}")
    finally:
        connection.close()