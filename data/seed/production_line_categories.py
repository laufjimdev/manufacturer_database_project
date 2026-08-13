from database.db_connection import get_connection
from data.seed.data_configs.production_line_categories_config import PRODUCTION_TYPE_CATEGORY_MAP

def seed_production_line_categories():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO production_line_categories
        (
            production_line_id,
            category_id
        )
        VALUES
        (
            %s,
            %s
        )
        ON CONFLICT (production_line_id, category_id)
        DO NOTHING;
'''

    cursor.execute('SELECT category_id, category_name FROM product_categories;')
    product_categories = cursor.fetchall()

    product_categories_dict = {}

    for category_id, category_name in product_categories:
        product_categories_dict[category_name] = category_id

    cursor.execute('SELECT production_line_id, line_type FROM production_lines;')
    production_lines_cat = cursor.fetchall()

    for production_line_id, line_type in production_lines_cat:
        cat_name = PRODUCTION_TYPE_CATEGORY_MAP[line_type][0]
        cursor.execute(insert_query, (
            production_line_id,
            product_categories_dict[cat_name]
        ))

    connection.commit()

    cursor.execute('SELECT COUNT(*) FROM production_line_categories;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} production line categories successfully inserted.")

if __name__ == "__main__":
    seed_production_line_categories()

