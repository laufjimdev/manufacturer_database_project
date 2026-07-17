from database.db_connection import get_connection

warehouses = [

    ("W1",
     "National Central Hub",
     "Chicago",
     "Illinois",
     120000),

    ("W2",
     "South Central Distribution",
     "Columbus",
     "Ohio",
     95000),

    ("W3",
     "Midwest / Northeast buffer",
     "Buckeye",
     "Arizona",
     80000),

    ("W4",
     "Inland Empire",
     "Riverside",
     "California",
     60000)

]

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

for warehouse in warehouses:

    cursor.execute(insert_query, warehouse)

connection.commit()

cursor.close()

connection.close()

print("Warehouses inserted successfully.")