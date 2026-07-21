--
-- PostgreSQL database dump
--

\restrict Mbo8ivCXIVULvlAYhrVMoVqwogVm0O9RXyHg0n2nOfGEHrj7ViCWPpzUOyghp3N

-- Dumped from database version 18.4 (Homebrew)
-- Dumped by pg_dump version 18.4

-- Started on 2026-07-21 14:02:30 MST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 4280 (class 0 OID 0)
-- Dependencies: 4
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 1027 (class 1247 OID 18114)
-- Name: received_item; Type: TYPE; Schema: public; Owner: lauradev
--

CREATE TYPE public.received_item AS (
	material_id integer,
	quantity_received numeric(12,2)
);


ALTER TYPE public.received_item OWNER TO lauradev;

--
-- TOC entry 281 (class 1255 OID 18107)
-- Name: place_sales_order(integer, date, character, jsonb, text); Type: PROCEDURE; Schema: public; Owner: lauradev
--

CREATE PROCEDURE public.place_sales_order(IN p_customer_id integer, IN p_order_date date, IN p_warehouse_id character, IN p_products jsonb, IN p_shipping_address text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_sales_order_id integer;
    v_total_amount numeric(14,2) := 0;
    item jsonb;
    v_product_id integer;
    v_quantity integer;
    v_selling_price numeric(12,2);
    v_on_hand integer;
BEGIN
    -- 1. Create the order header with a placeholder total
    INSERT INTO sales_orders (customer_id, order_date, status, total_amount, warehouse_id, shipping_address)
    VALUES (p_customer_id, p_order_date, 'pending', 0, p_warehouse_id, p_shipping_address)
    RETURNING sales_order_id INTO v_sales_order_id;

    -- 2. Loop through each requested product
    FOR item IN SELECT * FROM jsonb_array_elements(p_products)
    LOOP
        v_product_id := (item->>'product_id')::integer;
        v_quantity   := (item->>'quantity')::integer;

        -- Lock the inventory row so concurrent orders can't both pass the check
        SELECT quantity_on_hand INTO v_on_hand
        FROM inventory
        WHERE product_id = v_product_id
          AND warehouse_id = p_warehouse_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No inventory record for product % at warehouse %', v_product_id, p_warehouse_id;
        END IF;

        IF v_on_hand < v_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product %: have %, need %', v_product_id, v_on_hand, v_quantity;
        END IF;

        -- Get current selling price
        SELECT selling_price INTO v_selling_price
        FROM products
        WHERE product_id = v_product_id;

        -- Insert the line item
        INSERT INTO sales_order_items (sales_order_id, product_id, quantity, unit_price, line_total)
        VALUES (v_sales_order_id, v_product_id, v_quantity, v_selling_price, v_selling_price * v_quantity);

        -- Decrement inventory
        UPDATE inventory
        SET quantity_on_hand = quantity_on_hand - v_quantity,
            last_updated = CURRENT_TIMESTAMP
        WHERE product_id = v_product_id
          AND warehouse_id = p_warehouse_id;

        v_total_amount := v_total_amount + (v_selling_price * v_quantity);
    END LOOP;

    -- 3. Update the order total now that we know it
    UPDATE sales_orders
    SET total_amount = v_total_amount
    WHERE sales_order_id = v_sales_order_id;

END;
$$;


ALTER PROCEDURE public.place_sales_order(IN p_customer_id integer, IN p_order_date date, IN p_warehouse_id character, IN p_products jsonb, IN p_shipping_address text) OWNER TO lauradev;

--
-- TOC entry 293 (class 1255 OID 18116)
-- Name: process_return(integer, integer, integer, character varying, boolean, character varying, integer, text); Type: PROCEDURE; Schema: public; Owner: lauradev
--

CREATE PROCEDURE public.process_return(IN p_sales_order_id integer, IN p_product_id integer, IN p_quantity integer, IN p_reason character varying, IN p_restock boolean, IN p_condition character varying DEFAULT 'unknown'::character varying, IN p_handled_by_employee_id integer DEFAULT NULL::integer, IN p_notes text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_customer_id     integer;
    v_warehouse_id    character(2);
    v_unit_price      numeric(12,2);
    v_refund_amount   numeric(12,2);
    v_return_id       integer;
BEGIN
    -- Pull customer + warehouse from the original sales order
    SELECT customer_id, warehouse_id
    INTO v_customer_id, v_warehouse_id
    FROM public.sales_orders
    WHERE sales_order_id = p_sales_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sales order % not found', p_sales_order_id;
    END IF;

    -- Get the original unit_price for this product on this order
    SELECT unit_price
    INTO v_unit_price
    FROM public.sales_order_items
    WHERE sales_order_id = p_sales_order_id
      AND product_id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % was not part of sales order %', p_product_id, p_sales_order_id;
    END IF;

    -- Validate the handling employee, if provided
    IF p_handled_by_employee_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.employees WHERE employee_id = p_handled_by_employee_id
    ) THEN
        RAISE EXCEPTION 'Employee % not found', p_handled_by_employee_id;
    END IF;

    -- Compute refund_amount from the original unit_price
    v_refund_amount := v_unit_price * p_quantity;

    -- 1. Insert into returns
    INSERT INTO public.returns
        (sales_order_id, customer_id, product_id, quantity, return_date,
         reason, condition, status, resolution, refund_amount, restocked,
         warehouse_id, handled_by_employee_id, notes)
    VALUES
        (p_sales_order_id, v_customer_id, p_product_id, p_quantity, CURRENT_DATE,
         p_reason, p_condition, 'approved',
         CASE WHEN p_restock THEN 'restocked' ELSE 'refunded' END,
         v_refund_amount, p_restock, v_warehouse_id,
         p_handled_by_employee_id, p_notes)
    RETURNING return_id INTO v_return_id;

    -- 2. If restock = true, increment inventory.quantity_on_hand
    IF p_restock THEN
        -- Lock the row to avoid concurrent restocks racing on the same row
        PERFORM 1
        FROM public.inventory
        WHERE product_id = p_product_id
          AND warehouse_id = v_warehouse_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No inventory record for product % at warehouse %',
                p_product_id, v_warehouse_id;
        END IF;

        UPDATE public.inventory
        SET quantity_on_hand = quantity_on_hand + p_quantity,
            last_updated = CURRENT_TIMESTAMP
        WHERE product_id = p_product_id
          AND warehouse_id = v_warehouse_id;
    END IF;

    -- 3. Finalize returns.status
    UPDATE public.returns
    SET status = 'completed'
    WHERE return_id = v_return_id;

END;
$$;


ALTER PROCEDURE public.process_return(IN p_sales_order_id integer, IN p_product_id integer, IN p_quantity integer, IN p_reason character varying, IN p_restock boolean, IN p_condition character varying, IN p_handled_by_employee_id integer, IN p_notes text) OWNER TO lauradev;

--
-- TOC entry 294 (class 1255 OID 18115)
-- Name: receive_m_purchase_order(integer, character, public.received_item[]); Type: PROCEDURE; Schema: public; Owner: lauradev
--

CREATE PROCEDURE public.receive_m_purchase_order(IN p_purchase_order_id integer, IN p_factory_id character, IN p_received_items public.received_item[])
    LANGUAGE plpgsql
    AS $$
DECLARE
    item                public.received_item;
    v_open_lines        integer;
BEGIN
    -- Validate the PO exists
    IF NOT EXISTS (
        SELECT 1 FROM public.purchase_orders
        WHERE purchase_order_id = p_purchase_order_id
    ) THEN
        RAISE EXCEPTION 'Purchase order % not found', p_purchase_order_id;
    END IF;

    FOREACH item IN ARRAY p_received_items LOOP

        -- Guard: item must belong to this PO
        IF NOT EXISTS (
            SELECT 1 FROM public.purchase_order_items
            WHERE purchase_order_id = p_purchase_order_id
              AND material_id = item.material_id
        ) THEN
            RAISE EXCEPTION 'Material % is not on purchase order %',
                item.material_id, p_purchase_order_id;
        END IF;

        -- 1. Update purchase_order_items: record what was received
        UPDATE public.purchase_order_items
        SET quantity_received = quantity_received + item.quantity_received
        WHERE purchase_order_id = p_purchase_order_id
          AND material_id = item.material_id;

        -- 2. Increment materials_inventory.quantity_on_hand
        --    (and stamp last_updated), inserting a row if none exists yet
        INSERT INTO public.materials_inventory
            (material_id, factory_id, quantity_on_hand, reorder_level, last_updated)
        VALUES
            (item.material_id, p_factory_id, item.quantity_received, 0, CURRENT_TIMESTAMP)
        ON CONFLICT (material_id, factory_id) DO UPDATE
        SET quantity_on_hand = public.materials_inventory.quantity_on_hand
                                + EXCLUDED.quantity_on_hand,
            last_updated     = CURRENT_TIMESTAMP;

    END LOOP;

    -- 3. Update purchase_orders.status based on whether all lines are fully received
    SELECT COUNT(*) INTO v_open_lines
    FROM public.purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id
      AND quantity_received < quantity;

    UPDATE public.purchase_orders
    SET status = CASE WHEN v_open_lines = 0 THEN 'received' ELSE 'partially_received' END
    WHERE purchase_order_id = p_purchase_order_id;

    COMMIT;
END;
$$;


ALTER PROCEDURE public.receive_m_purchase_order(IN p_purchase_order_id integer, IN p_factory_id character, IN p_received_items public.received_item[]) OWNER TO lauradev;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 222 (class 1259 OID 16874)
-- Name: factories; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.factories (
    factory_id character(2) NOT NULL,
    factory_name character varying(100) NOT NULL,
    city character varying(80),
    state character varying(80),
    capacity_units_per_day integer DEFAULT 0 NOT NULL,
    manager_employee_id integer,
    CONSTRAINT chk_factories_capacity CHECK ((capacity_units_per_day >= 0))
);


ALTER TABLE public.factories OWNER TO lauradev;

--
-- TOC entry 226 (class 1259 OID 16955)
-- Name: production_lines; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.production_lines (
    production_line_id integer NOT NULL,
    factory_id character(2) NOT NULL,
    line_name character varying(100) NOT NULL,
    line_type character varying(50),
    capacity_per_day integer DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    CONSTRAINT chk_production_lines_capacity CHECK ((capacity_per_day >= 0)),
    CONSTRAINT chk_production_lines_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'maintenance'::character varying])::text[])))
);


