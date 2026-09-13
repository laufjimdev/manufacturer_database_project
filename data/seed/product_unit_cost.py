from database.db_connection import get_connection

def get_average_material_cost_per_product(connection):
    """
    Estimates each product's material cost as: for every material in its
    BOM, the average unit_cost across that material's preferred and backup
    suppliers (averaged across factories), multiplied by quantity_required.

    This is a standard-cost-style estimate, not an actual cost — it doesn't
    reflect which supplier a given work order's materials actually came
    from. 
    Returns: {product_id: estimated_unit_cost}
    """
    cursor = connection.cursor()

    cursor.execute('''
        SELECT
            pb.product_id,
            SUM(pb.quantity_required * avg_costs.avg_unit_cost) AS estimated_unit_cost
        FROM product_bom pb
        JOIN (
            SELECT material_id, AVG(unit_cost) AS avg_unit_cost
            FROM raw_material_suppliers
            GROUP BY material_id
        ) avg_costs ON avg_costs.material_id = pb.material_id
        GROUP BY pb.product_id
        ORDER BY pb.product_id;
    ''')
    rows = cursor.fetchall()
    cursor.close()

    return {product_id: float(estimated_unit_cost) for product_id, estimated_unit_cost in rows}

def seed_product_unit_cost():
    connection = get_connection()
    cursor = connection.cursor()

    update_query = 'UPDATE products SET standard_unit_cost = %s WHERE product_id = %s'

    products_standard_unit_cost = get_average_material_cost_per_product(connection)

    try:
        for product_id, standard_unit_cost in products_standard_unit_cost.items():
            cursor.execute(update_query, (standard_unit_cost, product_id))
        connection.commit()
    except Exception as e:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()

if __name__ == "__main__":
    seed_product_unit_cost()

    