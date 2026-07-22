from database.db_connection import get_connection
from data.raw_materials_config import MATERIALS
import random


def seed_raw_materials():

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = """
    INSERT INTO raw_materials
    (
        material_name,
        material_type,
        unit_of_measure,
        dimensions
    )
    VALUES
    (
        %s,
        %s,
        %s,
        %s,
    );
    """

    for material in MATERIALS:
        cursor.execute(insert_query, (
            material["material_name"],
            material["material_type"],
            material["unit_of_measure"],
            material["dimensions"],
        ))

    connection.commit()
    cursor.close()
    connection.close()

    print(f"{len(MATERIALS)} materials inserted successfully.")