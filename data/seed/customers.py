from database.db_connection import get_connection
from faker import Faker
from data.seed.suppliers import create_contact_info

fake = Faker("en_US")



def generate_event_company():
    event_keywords = [
        "Events",
        "Event Co.",
        "Productions",
        "Celebrations",
        "Experiences",
        "Occasions",
        "Gatherings",
    ]

    name_formats = [
        lambda: fake.last_name(),
        lambda: f"{fake.last_name()} {fake.last_name()}",
        lambda: f"{fake.last_name()} Brothers",
        lambda: f"{fake.last_name()} & {fake.last_name()}",
    ]

    base = fake.random_element(name_formats)()
    keyword = fake.random_element(event_keywords)

    return f"{base} {keyword}"


def generate_customer():
    customer_name = generate_event_company()
    first_name, last_name, email = create_contact_info(customer_name)
    contact_name = f"{first_name} {last_name}"
    phone = fake.numerify('###-###-####')
    city = fake.city()
    state = fake.state_abbr(include_territories=False)
    zipcode = fake.zipcode_in_state(state)
    billing_address_st = fake.street_address()

    return (customer_name, contact_name, email, phone, billing_address_st, city, state, zipcode)


def seed_customers():

    total_customers = 190

    connection = get_connection()
    cursor = connection.cursor()

    insert_query = '''
        INSERT INTO customers
        (
            customer_name,
            contact_name,
            email,
            phone,
            billing_address_st,
            city,
            state,
            zipcode
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
            %s
        );
'''

    for _ in range(total_customers):
        customer_name, contact_name, email, phone, billing_address_st, city, state, zipcode = generate_customer()
        cursor.execute(insert_query, (
            customer_name,
            contact_name,
            email,
            phone,
            billing_address_st,
            city,
            state,
            zipcode
        ))

    connection.commit()

    cursor.execute('SELECT COUNT(*) FROM customers;')
    rows = cursor.fetchone()[0]

    print(f"{rows} customers successfully inserted")


if __name__ == "__main__":
    seed_customers()