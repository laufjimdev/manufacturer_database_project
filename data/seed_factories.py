from database.db_connection import get_connection


FACTORIES = [
    {
        "factory_id": "F1",
        "factory_name": "Dallas–Fort Worth Factory",
        "city": "Dallas–Fort Worth",
        "state": "Texas",
        "capacity_units_per_day": 1080,
    },
    {
        "factory_id": "F2",
        "factory_name": "Atlanta Metro Factory",
        "city": "Atlanta",
        "state": "Georgia",
        "capacity_units_per_day": 660,
    },
    {
        "factory_id": "F3",
        "factory_name": "Phoenix–Buckeye Factory",
        "city": "Buckeye",
        "state": "Arizona",
        "capacity_units_per_day": 630,
    },
]


FACTORY_IDS = [factory["factory_id"] for factory in FACTORIES]

def seed_factories():

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = """
    INSERT INTO factories
    (
        factory_id,
        factory_name,
        city,
        state,
        capacity_units_per_day,
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
    ON CONFLICT (factory_id)
    DO NOTHING;
    """

    for factory in FACTORIES:
        cursor.execute(insert_query, (
            factory["factory_id"],
            factory["factory_name"],
            factory["city"],
            factory["state"],
            factory["capacity_units_per_day"],
        ))

    connection.commit()
    cursor.close()
    connection.close()

    print("Factories inserted successfully.")

