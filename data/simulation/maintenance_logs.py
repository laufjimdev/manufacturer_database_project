from database.db_connection import get_connection
from datetime import timedelta, date
from decimal import Decimal
from faker import Faker
import random

fake = Faker()

TECHNICIAN_HOURLY_RATE_USD = Decimal("45.00")

def get_technicians(connection):
    cursor = connection.cursor()
    cursor.execute('''
        SELECT e.employee_id, e.factory_id
        FROM employees e
        JOIN departments d
        ON e.department_id = d.department_id
        WHERE d.department_name = 'Maintenance';
    ''')
    techs_factories = cursor.fetchall()
    cursor.close()

    factories_techs_dict = {}
    for tech, factory in techs_factories:
        factories_techs_dict.setdefault(factory, []).append(tech)

    return factories_techs_dict


def create_maintenance_log(connection, machine_id, maintenance_date, description, downtime_hours, cost, technician_employee_id):
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO maintenance_logs
        (
            machine_id,
            maintenance_date,
            description,
            downtime_hours,
            cost,
            technician_employee_id
        )
        VALUES
        (
            %s, %s, %s, %s, %s, %s
        );
    '''

    cursor.execute(insert_query, (
        machine_id,
        maintenance_date,
        description,
        downtime_hours,
        cost,
        technician_employee_id
    ))

    cursor.close()


def get_maint_plans(connection):
    cursor = connection.cursor()
    cursor.execute('''
        SELECT 
            mp.machine_id, 
            mp.maintenance_type, 
            mp.frequency_days, 
            mp.estimated_duration_hours,
            pl.factory_id
        FROM maintenance_plans mp
        JOIN machines m
        ON mp.machine_id = m.machine_id
        JOIN production_lines pl
        ON m.production_line_id = pl.production_line_id;
    ''')

    maint_plans = cursor.fetchall()
    cursor.close()
    return maint_plans

def simulate_maintenance_logs(connection, operation_start, operation_end):

    maint_plans = get_maint_plans(connection)
    factories_techs_dict = get_technicians(connection)

    logs_to_insert = []

    for machine_id, description, frequency_days, estimated_duration_hours, factory_id in maint_plans:
        available_techs = factories_techs_dict.get(factory_id)
        if not available_techs:
            raise ValueError(f"No maintenance technicians found for factory {factory_id}")

        maintenance_date = operation_start + timedelta(days=frequency_days)

        while maintenance_date <= operation_end:
            downtime_hours = random.choice([
                estimated_duration_hours - 1,
                estimated_duration_hours,
                estimated_duration_hours + 1,
            ])
            cost = round(downtime_hours * TECHNICIAN_HOURLY_RATE_USD, 2)
            technician_employee_id = random.choice(available_techs)

            logs_to_insert.append((
                machine_id, maintenance_date, description,
                downtime_hours, cost, technician_employee_id
            ))

            maintenance_date += timedelta(days=frequency_days)

    logs_to_insert.sort(key=lambda log: log[1])

    for machine_id, maintenance_date, description, downtime_hours, cost, technician_employee_id in logs_to_insert:
        create_maintenance_log(
            connection, machine_id, maintenance_date, description,
            downtime_hours, cost, technician_employee_id
        )

    print(f"{len(logs_to_insert)} maintenance logs inserted successfully.")

if __name__ == "__main__":
    connection = get_connection()
    operation_start = date(2026,2,1)
    operation_end = date(2026,5,1)
    try:
        simulate_maintenance_logs(connection, operation_start, operation_end)
        connection.commit()
    except Exception as e:
        connection.rollback()
        raise Exception(f"Failed to generate maintenance logs, error: {e}") 
    finally:
        connection.close()