from database.db_connection import get_connection
from data.data_configs.product_bom_config import PRODUCT_MATERIALS

def seed_product_bom():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO product_bom 
        (
            product_id,
            material_id,
            quantity_required
        )
        VALUES
        (
            %s,
            %s,
            %s
        )
'''
    products_count = len(PRODUCT_MATERIALS.keys())

    for x in range(1, products_count + 1):
        for material_id, quantity_required in PRODUCT_MATERIALS[x]:
            cursor.execute(insert_query, (
                x,
                material_id,
                quantity_required
            ))

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM product_bom;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} product boms successfully inserted")

if __name__ == "__main__":
    seed_product_bom()