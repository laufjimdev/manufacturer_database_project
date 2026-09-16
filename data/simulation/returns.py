from database.db_connection import get_connection
from data.simulation.products_inventory import record_restocked_transaction
from datetime import timedelta
import random

RETURN_REASON_CONFIG = {
    "defective": (
        ["damaged", "unusable"],
        ["resolved"],
        ["refund", "replacement", "repair"],
    ),
    "no longer need": (
        ["good"],
        ["resolved"],
        ["refund", "store_credit"],
    ),
    "ordered wrong size": (
        ["good"],
        ["resolved"],
        ["refund", "replacement", "store_credit"],
    ),
    "wrong item shipped": (
        ["good"],
        ["resolved"],
        ["replacement", "refund"],
    ),
    "late delivery": (
        ["good", "unknown"],
        ["resolved", "rejected"],
        ["refund", "rejected"],
    ),
}

def get_warehouse_shipping_empl(connection):
    '''Gets a list of all the Shipping & Dispatch employees by warehouse and returns a dict keyed by warehouse_id'''

    cursor = connection.cursor()

    query = '''
        SELECT e.employee_id, d.warehouse_id
        FROM employees e
        LEFT JOIN departments d
        ON e.department_id = d.department_id
        WHERE d.department_name = 'Shipping & Dispatch';
    '''
    cursor.execute(query)
    shippng_employees = cursor.fetchall()

    shippng_employees_dict = {}

    for employee_id, warehouse_id in shippng_employees:
        shippng_employees_dict.setdefault(warehouse_id, []).append(employee_id)

    cursor.close()
    return shippng_employees_dict



def get_orders_to_return(connection, returns_count):
    '''Pulls sales orders info and returns random sales orders to simulate a return'''

    cursor = connection.cursor()
    query = '''
        SELECT 
            so.sales_order_id, 
            s.customer_id,
            so.product_id, 
            so.quantity,
            sh.delivery_date, 
            so.unit_price,
            s.warehouse_id
        FROM sales_order_items so
        LEFT JOIN sales_orders s
        ON so.sales_order_id = s.sales_order_id
        LEFT JOIN shipments sh
        ON so.sales_order_id = sh.sales_order_id
        ORDER BY RANDOM()
        LIMIT %s;
    '''
    cursor.execute(query, (returns_count,))
    sales_orders_data = cursor.fetchall()
    cursor.close()
    return sales_orders_data

def simulate_returns(connection, returns_count):
    
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO returns
        (
            sales_order_id,
            customer_id,
            product_id,
            quantity,
            return_date,
            reason,
            condition,
            status,
            resolution,
            refund_amount,
            restocked,
            warehouse_id,
            handled_by_employee_id
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
            %s,
            %s,
            %s,
            %s,
            %s,
            %s
        )RETURNING return_id;
    '''

    sales_orders_data = get_orders_to_return(connection, returns_count[0])

    returns_inserted = 0
    shippng_employees_dict = get_warehouse_shipping_empl(connection)

    for sales_order_id, customer_id, product_id, quantity, delivery_date, unit_price, warehouse_id in sales_orders_data:
        return_quantity = random.randint(1, quantity)
        return_date = delivery_date + timedelta(days=random.randint(3,7))
        reason = random.choice(list(RETURN_REASON_CONFIG.keys()))
        condition = random.choice(RETURN_REASON_CONFIG[reason][0])
        status = random.choice(RETURN_REASON_CONFIG[reason][1])
        resolution = random.choice(RETURN_REASON_CONFIG[reason][2])
        if resolution == 'refund':
            refund_amount = return_quantity * unit_price
        else:
            refund_amount = 0

        if condition == 'good':
            restocked = True
        else:
           restocked = False 
        
        handled_by_employee_id = random.choice(shippng_employees_dict[warehouse_id])

        cursor.execute(insert_query, (
            sales_order_id,
            customer_id,
            product_id,
            return_quantity,
            return_date,
            reason,
            condition,
            status,
            resolution,
            refund_amount,
            restocked,
            warehouse_id,
            handled_by_employee_id
        ))
        returns_inserted += 1
        return_id = cursor.fetchone()[0]

        if restocked:
            record_restocked_transaction(connection, product_id, return_quantity, return_id)

    cursor.close()

    print(f"{returns_inserted} return orders sucessfully inserted.")

if __name__ == "__main__":
    returns_count = 10
    simulate_returns(returns_count)
