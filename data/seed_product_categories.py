from database.db_connection import get_connection


CATEGORIES = [
    ("Wood-ET", "Wood Composite Event Tables"),
    ("Aluminum-ET", "Aluminum Frame Event Tables"),
    ("Heavy-Duty-T", "Heavy-Duty Commercial Tables"),
    ("Specialty-ET","Specialty Event Tables")
]
def seed_product_categories():

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO product_categories 
        (
            category_name,
            description    
        )
        VALUES
        (
            %s,
            %s
        )
'''
    for category_name, descripton  in CATEGORIES:
        cursor.execute(insert_query, (
            category_name,
            descripton
        ))

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM product_categories;')
    rows = cursor.fetchall()

    cursor.close()
    connection.close()

    print(f"{len(rows)} categories inserted successfully.")

def get_category_ids():
    connection= get_connection()
    cursor= connection.cursor()

    cursor.execute("SELECT category_id, category_name FROM product_categories;")
    category_ids = cursor.fetchall()

    cursor.close()
    connection.close()

    return category_ids


if __name__ == "__main__":
    seed_product_categories()