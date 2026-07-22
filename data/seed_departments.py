from database.db_connection import get_connection
from data.seed_factories import FACTORY_IDS
from data.seed_warehouses import WAREHOUSES_IDS

FACTORY_DEPARTMENTS = [
    'Production Assembly',
    'Welding & Fabrication',
    'Wood & Surface Finishing',
    'Quality Control',
    'Maintenance',
    'Procurement',
    'Plant Administration',
]

WAREHOUSE_DEPARTMENTS = [
    'Receiving',
    'Order Picking & Packing',
    'Shipping & Dispatch',
    'Inventory Control',
    'Material Handling (Forklift Operators)',
    'Warehouse Maintenance',
    'Logistics & Transportation Planning',
    'Warehouse Administration',
]


def _generate_department_rows(site_ids, department_names, location_type):
    """
    Builds department rows for either factories or warehouses.

    site_ids: list of factory or warehouse IDs (e.g. FACTORY_IDS)
    department_names: list of department names for that site type
    location_type: 'factory' or 'warehouse'
    """
    rows = []

    for site_id in site_ids:
        for index, department_name in enumerate(department_names, start=1):
            department_id = f'{site_id}-d{index}'

            factory_id = site_id if location_type == 'factory' else None
            warehouse_id = site_id if location_type == 'warehouse' else None

            rows.append((
                department_id,
                department_name,
                location_type,
                factory_id,
                warehouse_id,
            ))

    return rows


def seed_departments():

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = """
    INSERT INTO departments
    (
        department_id,
        department_name,
        location_type,
        factory_id,
        warehouse_id,
        supervisor_employee_id
    )
    VALUES
    (
        %s,
        %s,
        %s,
        %s,
        %s,
        NULL
    )
    ON CONFLICT (department_id)
    DO NOTHING;
    """

    factory_rows = _generate_department_rows(
        FACTORY_IDS, FACTORY_DEPARTMENTS, location_type='factory'
    )
    warehouse_rows = _generate_department_rows(
        WAREHOUSES_IDS, WAREHOUSE_DEPARTMENTS, location_type='warehouse'
    )

    all_rows = factory_rows + warehouse_rows

    cursor.executemany(insert_query, all_rows)

    connection.commit()
    cursor.close()
    connection.close()

    print(f"{len(all_rows)} departments inserted successfully.")

