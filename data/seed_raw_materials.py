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
        %s
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

def get_material_ids():
    """
    Fetches material_id + material_name pairs from the database.
    Used by seed_raw_material_suppliers to link materials to suppliers
    and to look up each material's base unit_cost from MATERIALS config.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute("SELECT material_id, material_name FROM raw_materials;")
    materials = cursor.fetchall()

    cursor.close()
    connection.close()

    return materials