ALTER TABLE public.production_lines OWNER TO lauradev;

--
-- TOC entry 227 (class 1259 OID 16972)
-- Name: products; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.products (
    product_id integer NOT NULL,
    product_name character varying(100) NOT NULL,
    description text,
    category_id integer NOT NULL,
    dimensions character varying(100),
    weight numeric(10,2),
    load_capacity numeric(10,2),
    unit_cost numeric(12,2) DEFAULT 0 NOT NULL,
    selling_price numeric(12,2) DEFAULT 0 NOT NULL,
    production_time_days integer,
    active_flag boolean DEFAULT true NOT NULL,
    production_line_id integer,
    CONSTRAINT chk_products_load_capacity CHECK ((load_capacity > (0)::numeric)),
    CONSTRAINT chk_products_production_time CHECK ((production_time_days > 0)),
    CONSTRAINT chk_products_selling_price CHECK ((selling_price >= (0)::numeric)),
    CONSTRAINT chk_products_unit_cost CHECK ((unit_cost >= (0)::numeric)),
    CONSTRAINT chk_products_weight CHECK ((weight > (0)::numeric))
);


ALTER TABLE public.products OWNER TO lauradev;

--
-- TOC entry 239 (class 1259 OID 17219)
-- Name: work_orders; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.work_orders (
    work_order_id integer NOT NULL,
    factory_id character(2) NOT NULL,
    production_line_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    start_date date,
    due_date date,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    priority character varying(20) DEFAULT 'normal'::character varying NOT NULL,
    CONSTRAINT chk_work_orders_dates CHECK (((due_date IS NULL) OR (due_date >= start_date))),
    CONSTRAINT chk_work_orders_priority CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'normal'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))),
    CONSTRAINT chk_work_orders_quantity CHECK ((quantity > 0)),
    CONSTRAINT chk_work_orders_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying, 'on_hold'::character varying])::text[])))
);


ALTER TABLE public.work_orders OWNER TO lauradev;

--
-- TOC entry 264 (class 1259 OID 18032)
-- Name: active_work_orders; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.active_work_orders AS
 SELECT wo.work_order_id,
    wo.quantity,
    wo.start_date,
    wo.due_date,
    wo.priority,
    wo.status,
    p.product_name,
    f.factory_name,
    pl.line_name
   FROM (((public.work_orders wo
     JOIN public.products p ON ((wo.product_id = p.product_id)))
     JOIN public.factories f ON ((wo.factory_id = f.factory_id)))
     JOIN public.production_lines pl ON ((wo.production_line_id = pl.production_line_id)))
  WHERE ((wo.status)::text <> ALL (ARRAY[('completed'::character varying)::text, ('cancelled'::character varying)::text]))
  ORDER BY
        CASE wo.priority
            WHEN 'urgent'::text THEN 1
            WHEN 'high'::text THEN 2
            WHEN 'normal'::text THEN 3
            WHEN 'low'::text THEN 4
            ELSE NULL::integer
        END, wo.due_date;


ALTER VIEW public.active_work_orders OWNER TO lauradev;

--
-- TOC entry 221 (class 1259 OID 16861)
-- Name: customers; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.customers (
    customer_id integer NOT NULL,
    customer_name character varying(100),
    contact_name character varying(100),
    email character varying(100) NOT NULL,
    phone character(30) NOT NULL,
    billing_address text NOT NULL,
    city character varying(80),
    state character varying(80),
    country character(2) NOT NULL,
    CONSTRAINT chk_customers_email CHECK (((email)::text ~~ '%@%.%'::text))
);


ALTER TABLE public.customers OWNER TO lauradev;

--
-- TOC entry 243 (class 1259 OID 17859)
-- Name: customers_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.customers ALTER COLUMN customer_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.customers_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 225 (class 1259 OID 16906)
-- Name: departments; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.departments (
    department_id character(2) NOT NULL,
    department_name character varying(50),
    location_type character varying(100),
    factory_id character(2) NOT NULL,
    warehouse_id character(2) NOT NULL,
    supervisor_employee_id integer
);


ALTER TABLE public.departments OWNER TO lauradev;

--
-- TOC entry 224 (class 1259 OID 16894)
-- Name: employees; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.employees (
    employee_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    phone character varying(30),
    job_title character varying(100),
    department_id character(2),
    factory_id character(2),
    warehouse_id character(2),
    hire_date date NOT NULL,
    employment_status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    CONSTRAINT chk_employees_email CHECK (((email)::text ~~ '%@%.%'::text)),
    CONSTRAINT chk_employees_status CHECK (((employment_status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'terminated'::character varying, 'on_leave'::character varying])::text[])))
);


ALTER TABLE public.employees OWNER TO lauradev;

--
-- TOC entry 223 (class 1259 OID 16884)
-- Name: warehouses; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.warehouses (
    warehouse_id character(2) NOT NULL,
    warehouse_name character varying(100) NOT NULL,
    city character varying(80),
    state character varying(80),
    storage_capacity_units integer DEFAULT 0 CONSTRAINT warehouses_capacity_not_null NOT NULL,
    manager_employee_id integer,
    CONSTRAINT chk_warehouses_capacity CHECK ((storage_capacity_units >= 0))
);


ALTER TABLE public.warehouses OWNER TO lauradev;

--
-- TOC entry 265 (class 1259 OID 18037)
-- Name: employee_directory; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.employee_directory AS
 SELECT e.employee_id,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS full_name,
    e.job_title,
    e.email,
    e.phone,
    e.hire_date,
    e.employment_status,
    d.department_name,
    COALESCE(f.factory_name, w.warehouse_name) AS location
   FROM (((public.employees e
     LEFT JOIN public.departments d ON ((e.department_id = d.department_id)))
     LEFT JOIN public.factories f ON ((e.factory_id = f.factory_id)))
     LEFT JOIN public.warehouses w ON ((e.warehouse_id = w.warehouse_id)))
  WHERE ((e.employment_status)::text = 'active'::text)
  ORDER BY e.last_name, e.first_name;


ALTER VIEW public.employee_directory OWNER TO lauradev;

--
-- TOC entry 244 (class 1259 OID 17860)
-- Name: employees_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.employees ALTER COLUMN employee_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.employees_employee_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 240 (class 1259 OID 17249)
-- Name: quality_inspections; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.quality_inspections (
    inspection_id integer NOT NULL,
    product_id integer NOT NULL,
    factory_id character(2) NOT NULL,
    production_line_id integer NOT NULL,
    inspection_date date NOT NULL,
    inspector_employee_id integer NOT NULL,
    result character varying(20) NOT NULL,
    defect_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT chk_quality_defect_count CHECK ((defect_count >= 0)),
    CONSTRAINT chk_quality_result CHECK (((result)::text = ANY ((ARRAY['passed'::character varying, 'failed'::character varying, 'pending'::character varying, 'conditional'::character varying])::text[])))
);


