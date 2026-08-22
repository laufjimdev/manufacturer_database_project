import math
from datetime import timedelta, date
from database.db_connection import get_connection
from data.seed.data_configs.product_bom_config import PRODUCT_RATIOS


def get_wo_quantity(production_line_id, quantity):
    if production_line_id not in (1,2):
        return quantity
    elif production_line_id == 1:
        return quantity * 0.52
    elif production_line_id == 2:
        return quantity * 0.48
    

def simulate_work_orders(factory_base_quantities_wo, start_date_wo):

    connection = get_connection()
    cursor = connection.cursor()

    try:
        #Getting production lines per products
        cursor.execute('''
                        SELECT pl.factory_id, p.product_id, plc.production_line_id
                        FROM production_line_categories plc
                        JOIN products p ON plc.category_id = p.category_id
                        JOIN production_lines pl ON plc.production_line_id = pl.production_line_id
                        ORDER BY pl.factory_id, p.product_id, plc.production_line_id;
    ''')
        products_n_lines = cursor.fetchall()
        products_n_lines_dict = {}

        for factory_id, product_id, production_line_id in products_n_lines:
            products_n_lines_dict.setdefault((factory_id, product_id), []).append(production_line_id)

        #Getting lines capacity per day
        cursor.execute('SELECT production_line_id, capacity_per_day FROM production_lines;')
        lines_capacity = cursor.fetchall()
        lines_capacity_dict = {}

        for production_line_id, capacity_per_day in lines_capacity:
            lines_capacity_dict[production_line_id] = capacity_per_day


        insert_query = '''
            INSERT INTO work_orders
            (
                factory_id,
                production_line_id,
                product_id,
                quantity,
                start_date,
                due_date,
                status,
                priority
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                'completed',
                'normal'
            );
    '''

        wo_counter = 0

        for factory_id, quantity in factory_base_quantities_wo.items():
            for product_id, ratio in PRODUCT_RATIOS.items():

                production_line_ids = products_n_lines_dict[(factory_id, product_id)]

                for production_line_id in production_line_ids:
                    line_capacity = lines_capacity_dict[production_line_id]
                    wo_quantity = get_wo_quantity(production_line_id, quantity) * ratio
                    due_date = start_date_wo + timedelta(days=math.ceil(wo_quantity / line_capacity))

                    cursor.execute(insert_query, (
                        factory_id,
                        production_line_id,
                        product_id,
                        wo_quantity,
                        start_date_wo,
                        due_date,
                    ))
                    wo_counter += 1
                
        connection.commit()
        print(f"{wo_counter} work orders successfully inseted.")

        #Register inventory transaction
        '''
        wo_fetch = 'SELECT work_order_id, factory_id, product_id, quantity FROM work_orders WHERE start_date = {start_date_wo}'

        inv_transaction_insertQ = 
            INSERT INTO inventory_transactions
            (
                material_id,
                factory_id,
                quantity,
                transaction_type,
                work_order_id,
                transaction_date
            )
            VALUES 
'''
        
    except Exception as e:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()

    

if __name__ == "__main__":
    factory_base_quantities_wo = {"F1": 800, "F2": 600, "F3": 300} 
    start_date = date(2026, 2, 1)
    simulate_work_orders(factory_base_quantities_wo, start_date)

    