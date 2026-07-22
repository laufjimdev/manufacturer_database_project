-- ===========================================
-- reset_database.sql
-- Clears all data while preserving the schema.
-- Resets identity columns back to 1.
-- ===========================================

BEGIN;

TRUNCATE TABLE

    -- Operational / transactional tables
    shipments,
    returns,
    sales_order_items,
    sales_orders,
    purchase_order_items,
    purchase_orders,
    work_orders,
    quality_inspections,
    products_inventory,
    raw_materials_inventory,
    maintenance_logs,
    maintenance_plans,
    machine_downtime,

    -- Manufacturing structure
    machines,
    products,
    product_bom,
    production_lines,

    -- Master data
    raw_materials,
	raw_material_suppliers,
    product_categories,
    suppliers,
    customers,

    -- Organization
    employees,
    departments,

    -- Core company structure
    factories,
    warehouses

RESTART IDENTITY;

COMMIT;