ALTER TABLE public.quality_inspections OWNER TO lauradev;

--
-- TOC entry 266 (class 1259 OID 18042)
-- Name: failed_quality_inspections; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.failed_quality_inspections AS
 SELECT qi.inspection_id,
    qi.inspection_date,
    qi.defect_count,
    p.product_name,
    p.product_id,
    f.factory_name,
    pl.line_name,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS inspector_name
   FROM ((((public.quality_inspections qi
     JOIN public.products p ON ((qi.product_id = p.product_id)))
     JOIN public.factories f ON ((qi.factory_id = f.factory_id)))
     JOIN public.production_lines pl ON ((qi.production_line_id = pl.production_line_id)))
     JOIN public.employees e ON ((qi.inspector_employee_id = e.employee_id)))
  WHERE ((qi.result)::text = 'failed'::text)
  ORDER BY qi.defect_count DESC;


ALTER VIEW public.failed_quality_inspections OWNER TO lauradev;

--
-- TOC entry 230 (class 1259 OID 17029)
-- Name: products_inventory; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.products_inventory (
    inventory_id integer CONSTRAINT inventory_inventory_id_not_null NOT NULL,
    warehouse_id character(2) CONSTRAINT inventory_warehouse_id_not_null NOT NULL,
    product_id integer CONSTRAINT inventory_product_id_not_null NOT NULL,
    quantity_on_hand integer DEFAULT 0 CONSTRAINT inventory_quantity_on_hand_not_null NOT NULL,
    reorder_level integer DEFAULT 0 CONSTRAINT inventory_reorder_level_not_null NOT NULL,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP CONSTRAINT inventory_last_updated_not_null NOT NULL
);


ALTER TABLE public.products_inventory OWNER TO lauradev;

--
-- TOC entry 267 (class 1259 OID 18047)
-- Name: inventory_below_reorder; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.inventory_below_reorder AS
 SELECT i.inventory_id,
    p.product_name,
    p.product_id,
    i.quantity_on_hand,
    i.reorder_level,
    (i.reorder_level - i.quantity_on_hand) AS units_short,
    w.warehouse_name,
    i.last_updated
   FROM ((public.products_inventory i
     JOIN public.products p ON ((i.product_id = p.product_id)))
     JOIN public.warehouses w ON ((i.warehouse_id = w.warehouse_id)))
  WHERE (i.quantity_on_hand <= i.reorder_level)
  ORDER BY (i.reorder_level - i.quantity_on_hand) DESC;


ALTER VIEW public.inventory_below_reorder OWNER TO lauradev;

--
-- TOC entry 245 (class 1259 OID 17861)
-- Name: inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.products_inventory ALTER COLUMN inventory_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventory_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 233 (class 1259 OID 17094)
-- Name: machine_downtime; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.machine_downtime (
    downtime_id integer NOT NULL,
    machine_id integer NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone,
    downtime_reason text,
    impact_hours numeric(6,2),
    CONSTRAINT chk_downtime_end_after_start CHECK (((end_time IS NULL) OR (end_time > start_time)))
);


ALTER TABLE public.machine_downtime OWNER TO lauradev;

--
-- TOC entry 246 (class 1259 OID 17862)
-- Name: machine_downtime_downtime_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.machine_downtime ALTER COLUMN downtime_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.machine_downtime_downtime_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 228 (class 1259 OID 16998)
-- Name: machines; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.machines (
    machine_id integer NOT NULL,
    production_line_id integer NOT NULL,
    machine_name character varying(100) NOT NULL,
    machine_type character varying(50),
    install_date date,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    hourly_rate numeric(10,2),
    maintenance_cycle_days integer,
    CONSTRAINT chk_machines_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'maintenance'::character varying, 'decommissioned'::character varying])::text[])))
);


ALTER TABLE public.machines OWNER TO lauradev;

--
-- TOC entry 232 (class 1259 OID 17074)
-- Name: maintenance_plans; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.maintenance_plans (
    maintenance_plan_id integer NOT NULL,
    machine_id integer NOT NULL,
    maintenance_type character varying(50) NOT NULL,
    frequency_days integer NOT NULL,
    estimated_duration_hours numeric(6,2),
    assigned_employee_id integer NOT NULL,
    CONSTRAINT chk_maintenance_plans_type CHECK (((maintenance_type)::text = ANY ((ARRAY['preventive'::character varying, 'corrective'::character varying, 'predictive'::character varying, 'emergency'::character varying])::text[])))
);


ALTER TABLE public.maintenance_plans OWNER TO lauradev;

--
-- TOC entry 268 (class 1259 OID 18052)
-- Name: machine_maintenance_schedule; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.machine_maintenance_schedule AS
 SELECT m.machine_id,
    m.machine_name,
    m.machine_type,
    m.status,
    m.maintenance_cycle_days,
    mp.maintenance_plan_id,
    mp.maintenance_type,
    mp.frequency_days,
    mp.estimated_duration_hours,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS assigned_technician,
    pl.line_name,
    f.factory_name
   FROM ((((public.machines m
     JOIN public.maintenance_plans mp ON ((m.machine_id = mp.machine_id)))
     JOIN public.employees e ON ((mp.assigned_employee_id = e.employee_id)))
     JOIN public.production_lines pl ON ((m.production_line_id = pl.production_line_id)))
     JOIN public.factories f ON ((pl.factory_id = f.factory_id)))
  ORDER BY mp.frequency_days;


ALTER VIEW public.machine_maintenance_schedule OWNER TO lauradev;

--
-- TOC entry 269 (class 1259 OID 18057)
-- Name: machines_down; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.machines_down AS
 SELECT m.machine_id,
    m.machine_name,
    md.downtime_reason,
    md.impact_hours,
    f.factory_name
   FROM (((public.machines m
     JOIN public.machine_downtime md ON ((m.machine_id = md.machine_id)))
     JOIN public.production_lines p ON ((m.production_line_id = p.production_line_id)))
     JOIN public.factories f ON ((f.factory_id = p.factory_id)))
  ORDER BY md.impact_hours DESC;


ALTER VIEW public.machines_down OWNER TO lauradev;

--
-- TOC entry 247 (class 1259 OID 17863)
-- Name: machines_machine_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.machines ALTER COLUMN machine_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.machines_machine_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 231 (class 1259 OID 17053)
-- Name: maintenance_logs; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.maintenance_logs (
    maintenance_log_id integer NOT NULL,
    machine_id integer NOT NULL,
    maintenance_date date NOT NULL,
    description text,
    downtime_hours numeric(6,2),
    cost numeric(12,2),
    technician_employee_id integer NOT NULL
);


ALTER TABLE public.maintenance_logs OWNER TO lauradev;

--
-- TOC entry 270 (class 1259 OID 18062)
-- Name: maintenance_cost_by_machine; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.maintenance_cost_by_machine AS
 SELECT m.machine_id,
    m.machine_name,
    m.machine_type,
    count(ml.maintenance_log_id) AS total_maintenance_events,
    sum(ml.cost) AS total_maintenance_cost,
    sum(ml.downtime_hours) AS total_downtime_hours,
    round(avg(ml.cost), 2) AS avg_cost_per_event,
    f.factory_name,
    pl.line_name
   FROM (((public.machines m
     JOIN public.maintenance_logs ml ON ((m.machine_id = ml.machine_id)))
     JOIN public.production_lines pl ON ((m.production_line_id = pl.production_line_id)))
     JOIN public.factories f ON ((pl.factory_id = f.factory_id)))
  GROUP BY m.machine_id, m.machine_name, m.machine_type, f.factory_name, pl.line_name
  ORDER BY (sum(ml.cost)) DESC;


ALTER VIEW public.maintenance_cost_by_machine OWNER TO lauradev;

--
-- TOC entry 248 (class 1259 OID 17864)
-- Name: maintenance_logs_maintenance_log_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_logs ALTER COLUMN maintenance_log_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.maintenance_logs_maintenance_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 249 (class 1259 OID 17865)
-- Name: maintenance_plans_maintenance_plan_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_plans ALTER COLUMN maintenance_plan_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.maintenance_plans_maintenance_plan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 242 (class 1259 OID 17345)
-- Name: raw_materials_inventory; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.raw_materials_inventory (
    materials_inventory_id integer CONSTRAINT materials_inventory_materials_inventory_id_not_null NOT NULL,
    material_id integer CONSTRAINT materials_inventory_material_id_not_null NOT NULL,
    factory_id character(2) CONSTRAINT materials_inventory_factory_id_not_null NOT NULL,
    quantity_on_hand numeric(12,2) DEFAULT 0 CONSTRAINT materials_inventory_quantity_on_hand_not_null NOT NULL,
    reorder_level numeric(12,2) DEFAULT 0 CONSTRAINT materials_inventory_reorder_level_not_null NOT NULL,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP CONSTRAINT materials_inventory_last_updated_not_null NOT NULL,
    CONSTRAINT chk_mat_inv_quantity CHECK ((quantity_on_hand >= (0)::numeric)),
    CONSTRAINT chk_mat_inv_reorder CHECK ((reorder_level >= (0)::numeric))
);


