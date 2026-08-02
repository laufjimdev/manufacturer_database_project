from database.db_connection import get_connection

PRODUCTION_LINES = [
    ("F1", "Wood Composite Line A", "Wood Composite", 320),
    ("F1", "Wood Composite Line B", "Wood Composite", 300),
    ("F1", "Aluminum Fabrication Line", "Aluminum", 220),
    ("F1", "Heavy-Duty Stainless Line", "Stainless Steel", 160),
    ("F1", "Specialty Glass Assembly Line", "Specialty Assembly", 80),
    ("F2", "Wood Composite Line", "Wood Composite", 300),
    ("F2", "Aluminum Fabrication Line", "Aluminum", 180),
    ("F2", "Heavy-Duty Stainless Line", "Stainless Steel", 120),
    ("F2", "Specialty Glass Assembly Line", "Specialty Assembly", 60),
    ("F3", "Wood Composite Line", "Wood Composite", 280),
    ("F3", "Aluminum Fabrication Line", "Aluminum", 170),
    ("F3", "Heavy-Duty Stainless Line", "Stainless Steel", 120),
    ("F3", "Specialty Glass Assembly Line", "Specialty Assembly", 60),
]

def seed_production_lines():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO production_lines 
        (
            factory_id,
            line_name,
            line_type,
            capacity_per_day,
            status
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            'active'
        )
'''

    for factory_id, line_name, line_type, capacity_per_day in PRODUCTION_LINES:
        cursor.execute(insert_query, (
            factory_id,
            line_name,
            line_type,
            capacity_per_day
        ))

    connection.commit()
    cursor.close()
    connection.close()

    print(f"{len(PRODUCTION_LINES)} production lines inserted")

def get_production_lines_ids():
    '''
        Fetches the production_line_id, factory_id and line_type from the production_lines table
    '''
    connection= get_connection()
    cursor= connection.cursor()

    cursor.execute('SELECT production_line_id, factory_id, line_type FROM production_lines;')
    production_lines_ids= cursor.fetchall()

    cursor.close()
    connection.close()

    return production_lines_ids

if __name__ == "__main__":
    seed_production_lines()