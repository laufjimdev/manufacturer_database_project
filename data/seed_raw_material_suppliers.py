from database.db_connection import get_connection
from data.raw_materials_config import MATERIALS
from data.seed_raw_materials import get_material_ids
from data.seed_suppliers import get_supplier_pool
from data.seed_factories import FACTORY_IDS
import random


BASE_COST_BY_NAME = {
    material["material_name"]: material["unit_cost"]
    for material in MATERIALS
}

RATING_MULTIPLIERS = [
    (9, 1.30),
    (8.5, 1.00),
    (7.5, 0.95),
    (6, 0.90),
]


def _get_multiplier(rating):
    for threshold, multiplier in RATING_MULTIPLIERS:
        if rating >= threshold:
            return multiplier
    return 0.90


def seed_raw_material_suppliers():

    materials = get_material_ids()
    suppliers = get_supplier_pool()

    high_rating_suppliers = [s for s in suppliers if s[1] >= 9]
    low_rating_suppliers = [s for s in suppliers if s[1] < 9]

    if not high_rating_suppliers:
        raise ValueError("No suppliers with rating >= 9 found. Run seed_suppliers first.")
    if not low_rating_suppliers:
        raise ValueError("No suppliers with rating < 9 found. Run seed_suppliers first.")

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = """
    INSERT INTO raw_material_suppliers
    (
        material_id,
        supplier_id,
        factory_id,
        unit_cost,
        lead_time_days,
        preferred_supplier
    )
    VALUES
    (
        %s,
        %s,
        %s,
        %s,
        %s,
        %s
    )
    ON CONFLICT (material_id, supplier_id)
    DO NOTHING;
    """

    rows = []

    for material_id, material_name in materials:
        base_cost = BASE_COST_BY_NAME[material_name]

        used_supplier_ids = set()

        available_high = high_rating_suppliers.copy()
        available_low = low_rating_suppliers.copy()
        random.shuffle(available_high)
        random.shuffle(available_low)

        for factory_id in FACTORY_IDS:

            # Preferred supplier — high rating
            preferred_supplier_id, preferred_rating, preferred_lead_time = available_high.pop()
            used_supplier_ids.add(preferred_supplier_id)
            preferred_price = round(base_cost * _get_multiplier(preferred_rating), 2)

            rows.append((
                material_id,
                preferred_supplier_id,
                factory_id,
                preferred_price,
                preferred_lead_time,
                True,
            ))

            # Backup supplier — lower rating
            backup_supplier_id, backup_rating, backup_lead_time = available_low.pop()
            used_supplier_ids.add(backup_supplier_id)
            backup_price = round(base_cost * _get_multiplier(backup_rating), 2)

            rows.append((
                material_id,
                backup_supplier_id,
                factory_id,
                backup_price,
                backup_lead_time,
                False,
            ))

    cursor.executemany(insert_query, rows)

    connection.commit()
    cursor.close()
    connection.close()

    print(f"{len(rows)} raw_material_suppliers rows inserted successfully.")