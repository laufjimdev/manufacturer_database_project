from database.db_connection import get_connection
from data.employees_config import FACTORY_STAFFING, WAREHOUSE_STAFFING
from data.seed_departments import FACTORY_DEPARTMENTS, WAREHOUSE_DEPARTMENTS
from datetime import date
from faker import Faker
import random

fake = Faker()


def _build_department_id_map(department_names):
    """
    Reconstructs department_name using the same enumeration order used in seed_departments.py.
    """
    return {
        name: f'd{index}'
        for index, name in enumerate(department_names, start=1)
    }


FACTORY_DEPT_SUFFIX = _build_department_id_map(FACTORY_DEPARTMENTS)
WAREHOUSE_DEPT_SUFFIX = _build_department_id_map(WAREHOUSE_DEPARTMENTS)


def _build_employee_record(department_id, factory_id=None, warehouse_id=None):
    first_name = fake.first_name()
    last_name = fake.last_name()
    email = fake.unique.email()
    phone = fake.numerify("###-###-####")
    hire_date = fake.date_between(start_date=date(2025, 7, 1), end_date=date(2025, 12, 20))

    return (
        first_name,
        last_name,
        email,
        phone,
        department_id,
        factory_id,
        warehouse_id,
        hire_date,
    )


def _generate_employees_from_staffing(staffing_dict, dept_suffix_map, site_key):
    employees = []

    for site_id, roles in staffing_dict.items():
        for role_name, count in roles.items():
            department_id = f'{site_id}-{dept_suffix_map[role_name]}'

            for _ in range(count):
                if site_key == 'factory_id':
                    employees.append(
                        _build_employee_record(department_id, factory_id=site_id)
                    )
                else:
                    employees.append(
                        _build_employee_record(department_id, warehouse_id=site_id)
                    )

    return employees


def seed_employees():

    factory_employees = _generate_employees_from_staffing(
        FACTORY_STAFFING, FACTORY_DEPT_SUFFIX, site_key='factory_id'
    )
    warehouse_employees = _generate_employees_from_staffing(
        WAREHOUSE_STAFFING, WAREHOUSE_DEPT_SUFFIX, site_key='warehouse_id'
    )

    all_employees = factory_employees + warehouse_employees
    random.shuffle(all_employees)

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = """
    INSERT INTO employees
    (
        first_name,
        last_name,
        email,
        phone,
        department_id,
        factory_id,
        warehouse_id,
        hire_date
    )
    VALUES
    (
        %s,
        %s,
        %s,
        %s,
        %s,
        %s,
        %s,
        %s
    )
    ON CONFLICT (email)
    DO NOTHING;
    """

    cursor.executemany(insert_query, all_employees)

    connection.commit()
    cursor.close()
    connection.close()

    print(f"{len(all_employees)} employees inserted successfully.")