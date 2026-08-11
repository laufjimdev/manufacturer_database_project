import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from airflow.sdk import dag, task, Param
from datetime import date

from database.db_connection import get_connection

from data.simulation.purchase_orders_n_items import generate_purchase_order_data, simulate_purchase_orders, simulate_purchase_order_items



@dag(
    dag_id="simulate_manufacturing_cycle",
    schedule=None,
    params={
        # Purchase order simulation params
        "factory_base_quantities": Param(
            {"F1": 1000, "F2": 800, "F3": 500}, type="object"
        ),
        "purchase_start_date": Param("2026-01-01", type="string", format="date"),
        "purchase_end_date": Param("2026-01-23", type="string", format="date"),
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

    


    po_task = run_purchase_order_simulation()

    po_task


simulate_manufacturing_cycle()