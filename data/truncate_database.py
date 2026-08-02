from pathlib import Path
from database.db_connection import get_connection


def truncate_database():
    """
    Truncates all tables and resets identity columns,
    using the SQL script in database/reset_database.sql.
    """
    
    CURRENT_DIR = Path(__file__).resolve().parent

    SQL_PATH = CURRENT_DIR.parent / 'database' / 'reset_database.sql'

    with open(SQL_PATH) as f:
        sql = f.read()

    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(sql)
        conn.commit()
        print("Database truncated successfully.")
    except Exception as e:
        conn.rollback()
        print(f"Error truncating database: {e}")
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    truncate_database()