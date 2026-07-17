from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from datetime import datetime, timedelta
import time

default_args = {
    'owner': 'laura',
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def sleep_1():
    print('Task1')
    time.sleep(1)

def sleep_2():
    print('Task2')
    time.sleep(2)

def sleep_3():
    print('Task3')
    time.sleep(3)

dag = DAG(
    'sleep_dag',
    default_args=default_args,
    description='',
    schedule=timedelta(days=1),
)

task1 = PythonOperator(
    task_id='sleep_1_second',
    python_callable=sleep_1,
    dag=dag,
)

task2 = PythonOperator(
    task_id='sleep_2_seconds',
    python_callable=sleep_2,
    dag=dag,
)

task3 = PythonOperator(
    task_id='sleep_3_seconds',
    python_callable=sleep_3,
    dag=dag,
)

task1 >> task2 >> task3