ALTER TABLE public.raw_materials_inventory OWNER TO lauradev;

--
-- TOC entry 251 (class 1259 OID 17867)
-- Name: materials_inventory_materials_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.raw_materials_inventory ALTER COLUMN materials_inventory_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.materials_inventory_materials_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 229 (class 1259 OID 17013)
-- Name: raw_materials; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.raw_materials (
    material_id integer CONSTRAINT materials_material_id_not_null NOT NULL,
    material_name character varying(100) CONSTRAINT materials_material_name_not_null NOT NULL,
    material_type character varying(50),
    unit_cost numeric(12,2) DEFAULT 0 CONSTRAINT materials_unit_cost_not_null NOT NULL,
    unit_of_measure character varying(30) CONSTRAINT materials_unit_of_measure_not_null NOT NULL,
    supplier_id integer CONSTRAINT materials_supplier_id_not_null NOT NULL,
    dimensions character varying(100),
    CONSTRAINT chk_materials_unit_cost CHECK ((unit_cost >= (0)::numeric)),
    CONSTRAINT chk_materials_uom CHECK (((unit_of_measure)::text = ANY ((ARRAY['units'::character varying, 'kg'::character varying, 'lbs'::character varying, 'meters'::character varying, 'feet'::character varying, 'liters'::character varying, 'gallons'::character varying, 'sqft'::character varying, 'sqm'::character varying, 'yards'::character varying, 'board_feet'::character varying])::text[])))
);


ALTER TABLE public.raw_materials OWNER TO lauradev;

--
-- TOC entry 250 (class 1259 OID 17866)
-- Name: materials_material_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.raw_materials ALTER COLUMN material_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.materials_material_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 220 (class 1259 OID 16852)
-- Name: suppliers; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.suppliers (
    supplier_id integer NOT NULL,
    supplier_name character varying(100) NOT NULL,
    contact_name character varying(100) NOT NULL,
    phone character(30),
    email character varying(100) NOT NULL,
    street text,
    city character varying(80),
    state character varying(80),
    lead_time_days integer,
    rating numeric(3,1),
    zipcode character(10) NOT NULL,
    CONSTRAINT chk_suppliers_email CHECK (((email)::text ~~ '%@%.%'::text)),
    CONSTRAINT chk_suppliers_lead_time CHECK ((lead_time_days > 0)),
    CONSTRAINT chk_suppliers_rating CHECK (((rating >= (0)::numeric) AND (rating <= (10)::numeric)))
);


ALTER TABLE public.suppliers OWNER TO lauradev;

--
-- TOC entry 271 (class 1259 OID 18067)
-- Name: materials_to_reorder; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.materials_to_reorder AS
 SELECT mi.materials_inventory_id,
    m.material_name,
    m.material_type,
    m.unit_of_measure,
    mi.quantity_on_hand,
    mi.reorder_level,
    (mi.reorder_level - mi.quantity_on_hand) AS units_short,
    f.factory_name,
    s.supplier_name,
    s.lead_time_days
   FROM (((public.raw_materials_inventory mi
     JOIN public.raw_materials m ON ((mi.material_id = m.material_id)))
     JOIN public.factories f ON ((mi.factory_id = f.factory_id)))
     JOIN public.suppliers s ON ((m.supplier_id = s.supplier_id)))
  WHERE (mi.quantity_on_hand <= mi.reorder_level)
  ORDER BY (mi.reorder_level - mi.quantity_on_hand) DESC;


ALTER VIEW public.materials_to_reorder OWNER TO lauradev;

--
-- TOC entry 235 (class 1259 OID 17126)
-- Name: purchase_order_items; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.purchase_order_items (
    purchase_order_item_id integer NOT NULL,
    purchase_order_id integer NOT NULL,
    material_id integer NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    unit_cost numeric(12,2) DEFAULT 0 NOT NULL,
    line_total numeric(14,2) DEFAULT 0 NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    CONSTRAINT chk_po_items_line_total CHECK ((line_total >= (0)::numeric)),
    CONSTRAINT chk_po_items_quantity CHECK ((quantity > 0)),
    CONSTRAINT chk_po_items_unit_cost CHECK ((unit_cost >= (0)::numeric))
);


ALTER TABLE public.purchase_order_items OWNER TO lauradev;

--
-- TOC entry 234 (class 1259 OID 17109)
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.purchase_orders (
    purchase_order_id integer NOT NULL,
    supplier_id integer NOT NULL,
    order_date date NOT NULL,
    expected_date date,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    total_cost numeric(14,2) DEFAULT 0 NOT NULL,
    CONSTRAINT chk_purchase_orders_dates CHECK (((expected_date IS NULL) OR (expected_date >= order_date))),
    CONSTRAINT chk_purchase_orders_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'shipped'::character varying, 'received'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT chk_purchase_orders_total CHECK ((total_cost >= (0)::numeric))
);


ALTER TABLE public.purchase_orders OWNER TO lauradev;

--
-- TOC entry 272 (class 1259 OID 18072)
-- Name: open_purchase_orders; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.open_purchase_orders AS
 SELECT po.purchase_order_id,
    po.order_date,
    po.expected_date,
    po.status,
    po.total_cost,
    s.supplier_name,
    s.contact_name,
    s.phone,
    count(poi.purchase_order_item_id) AS total_line_items
   FROM ((public.purchase_orders po
     JOIN public.suppliers s ON ((po.supplier_id = s.supplier_id)))
     JOIN public.purchase_order_items poi ON ((po.purchase_order_id = poi.purchase_order_id)))
  WHERE ((po.status)::text <> ALL (ARRAY[('received'::character varying)::text, ('cancelled'::character varying)::text]))
  GROUP BY po.purchase_order_id, po.order_date, po.expected_date, po.status, po.total_cost, s.supplier_name, s.contact_name, s.phone
  ORDER BY po.expected_date;


ALTER VIEW public.open_purchase_orders OWNER TO lauradev;

--
-- TOC entry 241 (class 1259 OID 17284)
-- Name: returns; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.returns (
    return_id integer NOT NULL,
    sales_order_id integer NOT NULL,
    customer_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    return_date date NOT NULL,
    reason character varying(255) NOT NULL,
    condition character varying(50) DEFAULT 'unknown'::character varying NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    resolution character varying(50),
    refund_amount numeric(12,2) DEFAULT 0 NOT NULL,
    restocked boolean DEFAULT false NOT NULL,
    warehouse_id character(2),
    handled_by_employee_id integer,
    notes text,
    CONSTRAINT chk_returns_condition CHECK (((condition)::text = ANY ((ARRAY['good'::character varying, 'damaged'::character varying, 'unusable'::character varying, 'unknown'::character varying])::text[]))),
    CONSTRAINT chk_returns_quantity CHECK ((quantity > 0)),
    CONSTRAINT chk_returns_refund CHECK ((refund_amount >= (0)::numeric)),
    CONSTRAINT chk_returns_resolution CHECK (((resolution)::text = ANY ((ARRAY['refund'::character varying, 'replacement'::character varying, 'store_credit'::character varying, 'repair'::character varying, 'rejected'::character varying])::text[]))),
    CONSTRAINT chk_returns_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'received'::character varying, 'inspected'::character varying, 'resolved'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public.returns OWNER TO lauradev;

--
-- TOC entry 236 (class 1259 OID 17150)
-- Name: sales_orders; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.sales_orders (
    sales_order_id integer NOT NULL,
    customer_id integer NOT NULL,
    order_date date NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    total_amount numeric(14,2) DEFAULT 0 NOT NULL,
    warehouse_id character(2) NOT NULL,
    shipping_address text,
    CONSTRAINT chk_sales_orders_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT chk_sales_orders_total CHECK ((total_amount >= (0)::numeric))
);


ALTER TABLE public.sales_orders OWNER TO lauradev;

--
-- TOC entry 273 (class 1259 OID 18077)
-- Name: open_returns; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.open_returns AS
 SELECT r.return_id,
    r.return_date,
    r.reason,
    r.condition,
    r.status,
    r.resolution,
    r.refund_amount,
    r.restocked,
    r.quantity,
    c.customer_name,
    c.email,
    p.product_name,
    so.sales_order_id,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS handled_by
   FROM ((((public.returns r
     JOIN public.customers c ON ((r.customer_id = c.customer_id)))
     JOIN public.products p ON ((r.product_id = p.product_id)))
     JOIN public.sales_orders so ON ((r.sales_order_id = so.sales_order_id)))
     LEFT JOIN public.employees e ON ((r.handled_by_employee_id = e.employee_id)))
  WHERE ((r.status)::text <> ALL (ARRAY[('resolved'::character varying)::text, ('rejected'::character varying)::text]))
  ORDER BY r.return_date;


ALTER VIEW public.open_returns OWNER TO lauradev;

--
-- TOC entry 238 (class 1259 OID 17199)
-- Name: shipments; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.shipments (
    shipment_id integer NOT NULL,
    sales_order_id integer NOT NULL,
    warehouse_id character(2) NOT NULL,
    ship_date date,
    delivery_date date,
    carrier character varying(100),
    tracking_number character varying(100),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    CONSTRAINT chk_shipments_dates CHECK (((delivery_date IS NULL) OR (delivery_date >= ship_date))),
    CONSTRAINT chk_shipments_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'in_transit'::character varying, 'delivered'::character varying, 'returned'::character varying, 'lost'::character varying])::text[])))
);


