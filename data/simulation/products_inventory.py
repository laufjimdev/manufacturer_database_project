from database.db_connection import get_connection

def simulate_products_inventory():
    connection = get_connection()
    cursor = connection.cursor()

    fetch_data_Q = '''
        SELECT 
'''