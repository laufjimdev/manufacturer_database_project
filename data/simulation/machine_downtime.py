from database.db_connection import get_connection
from data.simulation.data_configs.machine_downtime_config import DOWNTIME_REASONS
from data.simulation.maintenance_logs import create_maintenance_log, get_technicians, TECHNICIAN_HOURLY_RATE_USD
from faker import Faker
from decimal import Decimal
from datetime import datetime, time, timedelta
import random

fake = Faker()


def get_machines(connection):
    cursor = connection.cursor()
    cursor.execute('''
        SELECT m.machine_id, p.factory_id
        FROM machines m
        JOIN production_lines p
        ON m.production_line_id = p.production_line_id;''')
    machines_factories = cursor.fetchall()
    cursor.close()
    return machines_factories


def simulate_machine_downtime(connection, start_date, end_date, downtime_logs_count=None):
    
    if not isinstance(start_date, datetime):
        start_date = datetime.combine(start_date, time.min)
    if not isinstance(end_date, datetime):
        end_date = datetime.combine(end_date, time.max)

    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO machine_downtime
        (
            machine_id,
            start_time,
            end_time,
            downtime_reason
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s
        );
    '''

    machines_factories = get_machines(connection)
    downtime_logs = downtime_logs_count or random.randint(1, len(machines_factories))
    downtime_m_logged = {}
    downtime_counter = 0

    for _ in range(downtime_logs):
        machine_id,factory_id = random.choice(machines_factories)
        downtime_reason, hours_range = random.choice(DOWNTIME_REASONS)
        impact_hours = Decimal(round(random.uniform(*hours_range), 2))

        previous_ends = downtime_m_logged.get(machine_id)

        if previous_ends:
            start_time = max(previous_ends) + timedelta(days=random.randint(1, 5))
            if start_time > end_date:
                continue 
        else:
            start_time = fake.date_time_between(start_date, end_date)

        end_time = start_time + timedelta(hours=float(impact_hours))
        downtime_m_logged.setdefault(machine_id, []).append(end_time)

        cursor.execute(insert_query, (
            machine_id,
            start_time,
            end_time,
            downtime_reason
        ))

        factories_techs_dict = get_technicians(connection) 
        available_techs = factories_techs_dict[factory_id]
        technician_employee_id = random.choice(available_techs)

        cost = round(impact_hours * TECHNICIAN_HOURLY_RATE_USD, 2)
        create_maintenance_log(connection, machine_id, start_time, downtime_reason, impact_hours, cost, technician_employee_id)
        downtime_counter += 1
    cursor.close()


    print(f"{downtime_counter} machine downtime logs successfully inserted.")

if __name__ == "__main__":
    connection = get_connection()
    simulate_machine_downtime(connection, start_date=datetime(2026, 3, 1), end_date=datetime(2026, 3, 30))