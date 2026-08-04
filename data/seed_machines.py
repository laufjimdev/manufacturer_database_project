from database.db_connection import get_connection
from data.data_configs.machines_config import MACHINES
from datetime import date
from faker import Faker

fake = Faker()

def seed_machines():
    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO machines 
        (
            production_line_id,
            machine_name,
            machine_type,
            install_date,
            hourly_rate_usd,
            maintenance_cycle_days,
            status
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            'active'
        )
'''

    for production_line_id, machine_name, machine_type, hourly_rate_usd, maintenance_cycle_days in MACHINES:
        cursor.execute(insert_query, (
            production_line_id,
            machine_name,
            machine_type,
            fake.date_between(start_date=date(2025, 2, 1), end_date=date(2025, 7, 1)),
            hourly_rate_usd,
            maintenance_cycle_days
        ))

    connection.commit()

    cursor.execute('SELECT COUNT(*) FROM machines;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} machines inserted successfully.")

if __name__ == "__main__":
    seed_machines()