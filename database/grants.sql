-- ===========================================
-- grants.sql
-- Manufacturing Operations Database
-- Every privilege on schema objects, in one place.
--
-- Run AFTER roles.sql and schema.sql, connected to the manufacturing
-- database as the owner (lauradev). Database-level CONNECT is granted
-- in setup_database.sql, since it needs the database name.
-- Safe to re-run: GRANT is idempotent.
--
-- Contents:
--   1. Schema access
--   2. Default privileges (future tables created by lauradev)
--   3. dba and read_only_auditor (blanket)
--   4. Column-level privileges (sensitive columns, restricted updates)
--   5. Table-level privileges per group
--
-- Columns deliberately hidden:
--   customers -> email, phone, billing_address_st (sales / warehouse)
--   products  -> standard_unit_cost, selling_price (warehouse_staff)
-- ===========================================


------------------------------------------------------------
-- 1. SCHEMA ACCESS
------------------------------------------------------------

GRANT USAGE ON SCHEMA public
    TO dba, production_manager, maintenance_manager,
       read_only_auditor, sales_analyst, warehouse_staff;

GRANT CREATE ON SCHEMA public TO dba;


------------------------------------------------------------
-- 2. DEFAULT PRIVILEGES
-- Apply to objects lauradev creates AFTER this runs. Only blanket
-- rules belong here; role-specific grants are explicit below, so a
-- new table is invisible to those groups until granted on purpose.
------------------------------------------------------------

ALTER DEFAULT PRIVILEGES FOR ROLE lauradev IN SCHEMA public
    GRANT ALL ON TABLES TO dba;
ALTER DEFAULT PRIVILEGES FOR ROLE lauradev IN SCHEMA public
    GRANT ALL ON SEQUENCES TO dba;
ALTER DEFAULT PRIVILEGES FOR ROLE lauradev IN SCHEMA public
    GRANT SELECT ON TABLES TO read_only_auditor;


------------------------------------------------------------
-- 3. DBA / READ-ONLY AUDITOR
-- Cover tables that already exist (default privileges only affect
-- objects created later).
------------------------------------------------------------

GRANT ALL ON ALL TABLES    IN SCHEMA public TO dba;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO dba;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_only_auditor;


------------------------------------------------------------
-- 4. COLUMN-LEVEL PRIVILEGES
------------------------------------------------------------

-- customers: no email, phone or street address for anyone below dba/auditor.
GRANT SELECT (customer_id, customer_name, city, state, zipcode)
    ON public.customers TO sales_analyst;
GRANT SELECT (customer_id, customer_name)
    ON public.customers TO warehouse_staff;

-- products: warehouse_staff sees no cost or price.
GRANT SELECT (product_id, product_name, description, category_id,
              dimensions, weight_lb, load_capacity, active_flag)
    ON public.products TO warehouse_staff;

-- machines: maintenance can change machine status only.
GRANT UPDATE (status)
    ON public.machines TO maintenance_manager;

-- work_orders: production can reschedule and change status only.
GRANT UPDATE (start_date, due_date, status, priority, completed_at)
    ON public.work_orders TO production_manager;

-- Warehouse fulfilment fields only.
GRANT UPDATE (received_date, status)
    ON public.product_transfers TO warehouse_staff;

GRANT UPDATE (ship_date, delivery_date, carrier, tracking_number, status)
    ON public.shipments TO warehouse_staff;

GRANT UPDATE (condition, status, resolution, restocked,
              handled_by_employee_id, notes)
    ON public.returns TO warehouse_staff;


------------------------------------------------------------
-- 5. TABLE-LEVEL PRIVILEGES
------------------------------------------------------------

-- production_manager: read production, inventory, BOM and product data;
-- create work orders (updates limited to the columns above).
GRANT SELECT ON
    factories,
    production_lines,
    production_line_categories,
    machines,
    products,
    product_categories,
    product_bom,
    raw_materials,
    raw_materials_inventory,
    inventory_transactions,
    products_inventory,
    product_inventory_transactions,
    product_transfers,
    quality_inspections,
    work_orders
TO production_manager;

GRANT INSERT ON work_orders TO production_manager;

-- maintenance_manager: read factories/lines/machines; read/write
-- maintenance data (machine status update is column-level above).
GRANT SELECT ON
    factories,
    production_lines,
    machines
TO maintenance_manager;

GRANT SELECT, INSERT, UPDATE ON
    maintenance_plans,
    maintenance_logs,
    machine_downtime
TO maintenance_manager;

-- sales_analyst: read sales, shipments, returns, products and inventory.
-- Customer access is column-level above.
GRANT SELECT ON
    sales_orders,
    sales_order_items,
    shipments,
    returns,
    products,
    product_categories,
    products_inventory,
    warehouses
TO sales_analyst;

-- warehouse_staff: read orders, inventory, transfers and shipments;
-- insert shipments, returns and inventory transactions. Updates,
-- customers and products access are column-level above.
GRANT SELECT ON
    sales_orders,
    sales_order_items,
    products_inventory,
    product_inventory_transactions,
    product_transfers,
    shipments,
    returns,
    warehouses
TO warehouse_staff;

GRANT INSERT ON
    shipments,
    returns,
    product_inventory_transactions
TO warehouse_staff;
