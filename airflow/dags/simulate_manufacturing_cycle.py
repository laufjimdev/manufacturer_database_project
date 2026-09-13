import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from airflow.sdk import dag, task, Param
from datetime import date

from database.db_connection import get_connection

from data.simulation.purchase_orders_n_items import generate_purchase_order_data, simulate_purchase_orders, simulate_purchase_order_items
from data.simulation.work_orders import simulate_work_orders
from data.simulation.raw_materials_inventory import simulate_raw_materials_inventory
from data.simulation.products_inventory import simulate_products_inventory
from data.simulation.sales_orders_n_items import simulate_sales_orders, simulate_sales_order_items, generate_sales_order_data

@dag(
    dag_id="simulate_manufacturing_cycle",
    schedule=None,
    params={
        # Purchase order simulation params
        "factory_base_quantities": Param(
            {"F1": 1500, "F2": 800, "F3": 500}, type="object"
        ),
        "purchase_start_date": Param("2026-01-01", type="string", format="date"),
        "purchase_end_date": Param("2026-01-23", type="string", format="date"),
        # Work order simulation params
        "factory_base_quantities_wo": Param({"F1": 1200, "F2": 580, "F3": 315}, type = "object"),
        "start_date_wo": Param("2026-02-01", type= "string", format= "date"),
        #Sale orders simulation parms
        "sales_orders_by_warehouse" : Param({"W1": 500, "W2": 250, "W3": 200, "W4": 180}, type = "object"),
        "customers_by_warehouse_count" : Param({"W1": 150, "W2": 90, "W3": 70, "W4": 60}, type = "object"),
        "sale_start_date": Param("2026-03-01", type="string", format="date"),
        "sale_end_date": Param("2026-03-30", type="string", format="date"),
    },
)
def simulate_manufacturing_cycle():

    @task
    def run_purchase_order_simulation(**context):
        params = context["params"]
        factory_quantities = params["factory_base_quantities"]
        start = date.fromisoformat(params["purchase_start_date"])
        end = date.fromisoformat(params["purchase_end_date"])

        connection = get_connection()
        
        try:
            purchase_orders_data = generate_purchase_order_data(factory_quantities, start, end)
            po_data = simulate_purchase_orders(purchase_orders_data, connection)
            simulate_purchase_order_items(po_data, connection)
    
            connection.commit()
            print("Purchase orders and items committed successfully.")
    
        except Exception as e:
            connection.rollback()
            print(f"Failed to seed purchase orders and items, rolled back: {e}")
            raise
    
        finally:
            connection.close()

    @task
    def run_work_order_simulation(**context):
        params = context["params"]
        factory_base_quantities_wo = params["factory_base_quantities_wo"]
        start_date_wo = date.fromisoformat(params["start_date_wo"])

        simulate_work_orders(factory_base_quantities_wo, start_date_wo)

    @task
    def run_raw_materials_inventory_simulation():
        simulate_raw_materials_inventory()

    @task
    def run_products_inventory_simulation():
        simulate_products_inventory()

    @task
    def run_sales_orders_simulation(**context):
        params = context["params"]
        sales_orders_by_warehouse = params["sales_orders_by_warehouse"]
        customers_by_warehouse_count = params["customers_by_warehouse_count"]
        sale_start_date = date.fromisoformat(params["sale_start_date"])
        sale_end_date = date.fromisoformat(params["sale_end_date"])

        connection = get_connection()

        try:
            data = generate_sales_order_data(
                sales_orders_by_warehouse,
                customers_by_warehouse_count,
                sale_start_date,
                sale_end_date,
                connection,
            )
            data = simulate_sales_orders(data, connection)
            simulate_sales_order_items(data, connection)
            connection.commit()
        except Exception as e:
            connection.rollback()
            raise Exception(f"Failed to generate sales orders, error: {e}")
        finally:
            connection.close()

    po_task = run_purchase_order_simulation()
    wo_task = run_work_order_simulation()
    rm_inv_task = run_raw_materials_inventory_simulation()
    pi_task = run_products_inventory_simulation()
    so_task = run_sales_orders_simulation()

    po_task >> wo_task
    [po_task, wo_task] >> rm_inv_task >> so_task >> pi_task

simulate_manufacturing_cycle()