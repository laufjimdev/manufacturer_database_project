-- ===========================================
-- verify_database.sql
-- Manufacturing Operations Database
-- Verifies that data generation completed successfully.
-- ===========================================

------------------------------------------------------------
-- 1. ROW COUNTS
------------------------------------------------------------

SELECT 'factories' AS table_name, COUNT(*) AS total_rows FROM factories
UNION ALL
SELECT 'warehouses', COUNT(*) FROM warehouses
UNION ALL
SELECT 'departments', COUNT(*) FROM departments
UNION ALL
SELECT 'employees', COUNT(*) FROM employees
UNION ALL
SELECT 'suppliers', COUNT(*) FROM suppliers
UNION ALL
SELECT 'materials', COUNT(*) FROM materials
UNION ALL
SELECT 'materials_inventory', COUNT(*) FROM materials_inventory
UNION ALL
SELECT 'product_categories', COUNT(*) FROM product_categories
UNION ALL
SELECT 'production_lines', COUNT(*) FROM production_lines
UNION ALL
SELECT 'machines', COUNT(*) FROM machines
UNION ALL
SELECT 'maintenance_plans', COUNT(*) FROM maintenance_plans
UNION ALL
SELECT 'maintenance_logs', COUNT(*) FROM maintenance_logs
UNION ALL
SELECT 'machine_downtime', COUNT(*) FROM machine_downtime
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'purchase_orders', COUNT(*) FROM purchase_orders
UNION ALL
SELECT 'purchase_order_items', COUNT(*) FROM purchase_order_items
UNION ALL
SELECT 'work_orders', COUNT(*) FROM work_orders
UNION ALL
SELECT 'quality_inspections', COUNT(*) FROM quality_inspections
UNION ALL
SELECT 'sales_orders', COUNT(*) FROM sales_orders
UNION ALL
SELECT 'sales_order_items', COUNT(*) FROM sales_order_items
UNION ALL
SELECT 'shipments', COUNT(*) FROM shipments
UNION ALL
SELECT 'returns', COUNT(*) FROM returns
ORDER BY table_name;

------------------------------------------------------------
-- 2. EMPLOYEES PER FACTORY
------------------------------------------------------------

SELECT
    f.factory_name,
    COUNT(e.employee_id) AS employee_count
FROM factories f
LEFT JOIN employees e
ON f.factory_id = e.factory_id
GROUP BY f.factory_name
ORDER BY f.factory_name;

------------------------------------------------------------
-- 3. EMPLOYEES PER DEPARTMENT
------------------------------------------------------------

SELECT
    d.department_name,
    COUNT(e.employee_id) AS employees
FROM departments d
LEFT JOIN employees e
ON d.department_id = e.department_id
GROUP BY d.department_name
ORDER BY d.department_name;

------------------------------------------------------------
-- 4. PRODUCTS PER PRODUCTION LINE
------------------------------------------------------------

SELECT
    pl.line_name,
    COUNT(p.product_id) AS products
FROM production_lines pl
LEFT JOIN products p
ON pl.production_line_id = p.production_line_id
GROUP BY pl.line_name
ORDER BY pl.line_name;

------------------------------------------------------------
-- 5. INVENTORY BY WAREHOUSE
------------------------------------------------------------

SELECT
    w.warehouse_name,
    COUNT(i.product_id) AS product_types,
    SUM(i.quantity_on_hand) AS total_units
FROM warehouses w
LEFT JOIN inventory i
ON w.warehouse_id = i.warehouse_id
GROUP BY w.warehouse_name
ORDER BY w.warehouse_name;

------------------------------------------------------------
-- 6. MATERIAL INVENTORY BY FACTORY
------------------------------------------------------------

SELECT
    f.factory_name,
    COUNT(mi.material_id) AS materials,
    SUM(mi.quantity_on_hand) AS total_quantity
FROM factories f
LEFT JOIN materials_inventory mi
ON f.factory_id = mi.factory_id
GROUP BY f.factory_name
ORDER BY f.factory_name;

------------------------------------------------------------
-- 7. CHECK FOR NULL FOREIGN KEYS
------------------------------------------------------------

SELECT
    COUNT(*) AS employees_without_department
FROM employees
WHERE department_id IS NULL;

SELECT
    COUNT(*) AS employees_without_factory_or_warehouse
FROM employees
WHERE factory_id IS NULL
  AND warehouse_id IS NULL;

SELECT
    COUNT(*) AS products_without_line
FROM products
WHERE production_line_id IS NULL;

SELECT
    COUNT(*) AS inventory_without_product
FROM inventory
WHERE product_id IS NULL;

------------------------------------------------------------
-- 8. CAPACITY SUMMARY
------------------------------------------------------------

SELECT
    factory_name,
    capacity_units_per_day
FROM factories
ORDER BY factory_name;

SELECT
    warehouse_name,
    storage_capacity_units
FROM warehouses
ORDER BY warehouse_name;

------------------------------------------------------------
-- 9. IDENTITY SEQUENCES
------------------------------------------------------------

SELECT
    MAX(employee_id) AS highest_employee_id
FROM employees;

SELECT
    MAX(product_id) AS highest_product_id
FROM products;

SELECT
    MAX(customer_id) AS highest_customer_id
FROM customers;

------------------------------------------------------------
-- END OF VERIFICATION
------------------------------------------------------------