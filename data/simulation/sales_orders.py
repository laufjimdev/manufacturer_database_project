from database.db_connection import get_connection

def simulate_sales_orders():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO sales_orders
        (
            
        )
'''