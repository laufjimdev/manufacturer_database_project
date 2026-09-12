import math
from datetime import timedelta, date
from database.db_connection import get_connection
from data.seed.data_configs.product_bom_config import PRODUCT_RATIOS
from data.simulation.raw_materials_inventory import record_consumption_transaction
from data.simulation.product_transfers import create_product_transfer
from data.simulation.quality_inspections import get_qc_inspector_lookup, simulate_quality_inspections
from data.simulation.rework_orders import simulate_rework_orders

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

        #Getting product BOM (materials required per product)
        cursor.execute('SELECT * FROM product_bom;')
        rows = cursor.fetchall()
        product_bom_dict = {}
        for product_id, material_id, quantity_required in rows:
            product_bom_dict.setdefault(product_id, {})[material_id] = quantity_required


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
                priority,
                completed_at,
                reworked
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
                'normal',
                %s,
                FALSE
            )
            RETURNING work_order_id;
    '''


        wo_counter = 0
        inv_trns_counter = 0
        inspector_lookup = get_qc_inspector_lookup(connection)


        for factory_id, quantity in factory_base_quantities_wo.items():
            for product_id, ratio in PRODUCT_RATIOS.items():

                production_line_ids = products_n_lines_dict[(factory_id, product_id)]
                product_rework_lots = []

                for production_line_id in production_line_ids:
                    line_capacity = lines_capacity_dict[production_line_id]
                    wo_quantity = round(get_wo_quantity(production_line_id, quantity) * ratio)
                    due_date = start_date_wo + timedelta(days=math.ceil(wo_quantity / line_capacity))

                    cursor.execute(insert_query, (
                        factory_id,
                        production_line_id,
                        product_id,
                        wo_quantity,
                        start_date_wo,
                        due_date,
                        due_date
                    ))
                    work_order_id = cursor.fetchone()[0]
                    wo_counter += 1

                    #Register consumption transactions for this work order
                    materials = product_bom_dict[product_id]
                    for material_id, quantity_required in materials.items():
                        m_quantity_total = wo_quantity * quantity_required
                        record_consumption_transaction(
                            connection,
                            material_id,
                            factory_id,
                            m_quantity_total,
                            work_order_id=work_order_id
                        )
                        inv_trns_counter += 1

                    net_qty, rework_lots = simulate_quality_inspections(
                        connection, work_order_id, factory_id, production_line_id,
                        product_id, wo_quantity, due_date, inspector_lookup
                    )
                    product_rework_lots.extend(rework_lots)

                     #Simulate product transfer
                    shipped_date = due_date + timedelta(days=2)
                    received_date = shipped_date + timedelta(days=2)
                    if net_qty > 0:
                        create_product_transfer(connection, work_order_id, factory_id, product_id,
                            net_qty, shipped_date, received_date)
                    else:
                        print(f"Work order {work_order_id}: entire lot scrapped, no transfer created.")

            
                if product_rework_lots:
                    rework_wo_counter, _ = simulate_rework_orders(
                        connection, product_rework_lots, lines_capacity_dict, inspector_lookup
                    )
                    wo_counter += rework_wo_counter

        connection.commit()
        print(f"{wo_counter} work orders successfully inseted.")
        print(f"{inv_trns_counter} inventory transactions successfully inserted.")
        
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