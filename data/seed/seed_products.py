from database.db_connection import get_connection
from data.seed.data_configs.products_config import PRODUCTS
from data.seed.seed_product_categories import get_category_ids

def seed_products():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO products 
        (
            product_name,
            description,
            category_id,
            dimensions,
            weight_lb,
            load_capacity,
            active_flag
        )
        VALUES 
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            'true'
        )
'''

    category_ids_list = get_category_ids()
    category_map = {category_name: category_id for category_id, category_name in category_ids_list}

    for product_name, description, category_n, dimensions, weight_lb,load_capacity, line_name in PRODUCTS:
        cursor.execute(insert_query, (
            product_name,
            description,
            category_map[category_n],
            dimensions,
            weight_lb,
            load_capacity
        ))

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM products;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} products inserted successfully")

if __name__ == "__main__":
    seed_products()
