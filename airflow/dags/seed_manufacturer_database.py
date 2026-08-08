import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from datetime import datetime, timedelta

from data.truncate_database import truncate_database
from data.seed.seed_factories import seed_factories
from data.seed.seed_warehouses import seed_warehouses
from data.seed.seed_suppliers import seed_suppliers
from data.seed.seed_departments import seed_departments
from data.seed.seed_employees import seed_employees
from data.seed.seed_raw_materials import seed_raw_materials
from data.seed.seed_raw_material_suppliers import seed_raw_material_suppliers
from data.seed.seed_product_categories import seed_product_categories
from data.seed.seed_production_lines import seed_production_lines
from data.seed.seed_products import seed_products
from data.seed.seed_machines import seed_machines
from data.seed.seed_product_bom import seed_product_bom
from data.seed_purchase_orders_n_items import seed_purchase_orders_n_items
from data.seed_raw_materials_inventory import seed_raw_materials_inventory



default_args = {
    'owner': 'Laura Jimenez',
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}


dag = DAG(
    'seed_manufacturer_dag',
    default_args=default_args,
    description='',
    schedule=None,
    catchup=False,
)
#Tasks

truncate_database_task = PythonOperator(
    task_id='truncate_database',
    python_callable=truncate_database,
    dag=dag,
)

seed_factories_task = PythonOperator(
    task_id='seed_factories',
    python_callable=seed_factories,
    dag=dag,
)

seed_warehouses_task = PythonOperator(
    task_id='seed_warehouses',
    python_callable=seed_warehouses,
    dag=dag,
)

seed_suppliers_task = PythonOperator(
    task_id='seed_suppliers',
    python_callable=seed_suppliers,
    dag=dag,
)

seed_departments_task = PythonOperator(
    task_id='seed_departments',
    python_callable=seed_departments,
    dag=dag,
)

seed_employees_task = PythonOperator(
    task_id='seed_employees',
    python_callable=seed_employees,
    dag=dag,
)

seed_raw_materials_task = PythonOperator(
    task_id='seed_raw_materials',
    python_callable=seed_raw_materials,
    dag=dag,
)
seed_raw_material_suppliers_task = PythonOperator(
    task_id='seed_raw_material_suppliers',
    python_callable=seed_raw_material_suppliers,
    dag=dag,
)
seed_product_categories_task = PythonOperator(
    task_id='seed_product_categories',
    python_callable=seed_product_categories,
    dag=dag,
)
seed_production_lines_task = PythonOperator(
    task_id='seed_production_lines',
    python_callable=seed_production_lines,
    dag=dag,
)
seed_products_task = PythonOperator(
    task_id='seed_products',
    python_callable=seed_products,
    dag=dag,
)
seed_machines_task = PythonOperator(
    task_id='seed_machines',
    python_callable=seed_machines,
    dag=dag,
)
seed_product_bom_task = PythonOperator(
    task_id='seed_product_bom',
    python_callable=seed_product_bom,
    dag=dag,
)
seed_purchase_orders_n_items_task = PythonOperator(
    task_id='seed_purchase_orders_n_items',
    python_callable=seed_purchase_orders_n_items,
    dag=dag,
)
seed_raw_materials_inventory_task = PythonOperator(
    task_id='seed_raw_materials_inventory',
    python_callable=seed_raw_materials_inventory,
    dag=dag,
)
#Pipeline Definition

truncate_database_task >> [seed_suppliers_task, seed_product_categories_task]

seed_suppliers_task >> [
    seed_factories_task,
    seed_warehouses_task,
    seed_raw_materials_task
]

[seed_factories_task, seed_warehouses_task] >> seed_departments_task >> seed_employees_task

[seed_raw_materials_task, seed_factories_task]  >> seed_raw_material_suppliers_task >> seed_purchase_orders_n_items_task >> seed_raw_materials_inventory_task

seed_factories_task >> seed_production_lines_task >> [seed_products_task, seed_machines_task]

[seed_products_task, seed_raw_materials_task] >> seed_product_bom_task