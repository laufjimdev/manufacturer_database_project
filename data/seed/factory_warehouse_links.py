from database.db_connection import get_connection
from data.seed.data_configs.factory_warehouse_config import FACTORY_WAREHOUSE_LINKS

def seed_factory_warehouse_links():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO factory_warehouse_links
        (
            warehouse_id,
            factory_id,
            role
        )
        VALUES
        (
            %s,
            %s,
            %s
        )
        ON CONFLICT (factory_id, warehouse_id)
        DO NOTHING;
    '''

    cursor.executemany(insert_query, FACTORY_WAREHOUSE_LINKS)

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM factory_warehouse_links;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} factory-warehouse links inserted successfully.")

if __name__ == "__main__":
    seed_factory_warehouse_links()