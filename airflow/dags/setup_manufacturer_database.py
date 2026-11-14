import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))

from airflow import DAG
from airflow.models.param import Param
from airflow.providers.standard.operators.bash import BashOperator
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv(PROJECT_ROOT / ".env")

SETUP_SQL = PROJECT_ROOT / "database" / "setup_database.sql"

default_args = {
    'owner': 'Laura Jimenez',
    'start_date': datetime(2026, 1, 1),
    'retries': 0,  # a partial run leaves a half-built database, so don't auto-retry
}

dag = DAG(
    'setup_manufacturer_database_dag',
    default_args=default_args,
    description='Creates roles, the database, schema and grants by running setup_database.sql with psql.',
    schedule=None,
    catchup=False,
    params={
        "db_name": Param(
            os.getenv("DB_NAME", "manufacturer_db"),
            type="string",
            description="Name of the database to create.",
        ),
    },
)

run_setup_sql = BashOperator(
    task_id='run_setup_database_sql',
    bash_command='psql -v ON_ERROR_STOP=1 -v db_name="$TARGET_DB" -f "$SETUP_SQL"',
    env={
        "PGHOST": os.getenv("DB_HOST", "localhost"),
        "PGPORT": os.getenv("DB_PORT", "5432"),
        "PGUSER": os.getenv("DB_USER", ""),
        "PGPASSWORD": os.getenv("DB_PASSWORD", ""),
        "PGDATABASE": "postgres",
        "TARGET_DB": "{{ params.db_name }}",
        "SETUP_SQL": str(SETUP_SQL),
    },
    append_env=True,
)