from database.db_connection import get_connection
from faker import Faker
import random

fake = Faker("en_US")


LOCATIONS = [
    ("Phoenix", "AZ", "85"),
    ("Dallas", "TX", "75"),
    ("Atlanta", "GA", "30")
]


LEAD_TIME_RATING = {
    2: [9, 9.5, 10],
    3: [8.5, 9, 9.5],
    5: [7.5, 8, 8.5],
    7: [6, 7, 7.5]
}


def create_contact_info(company_name):
    domain = (
        company_name
        .lower()
        .replace(",", "")
        .replace(".", "")
        .replace(" ", "")
        .replace("&", "and")
    )

    first_name = fake.first_name().lower()
    last_name = fake.last_name().lower()
    contact_info = [first_name.capitalize(), last_name.capitalize(), f"{first_name}.{last_name}@{domain}.com"]
    return contact_info


def build_supplier_combos(total):
    """
    Build a list of (location, lead_time, rating) combos so that every
    location gets an equal number of suppliers, and within each location
    every rating gets an equal number of suppliers.

    Returns a shuffled list of length `total` (or the largest multiple
    of the combo count that is <= total, if total doesn't divide evenly).
    """
    # All (lead_time, rating) pairs, e.g. (2, 9), (2, 9.5), (2, 10), (3, 8.5)...
    lead_time_rating_pairs = [
        (lead_time, rating)
        for lead_time, ratings in LEAD_TIME_RATING.items()
        for rating in ratings
    ]

    # Cross with locations -> one combo per (location, lead_time, rating)
    base_combos = [
        (location, lead_time, rating)
        for location in LOCATIONS
        for lead_time, rating in lead_time_rating_pairs
    ]

    combo_count = len(base_combos)  # 3 locations * 12 (lead_time, rating) pairs = 36
    repeats = total // combo_count

    if repeats == 0:
        raise ValueError(
            f"total ({total}) must be >= number of combos ({combo_count}) "
            "to keep an equal split across locations and ratings."
        )

    combos = base_combos * repeats
    remainder = total - len(combos)

    if remainder:
        # Distribute leftover as evenly as possible, still balanced per
        # location (take equal slices across locations for the remainder).
        per_location_remainder = remainder // len(LOCATIONS)
        leftover_by_location = remainder - per_location_remainder * len(LOCATIONS)

        for i, location in enumerate(LOCATIONS):
            location_pairs = lead_time_rating_pairs.copy()
            random.shuffle(location_pairs)
            count = per_location_remainder + (1 if i < leftover_by_location else 0)
            for lead_time, rating in location_pairs[:count]:
                combos.append((location, lead_time, rating))

    random.shuffle(combos)
    return combos


def generate_supplier(location, lead_time, rating):

    company = fake.company()

    contact_info = create_contact_info(company)

    city, state, prefix = location

    supplier = {
        "name": company,
        "contact_name": f"{contact_info[0]} {contact_info[1]}",
        "phone": fake.numerify("###-###-####"),
        "email": contact_info[2],
        "street": fake.street_address(),
        "city": city,
        "state": state,
        "zipcode": fake.numerify(prefix + "###"),
        "lead_time_days": lead_time,
        "rating": rating
    }

    return supplier


def get_supplier_pool():
    """
    Fetches supplier_id, rating, and lead_time_days for all suppliers.
    Used by seed_raw_material_suppliers to select preferred (high-rating)
    and backup (lower-rating) suppliers per material.
    """
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute("SELECT supplier_id, rating, lead_time_days FROM suppliers;")
    suppliers = cursor.fetchall()

    cursor.close()
    connection.close()

    return suppliers


def seed_suppliers():

    Faker.seed(0)
    random.seed(0)

    total_suppliers = 108

    combos = build_supplier_combos(total_suppliers)

    suppliers = [
        generate_supplier(location, lead_time, rating)
        for location, lead_time, rating in combos
    ]

    connection = get_connection()

    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO suppliers 
        (
            supplier_name,
            contact_name,
            phone,
            email,
            street,
            city,
            state,
            zipcode,
            lead_time_days,
            rating
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
            %s,
            %s,
            %s
        );
'''

    for supplier in suppliers:
        cursor.execute(insert_query, 
            (
                supplier["name"],
                supplier["contact_name"],
                supplier["phone"],
                supplier["email"],
                supplier["street"],
                supplier["city"],
                supplier["state"],
                supplier["zipcode"],
                supplier["lead_time_days"],
                supplier["rating"]
            )
        )

    connection.commit()
    cursor.execute('SELECT COUNT(*) FROM suppliers;')
    rows = cursor.fetchone()[0]

    cursor.close()
    connection.close()

    print(f"{rows} Suppliers inserted successfully.")