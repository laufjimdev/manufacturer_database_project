-- ===========================================
-- roles.sql
-- Manufacturing Operations Database
-- Creates the cluster-wide roles and their memberships.
--
-- Requires PostgreSQL 16+ (per-membership INHERIT / SET / ADMIN options).
-- Run as a superuser (e.g. lauradev) BEFORE schema.sql.
-- Safe to re-run: existing roles are kept and their attributes re-applied.
--
-- Scope: roles, attributes and memberships ONLY.
-- Table/sequence privileges live in schema.sql
-- Passwords are NOT stored here.
--
-- Not created here: lauradev, the bootstrap superuser. It is the
-- break-glass account and owner of all objects (see README).
-- ===========================================


------------------------------------------------------------
-- 1. GROUP ROLES (NOLOGIN)
-- Privileges are granted to these; people/services join them.
------------------------------------------------------------

DO $$
DECLARE
    group_name text;
BEGIN
    FOREACH group_name IN ARRAY ARRAY[
        'dba',
        'production_manager',
        'maintenance_manager',
        'read_only_auditor',
        'sales_analyst',
        'warehouse_staff'
    ]
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = group_name) THEN
            EXECUTE format('CREATE ROLE %I', group_name);
        END IF;

        -- Baseline attributes: no login, no elevated powers.
        EXECUTE format(
            'ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT',
            group_name
        );
    END LOOP;
END
$$;

-- Only dba gets role-management and database-creation attributes.
-- NOTE: attributes are NOT inherited through membership. Members of dba
-- do not get CREATEDB automatically; they must SET ROLE dba to use it.
ALTER ROLE dba CREATEROLE CREATEDB;

-- Built-in monitoring roles (predefined by PostgreSQL).
GRANT pg_monitor TO dba WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT pg_read_all_settings TO read_only_auditor WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;


------------------------------------------------------------
-- 2. LOGIN ROLES
-- Naming convention: <group>_<n>
------------------------------------------------------------

-- 2a. DBA account(s)
-- CREATEROLE is set directly on the user (attributes are not inherited)
-- so daily admin can onboard users without stepping up. Under PG16+,
-- CREATEROLE can only manage roles this user created or administers.
-- NOCREATEDB: creating a database requires SET ROLE dba on purpose.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dba_1') THEN
        CREATE ROLE dba_1;
    END IF;
END
$$;
ALTER ROLE dba_1 LOGIN NOSUPERUSER NOCREATEDB CREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;

-- 2b. Business users: how many accounts per group.
-- maintenance_manager has no login accounts yet.
-- Regular users get no role-management or database-creation attributes.
DO $$
DECLARE
    rec record;
    i integer;
    user_name text;
BEGIN
    FOR rec IN
        SELECT * FROM (VALUES
            ('production_manager', 2),
            ('maintenance_manager', 3),
            ('read_only_auditor',  1),
            ('sales_analyst',      3),
            ('warehouse_staff',    16)
        ) AS t(group_name, account_count)
    LOOP
        FOR i IN 1..rec.account_count LOOP
            user_name := format('%s_%s', rec.group_name, i);

            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = user_name) THEN
                EXECUTE format('CREATE ROLE %I', user_name);
            END IF;

            EXECUTE format(
                'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT',
                user_name
            );
        END LOOP;
    END LOOP;
END
$$;


------------------------------------------------------------
-- 3. MEMBERSHIPS
-- INHERIT TRUE : member uses the group's privileges directly.
-- SET FALSE    : member cannot SET ROLE to the group (privileges only).
-- ADMIN FALSE  : member cannot add/remove other members.
------------------------------------------------------------

-- dba_1 keeps SET TRUE so it can deliberately step up (SET ROLE dba)
-- to use CREATEDB when a new database is genuinely needed.
GRANT dba TO dba_1 WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;

DO $$
DECLARE
    rec record;
    i integer;
    user_name text;
BEGIN
    FOR rec IN
        SELECT * FROM (VALUES
            ('production_manager', 2),
            ('maintenance_manager', 3),
            ('read_only_auditor',  1),
            ('sales_analyst',      3),
            ('warehouse_staff',    16)
        ) AS t(group_name, account_count)
    LOOP
        FOR i IN 1..rec.account_count LOOP
            user_name := format('%s_%s', rec.group_name, i);

            EXECUTE format(
                'GRANT %I TO %I WITH INHERIT TRUE, SET FALSE, ADMIN FALSE',
                rec.group_name, user_name
            );
        END LOOP;
    END LOOP;
END
$$;


------------------------------------------------------------
-- 4. ROLE COMMENTS
------------------------------------------------------------

COMMENT ON ROLE dba                 IS 'Group: database administration. CREATEROLE + CREATEDB (not inherited by members).';
COMMENT ON ROLE production_manager  IS 'Group: plans and tracks work orders; read access to production data.';
COMMENT ON ROLE maintenance_manager IS 'Group: machine maintenance plans, logs and downtime.';
COMMENT ON ROLE read_only_auditor   IS 'Group: SELECT-only access for audit and review.';
COMMENT ON ROLE sales_analyst       IS 'Group: sales, inventory and returns analysis; limited customer columns.';
COMMENT ON ROLE warehouse_staff     IS 'Group: shipments, transfers and returns handling.';
COMMENT ON ROLE dba_1               IS 'Daily admin login. Member of dba (SET allowed to step up for CREATEDB).';