ALTER TABLE public.shipments OWNER TO lauradev;

--
-- TOC entry 274 (class 1259 OID 18082)
-- Name: pending_shipments; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.pending_shipments AS
 SELECT sh.shipment_id,
    sh.ship_date,
    sh.delivery_date,
    sh.carrier,
    sh.tracking_number,
    sh.status,
    so.sales_order_id,
    so.order_date,
    so.shipping_address,
    c.customer_name,
    c.email,
    w.warehouse_name
   FROM (((public.shipments sh
     JOIN public.sales_orders so ON ((sh.sales_order_id = so.sales_order_id)))
     JOIN public.customers c ON ((so.customer_id = c.customer_id)))
     JOIN public.warehouses w ON ((sh.warehouse_id = w.warehouse_id)))
  WHERE ((sh.status)::text <> ALL (ARRAY[('delivered'::character varying)::text, ('returned'::character varying)::text, ('lost'::character varying)::text]))
  ORDER BY sh.ship_date;


ALTER VIEW public.pending_shipments OWNER TO lauradev;

--
-- TOC entry 219 (class 1259 OID 16843)
-- Name: product_categories; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.product_categories (
    category_id integer NOT NULL,
    category_name character varying(100) NOT NULL,
    description text
);


ALTER TABLE public.product_categories OWNER TO lauradev;

--
-- TOC entry 252 (class 1259 OID 17868)
-- Name: product_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.product_categories ALTER COLUMN category_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.product_categories_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 280 (class 1259 OID 18205)
-- Name: product_materials; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.product_materials (
    product_id integer NOT NULL,
    material_id integer NOT NULL,
    quantity_required integer
);


ALTER TABLE public.product_materials OWNER TO lauradev;

--
-- TOC entry 253 (class 1259 OID 17869)
-- Name: production_lines_production_line_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.production_lines ALTER COLUMN production_line_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.production_lines_production_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 275 (class 1259 OID 18087)
-- Name: products_on_hand; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.products_on_hand AS
 SELECT i.product_id,
    p.product_name,
    i.quantity_on_hand,
    w.warehouse_name
   FROM ((public.products_inventory i
     JOIN public.products p ON ((i.product_id = p.product_id)))
     JOIN public.warehouses w ON ((i.warehouse_id = w.warehouse_id)))
  ORDER BY w.warehouse_name;


ALTER VIEW public.products_on_hand OWNER TO lauradev;

--
-- TOC entry 254 (class 1259 OID 17870)
-- Name: products_product_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.products ALTER COLUMN product_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 255 (class 1259 OID 17871)
-- Name: purchase_order_items_purchase_order_item_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.purchase_order_items ALTER COLUMN purchase_order_item_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purchase_order_items_purchase_order_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 256 (class 1259 OID 17872)
-- Name: purchase_orders_purchase_order_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.purchase_orders ALTER COLUMN purchase_order_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purchase_orders_purchase_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 276 (class 1259 OID 18092)
-- Name: quality_inspection_summary; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.quality_inspection_summary AS
 SELECT qi.inspection_id,
    qi.inspection_date,
    qi.result,
    qi.defect_count,
    p.product_name,
    f.factory_name,
    pl.line_name,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS inspector_name
   FROM ((((public.quality_inspections qi
     JOIN public.products p ON ((qi.product_id = p.product_id)))
     JOIN public.factories f ON ((qi.factory_id = f.factory_id)))
     JOIN public.production_lines pl ON ((qi.production_line_id = pl.production_line_id)))
     JOIN public.employees e ON ((qi.inspector_employee_id = e.employee_id)))
  ORDER BY qi.inspection_date DESC;


ALTER VIEW public.quality_inspection_summary OWNER TO lauradev;

--
-- TOC entry 257 (class 1259 OID 17873)
-- Name: quality_inspections_inspection_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.quality_inspections ALTER COLUMN inspection_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.quality_inspections_inspection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 258 (class 1259 OID 17874)
-- Name: returns_return_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.returns ALTER COLUMN return_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.returns_return_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 237 (class 1259 OID 17175)
-- Name: sales_order_items; Type: TABLE; Schema: public; Owner: lauradev
--

CREATE TABLE public.sales_order_items (
    sales_order_item_id integer NOT NULL,
    sales_order_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    unit_price numeric(12,2) DEFAULT 0 NOT NULL,
    line_total numeric(14,2) DEFAULT 0 NOT NULL,
    CONSTRAINT chk_so_items_line_total CHECK ((line_total >= (0)::numeric)),
    CONSTRAINT chk_so_items_quantity CHECK ((quantity > 0)),
    CONSTRAINT chk_so_items_unit_price CHECK ((unit_price >= (0)::numeric))
);


ALTER TABLE public.sales_order_items OWNER TO lauradev;

--
-- TOC entry 277 (class 1259 OID 18097)
-- Name: sales_order_details; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.sales_order_details AS
 SELECT so.sales_order_id,
    so.order_date,
    so.status,
    so.total_amount,
    so.shipping_address,
    c.customer_name,
    c.email,
    c.phone,
    p.product_name,
    soi.quantity,
    soi.unit_price,
    soi.line_total,
    w.warehouse_name
   FROM ((((public.sales_orders so
     JOIN public.customers c ON ((so.customer_id = c.customer_id)))
     JOIN public.sales_order_items soi ON ((so.sales_order_id = soi.sales_order_id)))
     JOIN public.products p ON ((soi.product_id = p.product_id)))
     JOIN public.warehouses w ON ((so.warehouse_id = w.warehouse_id)))
  ORDER BY so.order_date DESC;


ALTER VIEW public.sales_order_details OWNER TO lauradev;

--
-- TOC entry 259 (class 1259 OID 17875)
-- Name: sales_order_items_sales_order_item_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.sales_order_items ALTER COLUMN sales_order_item_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sales_order_items_sales_order_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 260 (class 1259 OID 17876)
-- Name: sales_orders_sales_order_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.sales_orders ALTER COLUMN sales_order_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sales_orders_sales_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 261 (class 1259 OID 17877)
-- Name: shipments_shipment_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.shipments ALTER COLUMN shipment_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.shipments_shipment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 278 (class 1259 OID 18102)
-- Name: supplier_catalog; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.supplier_catalog AS
 SELECT s.supplier_id,
    s.supplier_name,
    s.contact_name,
    s.phone,
    s.email,
    s.lead_time_days,
    s.rating,
    m.material_id,
    m.material_name,
    m.material_type,
    m.unit_cost,
    m.unit_of_measure
   FROM (public.suppliers s
     JOIN public.raw_materials m ON ((s.supplier_id = m.supplier_id)))
  ORDER BY s.rating DESC, s.supplier_name;


ALTER VIEW public.supplier_catalog OWNER TO lauradev;

--
-- TOC entry 262 (class 1259 OID 17878)
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.suppliers ALTER COLUMN supplier_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.suppliers_supplier_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 263 (class 1259 OID 17879)
-- Name: work_orders_work_order_id_seq; Type: SEQUENCE; Schema: public; Owner: lauradev
--

ALTER TABLE public.work_orders ALTER COLUMN work_order_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.work_orders_work_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 4231 (class 0 OID 16861)
-- Dependencies: 221
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.customers (customer_id, customer_name, contact_name, email, phone, billing_address, city, state, country) FROM stdin;
\.


--
-- TOC entry 4235 (class 0 OID 16906)
-- Dependencies: 225
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.departments (department_id, department_name, location_type, factory_id, warehouse_id, supervisor_employee_id) FROM stdin;
\.


