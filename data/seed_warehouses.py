from database.db_connection import get_connection

WAREHOUSES = [

    {
        "warehouse_id": "W1",
        "warehouse_name": "National Central Hub",
        "city": "Columbus",
        "state": "Ohio",
        "storage_capacity_units": 120000
    },

    {
        "warehouse_id": "W2",
        "warehouse_name": "South Central Distribution",
        "city": "Dallas",
        "state": "Texas",
        "storage_capacity_units": 95000
    },

    {
        "warehouse_id": "W3",
        "warehouse_name": "Northeast Distribution",
        "city": "Chicago",
        "state": "Illinois",
        "storage_capacity_units": 70000
    },

    {
        "warehouse_id": "W4",
        "warehouse_name": "Inland Empire",
        "city": "Riverside",
        "state": "California",
        "storage_capacity_units": 60000
    }
]

WAREHOUSES_IDS = [warehouse["warehouse_id"] for warehouse in WAREHOUSES]

def seed_warehouses():
    
    connection = get_connection()
    cursor = connection.cursor()
    
    insert_query = """

    INSERT INTO warehouses
    (
        warehouse_id,
        warehouse_name,
        city,
        state,
        storage_capacity_units,
        manager_employee_id
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

    ON CONFLICT (warehouse_id)
    DO NOTHING;

    """

    for warehouse in WAREHOUSES:

        cursor.execute(insert_query, (
            warehouse["warehouse_id"],
            warehouse["warehouse_name"],
            warehouse["city"],
            warehouse["state"],
            warehouse["storage_capacity_units"],
        ))

    connection.commit()
    cursor.close()
    connection.close()

    print("Warehouses inserted successfully.")