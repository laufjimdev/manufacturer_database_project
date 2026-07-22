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


def generate_supplier():

    company = fake.company()

    contact_info = create_contact_info(company)

    city, state, prefix = random.choice(LOCATIONS)

    lead_time = random.choice(
        list(LEAD_TIME_RATING.keys())
    )

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
        "rating": random.choice(
            LEAD_TIME_RATING[lead_time]
        )
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

    suppliers = []

    for _ in range(100):
        suppliers.append(generate_supplier())

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

    cursor.close()

    connection.close()
       

    print(f"{len(suppliers)} Suppliers inserted successfully.")
        