--
-- TOC entry 4234 (class 0 OID 16894)
-- Dependencies: 224
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.employees (employee_id, first_name, last_name, email, phone, job_title, department_id, factory_id, warehouse_id, hire_date, employment_status) FROM stdin;
\.


--
-- TOC entry 4232 (class 0 OID 16874)
-- Dependencies: 222
-- Data for Name: factories; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.factories (factory_id, factory_name, city, state, capacity_units_per_day, manager_employee_id) FROM stdin;
F1	Dallas–Fort Worth Factory	Dallas–Fort Worth	Texas	1200	\N
F2	Atlanta Metro Factory	Atlanta	Georgia	1000	\N
F3	Phoenix–Buckeye Factory	Buckeye	Arizona	900	\N
\.


--
-- TOC entry 4243 (class 0 OID 17094)
-- Dependencies: 233
-- Data for Name: machine_downtime; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.machine_downtime (downtime_id, machine_id, start_time, end_time, downtime_reason, impact_hours) FROM stdin;
\.


--
-- TOC entry 4238 (class 0 OID 16998)
-- Dependencies: 228
-- Data for Name: machines; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.machines (machine_id, production_line_id, machine_name, machine_type, install_date, status, hourly_rate, maintenance_cycle_days) FROM stdin;
\.


--
-- TOC entry 4241 (class 0 OID 17053)
-- Dependencies: 231
-- Data for Name: maintenance_logs; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.maintenance_logs (maintenance_log_id, machine_id, maintenance_date, description, downtime_hours, cost, technician_employee_id) FROM stdin;
\.


--
-- TOC entry 4242 (class 0 OID 17074)
-- Dependencies: 232
-- Data for Name: maintenance_plans; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.maintenance_plans (maintenance_plan_id, machine_id, maintenance_type, frequency_days, estimated_duration_hours, assigned_employee_id) FROM stdin;
\.


--
-- TOC entry 4229 (class 0 OID 16843)
-- Dependencies: 219
-- Data for Name: product_categories; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.product_categories (category_id, category_name, description) FROM stdin;
\.


--
-- TOC entry 4274 (class 0 OID 18205)
-- Dependencies: 280
-- Data for Name: product_materials; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.product_materials (product_id, material_id, quantity_required) FROM stdin;
\.


--
-- TOC entry 4236 (class 0 OID 16955)
-- Dependencies: 226
-- Data for Name: production_lines; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.production_lines (production_line_id, factory_id, line_name, line_type, capacity_per_day, status) FROM stdin;
\.


--
-- TOC entry 4237 (class 0 OID 16972)
-- Dependencies: 227
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.products (product_id, product_name, description, category_id, dimensions, weight, load_capacity, unit_cost, selling_price, production_time_days, active_flag, production_line_id) FROM stdin;
\.


--
-- TOC entry 4240 (class 0 OID 17029)
-- Dependencies: 230
-- Data for Name: products_inventory; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.products_inventory (inventory_id, warehouse_id, product_id, quantity_on_hand, reorder_level, last_updated) FROM stdin;
\.


--
-- TOC entry 4245 (class 0 OID 17126)
-- Dependencies: 235
-- Data for Name: purchase_order_items; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.purchase_order_items (purchase_order_item_id, purchase_order_id, material_id, quantity, unit_cost, line_total, quantity_received) FROM stdin;
\.


--
-- TOC entry 4244 (class 0 OID 17109)
-- Dependencies: 234
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.purchase_orders (purchase_order_id, supplier_id, order_date, expected_date, status, total_cost) FROM stdin;
\.


--
-- TOC entry 4250 (class 0 OID 17249)
-- Dependencies: 240
-- Data for Name: quality_inspections; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.quality_inspections (inspection_id, product_id, factory_id, production_line_id, inspection_date, inspector_employee_id, result, defect_count) FROM stdin;
\.


--
-- TOC entry 4239 (class 0 OID 17013)
-- Dependencies: 229
-- Data for Name: raw_materials; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.raw_materials (material_id, material_name, material_type, unit_cost, unit_of_measure, supplier_id, dimensions) FROM stdin;
\.


--
-- TOC entry 4252 (class 0 OID 17345)
-- Dependencies: 242
-- Data for Name: raw_materials_inventory; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.raw_materials_inventory (materials_inventory_id, material_id, factory_id, quantity_on_hand, reorder_level, last_updated) FROM stdin;
\.


--
-- TOC entry 4251 (class 0 OID 17284)
-- Dependencies: 241
-- Data for Name: returns; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.returns (return_id, sales_order_id, customer_id, product_id, quantity, return_date, reason, condition, status, resolution, refund_amount, restocked, warehouse_id, handled_by_employee_id, notes) FROM stdin;
\.


--
-- TOC entry 4247 (class 0 OID 17175)
-- Dependencies: 237
-- Data for Name: sales_order_items; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.sales_order_items (sales_order_item_id, sales_order_id, product_id, quantity, unit_price, line_total) FROM stdin;
\.


--
-- TOC entry 4246 (class 0 OID 17150)
-- Dependencies: 236
-- Data for Name: sales_orders; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.sales_orders (sales_order_id, customer_id, order_date, status, total_amount, warehouse_id, shipping_address) FROM stdin;
\.


--
-- TOC entry 4248 (class 0 OID 17199)
-- Dependencies: 238
-- Data for Name: shipments; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.shipments (shipment_id, sales_order_id, warehouse_id, ship_date, delivery_date, carrier, tracking_number, status) FROM stdin;
\.


--
-- TOC entry 4230 (class 0 OID 16852)
-- Dependencies: 220
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.suppliers (supplier_id, supplier_name, contact_name, phone, email, street, city, state, lead_time_days, rating, zipcode) FROM stdin;
1	Chang-Fisher	Jonathan Dixon	\N	jonathan.dixon@chang-fisher.com	7593 Juan Throughway Apt. 948	Phoenix	AZ	7	7.5	85924     
2	Blair Ltd	Mark Castro	\N	mark.castro@blairltd.com	5938 Ramos Pike Suite 080	Dallas	TX	3	9.0	75160     
3	Snyder, Dillon and Sanchez	Mark Harrell	\N	mark.harrell@snyderdillonandsanchez.com	332 Davis Island	Atlanta	GA	5	8.5	30871     
4	Arnold-Mann	Amy Olsen	\N	amy.olsen@arnold-mann.com	894 Davis Union	Atlanta	GA	3	8.5	30659     
5	Roberts and Sons	Lori Johnson	\N	lori.johnson@robertsandsons.com	1122 Megan Squares Suite 848	Atlanta	GA	7	6.0	30339     
6	Riley-Hayes	Donna Davies	\N	donna.davies@riley-hayes.com	59179 Bruce Gardens Apt. 413	Phoenix	AZ	5	7.5	85525     
7	Cabrera-Garcia	Dustin Wolfe	\N	dustin.wolfe@cabrera-garcia.com	891 David Field	Atlanta	GA	3	9.0	30991     
8	Davis-Bass	Darren Jacobs	\N	darren.jacobs@davis-bass.com	17300 Oliver Village	Atlanta	GA	5	8.5	30413     
9	Lucas LLC	Ryan Brown	\N	ryan.brown@lucasllc.com	91634 Strong Mountains Apt. 302	Dallas	TX	2	10.0	75258     
10	Wilson-Morse	Elizabeth Smith	\N	elizabeth.smith@wilson-morse.com	845 Monroe Glen Apt. 807	Dallas	TX	5	8.0	75150     
\.


--
-- TOC entry 4233 (class 0 OID 16884)
-- Dependencies: 223
-- Data for Name: warehouses; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.warehouses (warehouse_id, warehouse_name, city, state, storage_capacity_units, manager_employee_id) FROM stdin;
\.


--
-- TOC entry 4249 (class 0 OID 17219)
-- Dependencies: 239
-- Data for Name: work_orders; Type: TABLE DATA; Schema: public; Owner: lauradev
--

COPY public.work_orders (work_order_id, factory_id, production_line_id, product_id, quantity, start_date, due_date, status, priority) FROM stdin;
\.


--
-- TOC entry 4281 (class 0 OID 0)
-- Dependencies: 243
-- Name: customers_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.customers_customer_id_seq', 1, false);


--
-- TOC entry 4282 (class 0 OID 0)
-- Dependencies: 244
-- Name: employees_employee_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.employees_employee_id_seq', 1, false);


--
-- TOC entry 4283 (class 0 OID 0)
-- Dependencies: 245
-- Name: inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.inventory_inventory_id_seq', 1, false);


