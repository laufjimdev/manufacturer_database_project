from database.db_connection import get_connection
from data.seed.data_configs.maintenance_plans_config import MAINTENANCE_PLANS_BY_MACHINE_TYPE

def seed_maintenance_plans():
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute('SELECT machine_id, machine_type FROM machines;')
    machines = cursor.fetchall()

    insert_query = '''
        INSERT INTO maintenance_plans
        (
            machine_id,
            maintenance_type,
            frequency_days,
            estimated_duration_hours
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s
        );
'''

    for machine_id, machine_type in machines:
        maintenance_type, frequency_days, estimated_duration_hours = MAINTENANCE_PLANS_BY_MACHINE_TYPE[machine_type]
        cursor.execute(insert_query,(
            machine_id,
            maintenance_type,
            frequency_days,
            estimated_duration_hours
        ))

    connection.commit()

    cursor.execute('SELECT COUNT(*) FROM maintenance_plans;')
    rows = cursor.fetchone()[0]

    print(f"{rows} maintenance plans successfully inserted.")


if __name__ == "__main__":
    seed_maintenance_plans()