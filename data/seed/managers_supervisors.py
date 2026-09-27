from database.db_connection import get_connection
from data.seed.employees import FACTORY_DEPT_SUFFIX, WAREHOUSE_DEPT_SUFFIX
from data.seed.factories import FACTORY_IDS
from data.seed.warehouses import WAREHOUSES_IDS
import random


def get_employees_by_department(connection):
    cursor = connection.cursor()
    cursor.execute('SELECT employee_id, department_id FROM employees;')
    rows = cursor.fetchall()
    cursor.close()

    dept_employees = {}
    for employee_id, department_id in rows:
        dept_employees.setdefault(department_id, []).append(employee_id)
    return dept_employees


def seed_managers_supervisors():
    connection = get_connection()
    cursor = connection.cursor()


    dept_employees = get_employees_by_department(connection)

    for department_id, employee_ids in dept_employees.items():
        supervisor_id = random.choice(employee_ids)
        cursor.execute(
            'UPDATE departments SET supervisor_employee_id = %s WHERE department_id = %s;',
            (supervisor_id, department_id)
        )

    for factory_id in FACTORY_IDS:
        dept_id = f'{factory_id}-{FACTORY_DEPT_SUFFIX["Plant Administration"]}'
        manager_id = random.choice(dept_employees[dept_id])
        cursor.execute(
            'UPDATE factories SET manager_employee_id = %s WHERE factory_id = %s;',
            (manager_id, factory_id)
        )

    for warehouse_id in WAREHOUSES_IDS:
        dept_id = f'{warehouse_id}-{WAREHOUSE_DEPT_SUFFIX["Warehouse Administration"]}'
        manager_id = random.choice(dept_employees[dept_id])
        cursor.execute(
            'UPDATE warehouses SET manager_employee_id = %s WHERE warehouse_id = %s;',
            (manager_id, warehouse_id)
        )

    connection.commit()
    print("Managers and supervisors seeded successfully.")

    cursor.close()
    connection.close()