from datetime import timedelta
from faker import Faker
import random

fake = Faker()

CARRIERS = [('USPS', 94), ('FEDEX', 98)]

def get_carrier():
    carrier, prefix = random.choice(CARRIERS)
    if carrier == 'USPS':
        tracking_number = fake.numerify(f'{prefix}####################')
        return((carrier, tracking_number))
    elif carrier == 'FEDEX':
        tracking_number = fake.numerify(f'{prefix}##########')
        return((carrier, tracking_number))

def create_shipment(connection, sales_order_id, warehouse_id, order_date):
    '''
        Inserts a row in the shipments table for a sale order. 
        Shipping happens 1-3 business days from the day of the order.
        Delivery happens within 1-4 calendar days.
        Carriers used for shipments are: USPS and Fedex. 
        All shipments will show delivered for now.
    '''

    insert_query = '''
        INSERT INTO shipments
        (
            sales_order_id,
            warehouse_id,
            ship_date,
            delivery_date,
            carrier,
            tracking_number,
            status
        )
        VALUES
        (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            'delivered'
        );
    '''

    ship_date = order_date + timedelta(days=random.randint(1,3))
    delivery_date = ship_date + timedelta(days=random.randint(1,4))
    carrier, tracking_number = get_carrier()

    cursor = connection.cursor()

    cursor.execute(insert_query, (
        sales_order_id,
        warehouse_id,
        ship_date,
        delivery_date,
        carrier,
        tracking_number
    ))

    cursor.close()
