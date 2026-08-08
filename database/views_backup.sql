--
-- PostgreSQL database dump
--

\restrict Q2Gxp95e9yy3OXXCTxkEeaSfLb6NXVqgujYgrdqa9nSJpzPbGLqgjvuh6MXkjI2

-- Dumped from database version 18.4 (Homebrew)
-- Dumped by pg_dump version 18.4

-- Started on 2026-08-08 12:10:16 MST

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
-- TOC entry 278 (class 1259 OID 18795)
-- Name: employee_directory; Type: VIEW; Schema: public; Owner: lauradev
--

CREATE VIEW public.employee_directory AS
 SELECT e.employee_id,
    (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS full_name,
    e.email,
    e.phone,
    e.hire_date,
    e.employment_status,
    d.department_name,
    COALESCE(f.factory_name, w.warehouse_name) AS location
   FROM (((public.employees e
     LEFT JOIN public.departments d ON (((e.department_id)::text = (d.department_id)::text)))
     LEFT JOIN public.factories f ON ((e.factory_id = f.factory_id)))
     LEFT JOIN public.warehouses w ON ((e.warehouse_id = w.warehouse_id)))
  WHERE ((e.employment_status)::text = 'active'::text)
  ORDER BY e.last_name, e.first_name;


ALTER VIEW public.employee_directory OWNER TO lauradev;

--
-- TOC entry 265 (class 1259 OID 18042)
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
-- TOC entry 266 (class 1259 OID 18047)
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
-- TOC entry 267 (class 1259 OID 18052)
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
-- TOC entry 268 (class 1259 OID 18057)
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
-- TOC entry 269 (class 1259 OID 18062)
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
-- TOC entry 270 (class 1259 OID 18072)
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
-- TOC entry 271 (class 1259 OID 18077)
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
-- TOC entry 272 (class 1259 OID 18082)
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
-- TOC entry 273 (class 1259 OID 18087)
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
-- TOC entry 274 (class 1259 OID 18092)
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
-- TOC entry 275 (class 1259 OID 18097)
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

-- Completed on 2026-08-08 12:10:16 MST

--
-- PostgreSQL database dump complete
--

\unrestrict Q2Gxp95e9yy3OXXCTxkEeaSfLb6NXVqgujYgrdqa9nSJpzPbGLqgjvuh6MXkjI2

