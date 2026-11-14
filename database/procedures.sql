-- PROCEDURE: public.place_sales_order(integer, date, character, jsonb, text)

-- DROP PROCEDURE IF EXISTS public.place_sales_order(integer, date, character, jsonb, text);

CREATE OR REPLACE PROCEDURE public.place_sales_order(
	IN p_customer_id integer,
	IN p_order_date date,
	IN p_warehouse_id character,
	IN p_products jsonb,
	IN p_shipping_address text)
LANGUAGE 'plpgsql'
AS $BODY$
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
$BODY$;
ALTER PROCEDURE public.place_sales_order(integer, date, character, jsonb, text)
    OWNER TO lauradev;

---------------------------------

-- PROCEDURE: public.process_return(integer, integer, integer, character varying, boolean, character varying, integer, text)

-- DROP PROCEDURE IF EXISTS public.process_return(integer, integer, integer, character varying, boolean, character varying, integer, text);

CREATE OR REPLACE PROCEDURE public.process_return(
	IN p_sales_order_id integer,
	IN p_product_id integer,
	IN p_quantity integer,
	IN p_reason character varying,
	IN p_restock boolean,
	IN p_condition character varying DEFAULT 'unknown'::character varying,
	IN p_handled_by_employee_id integer DEFAULT NULL::integer,
	IN p_notes text DEFAULT NULL::text)
LANGUAGE 'plpgsql'
AS $BODY$
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
$BODY$;
ALTER PROCEDURE public.process_return(integer, integer, integer, character varying, boolean, character varying, integer, text)
    OWNER TO lauradev;

--------------------

-- PROCEDURE: public.receive_m_purchase_order(integer, character, received_item[])

-- DROP PROCEDURE IF EXISTS public.receive_m_purchase_order(integer, character, received_item[]);

CREATE OR REPLACE PROCEDURE public.receive_m_purchase_order(
	IN p_purchase_order_id integer,
	IN p_factory_id character,
	IN p_received_items received_item[])
LANGUAGE 'plpgsql'
AS $BODY$
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
$BODY$;
ALTER PROCEDURE public.receive_m_purchase_order(integer, character, received_item[])
    OWNER TO lauradev;