--
-- TOC entry 4284 (class 0 OID 0)
-- Dependencies: 246
-- Name: machine_downtime_downtime_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.machine_downtime_downtime_id_seq', 1, false);


--
-- TOC entry 4285 (class 0 OID 0)
-- Dependencies: 247
-- Name: machines_machine_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.machines_machine_id_seq', 1, false);


--
-- TOC entry 4286 (class 0 OID 0)
-- Dependencies: 248
-- Name: maintenance_logs_maintenance_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.maintenance_logs_maintenance_log_id_seq', 1, false);


--
-- TOC entry 4287 (class 0 OID 0)
-- Dependencies: 249
-- Name: maintenance_plans_maintenance_plan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.maintenance_plans_maintenance_plan_id_seq', 1, false);


--
-- TOC entry 4288 (class 0 OID 0)
-- Dependencies: 251
-- Name: materials_inventory_materials_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.materials_inventory_materials_inventory_id_seq', 1, false);


--
-- TOC entry 4289 (class 0 OID 0)
-- Dependencies: 250
-- Name: materials_material_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.materials_material_id_seq', 1, false);


--
-- TOC entry 4290 (class 0 OID 0)
-- Dependencies: 252
-- Name: product_categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.product_categories_category_id_seq', 1, false);


--
-- TOC entry 4291 (class 0 OID 0)
-- Dependencies: 253
-- Name: production_lines_production_line_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.production_lines_production_line_id_seq', 1, false);


--
-- TOC entry 4292 (class 0 OID 0)
-- Dependencies: 254
-- Name: products_product_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.products_product_id_seq', 1, false);


--
-- TOC entry 4293 (class 0 OID 0)
-- Dependencies: 255
-- Name: purchase_order_items_purchase_order_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.purchase_order_items_purchase_order_item_id_seq', 1, false);


--
-- TOC entry 4294 (class 0 OID 0)
-- Dependencies: 256
-- Name: purchase_orders_purchase_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.purchase_orders_purchase_order_id_seq', 1, false);


--
-- TOC entry 4295 (class 0 OID 0)
-- Dependencies: 257
-- Name: quality_inspections_inspection_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.quality_inspections_inspection_id_seq', 1, false);


--
-- TOC entry 4296 (class 0 OID 0)
-- Dependencies: 258
-- Name: returns_return_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.returns_return_id_seq', 1, false);


--
-- TOC entry 4297 (class 0 OID 0)
-- Dependencies: 259
-- Name: sales_order_items_sales_order_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.sales_order_items_sales_order_item_id_seq', 1, false);


--
-- TOC entry 4298 (class 0 OID 0)
-- Dependencies: 260
-- Name: sales_orders_sales_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.sales_orders_sales_order_id_seq', 1, false);


--
-- TOC entry 4299 (class 0 OID 0)
-- Dependencies: 261
-- Name: shipments_shipment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.shipments_shipment_id_seq', 1, false);


--
-- TOC entry 4300 (class 0 OID 0)
-- Dependencies: 262
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.suppliers_supplier_id_seq', 10, true);


--
-- TOC entry 4301 (class 0 OID 0)
-- Dependencies: 263
-- Name: work_orders_work_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: lauradev
--

SELECT pg_catalog.setval('public.work_orders_work_order_id_seq', 1, false);


--
-- TOC entry 3937 (class 2606 OID 17342)
-- Name: maintenance_logs chk_cost_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_logs
    ADD CONSTRAINT chk_cost_non_negative CHECK ((cost >= (0)::numeric)) NOT VALID;


--
-- TOC entry 3938 (class 2606 OID 17341)
-- Name: maintenance_logs chk_downtime_hours_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_logs
    ADD CONSTRAINT chk_downtime_hours_non_negative CHECK ((downtime_hours >= (0)::numeric)) NOT VALID;


--
-- TOC entry 3939 (class 2606 OID 17344)
-- Name: maintenance_plans chk_estimated_duration_hours_non_zero; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_plans
    ADD CONSTRAINT chk_estimated_duration_hours_non_zero CHECK ((estimated_duration_hours > (0)::numeric)) NOT VALID;


--
-- TOC entry 3940 (class 2606 OID 17343)
-- Name: maintenance_plans chk_frequency_days_non_zero; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.maintenance_plans
    ADD CONSTRAINT chk_frequency_days_non_zero CHECK ((frequency_days > 0)) NOT VALID;


--
-- TOC entry 3930 (class 2606 OID 17339)
-- Name: machines chk_hourly_rate_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.machines
    ADD CONSTRAINT chk_hourly_rate_non_negative CHECK ((hourly_rate >= (0)::numeric)) NOT VALID;


--
-- TOC entry 3943 (class 2606 OID 17338)
-- Name: machine_downtime chk_impact_hours_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.machine_downtime
    ADD CONSTRAINT chk_impact_hours_non_negative CHECK ((impact_hours >= (0)::numeric)) NOT VALID;


--
-- TOC entry 3935 (class 2606 OID 17336)
-- Name: products_inventory chk_inventory_quantity_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.products_inventory
    ADD CONSTRAINT chk_inventory_quantity_non_negative CHECK ((quantity_on_hand >= 0)) NOT VALID;


--
-- TOC entry 3932 (class 2606 OID 17340)
-- Name: machines chk_maintenance_cycle_days_non_zero; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.machines
    ADD CONSTRAINT chk_maintenance_cycle_days_non_zero CHECK ((maintenance_cycle_days > 0)) NOT VALID;


--
-- TOC entry 3936 (class 2606 OID 17337)
-- Name: products_inventory chk_reorder_level_non_negative; Type: CHECK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE public.products_inventory
    ADD CONSTRAINT chk_reorder_level_non_negative CHECK ((reorder_level >= 0)) NOT VALID;


--
-- TOC entry 3975 (class 2606 OID 17333)
-- Name: customers customers_email_key; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_email_key UNIQUE (email);


--
-- TOC entry 3977 (class 2606 OID 17527)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 3987 (class 2606 OID 16914)
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (department_id);


--
-- TOC entry 3983 (class 2606 OID 17335)
-- Name: employees employees_email_key; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_email_key UNIQUE (email);


--
-- TOC entry 3985 (class 2606 OID 17537)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);


--
-- TOC entry 3979 (class 2606 OID 16883)
-- Name: factories factories_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.factories
    ADD CONSTRAINT factories_pkey PRIMARY KEY (factory_id);


--
-- TOC entry 3997 (class 2606 OID 17560)
-- Name: products_inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products_inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (inventory_id);


--
-- TOC entry 4003 (class 2606 OID 17572)
-- Name: machine_downtime machine_downtime_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.machine_downtime
    ADD CONSTRAINT machine_downtime_pkey PRIMARY KEY (downtime_id);


--
-- TOC entry 3993 (class 2606 OID 17588)
-- Name: machines machines_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT machines_pkey PRIMARY KEY (machine_id);


--
-- TOC entry 3999 (class 2606 OID 17600)
-- Name: maintenance_logs maintenance_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_logs
    ADD CONSTRAINT maintenance_logs_pkey PRIMARY KEY (maintenance_log_id);


--
-- TOC entry 4001 (class 2606 OID 17623)
-- Name: maintenance_plans maintenance_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT maintenance_plans_pkey PRIMARY KEY (maintenance_plan_id);


--
-- TOC entry 4021 (class 2606 OID 18111)
-- Name: raw_materials_inventory materials_inventory_material_factory_key; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials_inventory
    ADD CONSTRAINT materials_inventory_material_factory_key UNIQUE (material_id, factory_id);


--
-- TOC entry 4023 (class 2606 OID 17652)
-- Name: raw_materials_inventory materials_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials_inventory
    ADD CONSTRAINT materials_inventory_pkey PRIMARY KEY (materials_inventory_id);


--
-- TOC entry 3995 (class 2606 OID 17640)
-- Name: raw_materials materials_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials
    ADD CONSTRAINT materials_pkey PRIMARY KEY (material_id);


--
-- TOC entry 3971 (class 2606 OID 17664)
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 3989 (class 2606 OID 17673)
-- Name: production_lines production_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT production_lines_pkey PRIMARY KEY (production_line_id);


--
-- TOC entry 3991 (class 2606 OID 17680)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- TOC entry 4007 (class 2606 OID 17702)
-- Name: purchase_order_items purchase_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_pkey PRIMARY KEY (purchase_order_item_id);


--
-- TOC entry 4005 (class 2606 OID 17719)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (purchase_order_id);


--
-- TOC entry 4017 (class 2606 OID 17731)
-- Name: quality_inspections quality_inspections_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.quality_inspections
    ADD CONSTRAINT quality_inspections_pkey PRIMARY KEY (inspection_id);


