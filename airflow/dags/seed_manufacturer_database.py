import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from datetime import datetime, timedelta

from data.seed_factories import seed_factories
from data.seed_warehouses import seed_warehouses
from data.seed_suppliers import seed_suppliers

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

seed_factories_task >> seed_warehouses_task >> seed_suppliers_task