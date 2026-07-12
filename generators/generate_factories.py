from db_connection import get_connection

def generateFactories():

    factories = [

        ("F1",
        "Dallas–Fort Worth Factory",
        "Dallas–Fort Worth",
        "Texas",
        1200),

        ("F2",
        "Atlanta Metro Factory",
        "Atlanta",
        "Georgia",
        1000),

        ("F3",
        "Phoenix–Buckeye Factory",
        "Buckeye",
        "Arizona",
        900)

    ]

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

    for factory in factories:

        cursor.execute(insert_query, factory)

    connection.commit()

    cursor.close()

    connection.close()

    print("Factories inserted successfully.")