--
-- TOC entry 4019 (class 2606 OID 17753)
-- Name: returns returns_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_pkey PRIMARY KEY (return_id);


--
-- TOC entry 4011 (class 2606 OID 17789)
-- Name: sales_order_items sales_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_order_items
    ADD CONSTRAINT sales_order_items_pkey PRIMARY KEY (sales_order_item_id);


--
-- TOC entry 4009 (class 2606 OID 17806)
-- Name: sales_orders sales_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_pkey PRIMARY KEY (sales_order_id);


--
-- TOC entry 4013 (class 2606 OID 17822)
-- Name: shipments shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_pkey PRIMARY KEY (shipment_id);


--
-- TOC entry 3973 (class 2606 OID 17834)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (supplier_id);


--
-- TOC entry 3981 (class 2606 OID 16893)
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_pkey PRIMARY KEY (warehouse_id);


--
-- TOC entry 4015 (class 2606 OID 17843)
-- Name: work_orders work_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_pkey PRIMARY KEY (work_order_id);


--
-- TOC entry 4029 (class 2606 OID 16935)
-- Name: departments fk_departments_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_departments_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4030 (class 2606 OID 17880)
-- Name: departments fk_departments_supervisor; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_departments_supervisor FOREIGN KEY (supervisor_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4031 (class 2606 OID 16940)
-- Name: departments fk_departments_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_departments_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4026 (class 2606 OID 16915)
-- Name: employees fk_employees_department; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_employees_department FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- TOC entry 4027 (class 2606 OID 16920)
-- Name: employees fk_employees_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_employees_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4028 (class 2606 OID 16925)
-- Name: employees fk_employees_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_employees_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4024 (class 2606 OID 17885)
-- Name: factories fk_factories_manager; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.factories
    ADD CONSTRAINT fk_factories_manager FOREIGN KEY (manager_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4037 (class 2606 OID 17895)
-- Name: products_inventory fk_inventory_product; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products_inventory
    ADD CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 4038 (class 2606 OID 17043)
-- Name: products_inventory fk_inventory_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products_inventory
    ADD CONSTRAINT fk_inventory_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4043 (class 2606 OID 17900)
-- Name: machine_downtime fk_machine_downtime_machine; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.machine_downtime
    ADD CONSTRAINT fk_machine_downtime_machine FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- TOC entry 4035 (class 2606 OID 17905)
-- Name: machines fk_machines_production_line; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT fk_machines_production_line FOREIGN KEY (production_line_id) REFERENCES public.production_lines(production_line_id);


--
-- TOC entry 4039 (class 2606 OID 17910)
-- Name: maintenance_logs fk_maintenance_logs_machine; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_logs
    ADD CONSTRAINT fk_maintenance_logs_machine FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- TOC entry 4040 (class 2606 OID 17915)
-- Name: maintenance_logs fk_maintenance_logs_technician; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_logs
    ADD CONSTRAINT fk_maintenance_logs_technician FOREIGN KEY (technician_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4041 (class 2606 OID 17920)
-- Name: maintenance_plans fk_maintenance_plans_employee; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_employee FOREIGN KEY (assigned_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4042 (class 2606 OID 17925)
-- Name: maintenance_plans fk_maintenance_plans_machine; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_machine FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- TOC entry 4065 (class 2606 OID 17366)
-- Name: raw_materials_inventory fk_mat_inv_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials_inventory
    ADD CONSTRAINT fk_mat_inv_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4066 (class 2606 OID 17935)
-- Name: raw_materials_inventory fk_mat_inv_material; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials_inventory
    ADD CONSTRAINT fk_mat_inv_material FOREIGN KEY (material_id) REFERENCES public.raw_materials(material_id);


--
-- TOC entry 4036 (class 2606 OID 17930)
-- Name: raw_materials fk_materials_supplier; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.raw_materials
    ADD CONSTRAINT fk_materials_supplier FOREIGN KEY (supplier_id) REFERENCES public.suppliers(supplier_id);


--
-- TOC entry 4032 (class 2606 OID 16967)
-- Name: production_lines fk_production_lines_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT fk_production_lines_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4033 (class 2606 OID 17940)
-- Name: products fk_products_category; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES public.product_categories(category_id);


--
-- TOC entry 4034 (class 2606 OID 17945)
-- Name: products fk_products_production_line; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_production_line FOREIGN KEY (production_line_id) REFERENCES public.production_lines(production_line_id);


--
-- TOC entry 4045 (class 2606 OID 17950)
-- Name: purchase_order_items fk_purchase_order_items_material; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT fk_purchase_order_items_material FOREIGN KEY (material_id) REFERENCES public.raw_materials(material_id);


--
-- TOC entry 4046 (class 2606 OID 17955)
-- Name: purchase_order_items fk_purchase_order_items_order; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT fk_purchase_order_items_order FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(purchase_order_id);


--
-- TOC entry 4044 (class 2606 OID 17960)
-- Name: purchase_orders fk_purchase_orders_supplier; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_purchase_orders_supplier FOREIGN KEY (supplier_id) REFERENCES public.suppliers(supplier_id);


--
-- TOC entry 4056 (class 2606 OID 17268)
-- Name: quality_inspections fk_quality_inspections_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.quality_inspections
    ADD CONSTRAINT fk_quality_inspections_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4057 (class 2606 OID 17965)
-- Name: quality_inspections fk_quality_inspections_inspector; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.quality_inspections
    ADD CONSTRAINT fk_quality_inspections_inspector FOREIGN KEY (inspector_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4058 (class 2606 OID 17970)
-- Name: quality_inspections fk_quality_inspections_product; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.quality_inspections
    ADD CONSTRAINT fk_quality_inspections_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 4059 (class 2606 OID 17975)
-- Name: quality_inspections fk_quality_inspections_production_line; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.quality_inspections
    ADD CONSTRAINT fk_quality_inspections_production_line FOREIGN KEY (production_line_id) REFERENCES public.production_lines(production_line_id);


--
-- TOC entry 4060 (class 2606 OID 17980)
-- Name: returns fk_returns_customer; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT fk_returns_customer FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- TOC entry 4061 (class 2606 OID 17985)
-- Name: returns fk_returns_employee; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT fk_returns_employee FOREIGN KEY (handled_by_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4062 (class 2606 OID 17990)
-- Name: returns fk_returns_product; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT fk_returns_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 4063 (class 2606 OID 17995)
-- Name: returns fk_returns_sales_order; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT fk_returns_sales_order FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(sales_order_id);


--
-- TOC entry 4064 (class 2606 OID 17322)
-- Name: returns fk_returns_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT fk_returns_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4049 (class 2606 OID 18000)
-- Name: sales_order_items fk_sales_order_items_order; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_order_items
    ADD CONSTRAINT fk_sales_order_items_order FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(sales_order_id);


--
-- TOC entry 4050 (class 2606 OID 18005)
-- Name: sales_order_items fk_sales_order_items_product; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_order_items
    ADD CONSTRAINT fk_sales_order_items_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 4047 (class 2606 OID 18010)
-- Name: sales_orders fk_sales_orders_customer; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT fk_sales_orders_customer FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- TOC entry 4048 (class 2606 OID 17170)
-- Name: sales_orders fk_sales_orders_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT fk_sales_orders_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4051 (class 2606 OID 18015)
-- Name: shipments fk_shipments_sales_order; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_shipments_sales_order FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(sales_order_id);


--
-- TOC entry 4052 (class 2606 OID 17214)
-- Name: shipments fk_shipments_warehouse; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_shipments_warehouse FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- TOC entry 4025 (class 2606 OID 17890)
-- Name: warehouses fk_warehouses_manager; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT fk_warehouses_manager FOREIGN KEY (manager_employee_id) REFERENCES public.employees(employee_id);


--
-- TOC entry 4053 (class 2606 OID 17234)
-- Name: work_orders fk_work_orders_factory; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_factory FOREIGN KEY (factory_id) REFERENCES public.factories(factory_id);


--
-- TOC entry 4054 (class 2606 OID 18020)
-- Name: work_orders fk_work_orders_product; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 4055 (class 2606 OID 18025)
-- Name: work_orders fk_work_orders_production_line; Type: FK CONSTRAINT; Schema: public; Owner: lauradev
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_production_line FOREIGN KEY (production_line_id) REFERENCES public.production_lines(production_line_id);


-- Completed on 2026-07-21 14:02:30 MST

--
-- PostgreSQL database dump complete
--

\unrestrict Mbo8ivCXIVULvlAYhrVMoVqwogVm0O9RXyHg0n2nOfGEHrj7ViCWPpzUOyghp3N

