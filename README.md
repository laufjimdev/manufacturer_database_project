# Manufacturer Database Project

## Overview

This project is a comprehensive relational database for a fictional
furniture manufacturing company. It was built as a hands-on learning
project to reinforce database design, SQL development, PostgreSQL
administration, data engineering concepts, and manufacturing data
modeling.

Rather than being a tutorial or a collection of isolated exercises, this
repository represents an end-to-end project that continues to evolve as
I learn new technologies and best practices.

## Why I Built This Project

After transitioning into Data Engineering from an Industrial Engineering
background, I wanted a project that would demonstrate practical skills
beyond coursework and certificates.

The primary objectives are to:

- Showcase newly acquired technical skills through a realistic
  business project.
- Apply database theory to a complete manufacturing system.
- Practice PostgreSQL administration and database design.
- Build experience with ETL pipelines, automation, and data
  engineering workflows.
- Demonstrate continuous learning through iterative improvements.
- Help compensate for limited professional Data Engineering experience
  by providing recruiters with a substantial portfolio project.

This repository reflects how I approach learning: by designing,
implementing, testing, and improving a system that resembles a
real-world production environment.

## Current Scope

The project includes entities such as:

- Factories
- Warehouses
- Production lines
- Employees and departments
- Products
- Bills of Materials (BOM)
- Raw materials
- Suppliers
- Purchase orders
- Inventory
- Work orders
- Quality inspections
- Machine maintenance
- Sales orders
- Shipments
- Customer returns

Synthetic datasets are generated to simulate realistic manufacturing
operations and support querying, optimization, and analytics.

## Technologies

- PostgreSQL
- SQL
- Python
- Airflow (work in progress)
- Git & GitHub

## Goals

This project is intended to demonstrate my ability to:

- Design normalized relational databases
- Model complex business processes
- Write maintainable SQL
- Generate and manage realistic datasets
- Build automated data workflows
- Think critically about database architecture
- Continuously improve an evolving technical project

Future updates will include additional automation, ETL pipelines,
orchestration, analytics, performance optimization, and documentation.

## Security & Access Control

Access is managed with PostgreSQL roles. Privileges are granted to **group roles** (`NOLOGIN`), and individual **login roles** get them through membership. Nobody is granted table privileges directly, so onboarding a new user is a single `GRANT`.

### Group roles

| Group                 | Login | Superuser | Create roles | Create databases | Purpose                                             |
| --------------------- | ----- | --------- | ------------ | ---------------- | --------------------------------------------------- |
| `dba`                 | no    | no        | yes          | yes              | Database administration                             |
| `production_manager`  | no    | no        | no           | no               | Plans and tracks work orders                        |
| `maintenance_manager` | no    | no        | no           | no               | Maintains machines and logs maintenance             |
| `read_only_auditor`   | no    | no        | no           | no               | Read-only access for audit and review               |
| `sales_analyst`       | no    | no        | no           | no               | Sales, inventory and returns analysis               |
| `warehouse_staff`     | no    | no        | no           | no               | Warehouse operations: shipments, transfers, returns |

### Login roles

| Login role             | Member of group      |
| ---------------------- | -------------------- |
| `dba_n`                | `dba`                |
| `production_manager_n` | `production_manager` |
| `read_only_auditor_n`  | `read_only_auditor`  |
| `sales_analyst_n`      | `sales_analyst`      |
| `warehouse_staff_n`    | `warehouse_staff`    |

`n` is the sequence number of the account (e.g. `warehouse_staff_1` to `warehouse_staff_16`).

Regular users are granted membership with `INHERIT TRUE, SET FALSE, ADMIN FALSE`. They use the group's privileges directly but cannot `SET ROLE` to the group or manage its membership.

### Access by group

| Group                 | Access                                                                                                                                                                                                                                                                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dba`                 | `ALL` on every table and sequence in `public`, plus `CREATE` on the schema                                                                                                                                                                                                                                                                  |
| `production_manager`  | Read access to production, inventory, BOM and product tables; can create work orders and update their scheduling and status columns                                                                                                                                                                                                         |
| `maintenance_manager` | Read access to factories, lines and machines; read/write on maintenance plans, maintenance logs and machine downtime; can update machine status                                                                                                                                                                                             |
| `read_only_auditor`   | `SELECT` on all tables and views, including future ones created by the owner                                                                                                                                                                                                                                                                |
| `sales_analyst`       | Read access to sales, shipments, returns, products and inventory; customer data limited to ID, name, city, state and zipcode (no email, phone or street address)                                                                                                                                                                            |
| `warehouse_staff`     | Read access to orders, inventory, transfers and shipments; can insert shipments, returns and inventory transactions; column-level `UPDATE` limited to fulfilment fields (transfer status and received date, shipment tracking and status, return handling fields); customer data limited to ID and name; no access to product cost or price |

### Design decisions

- **Column-level privileges.** Sensitive columns (customer contact details, product cost and price) are hidden from groups that don't need them, and update rights are restricted to the specific columns each role works on.
- **Role attributes are not inherited.** `CREATEROLE` and `CREATEDB` belong to `dba` and are not passed down through membership. `dba_n` accounts receive `CREATEROLE` directly so they can onboard users; creating databases requires `SET ROLE dba`, so it is a deliberate step up.
- **Least privilege for regular users.** Application and business users have no `CREATEROLE`, `CREATEDB` or `SET` on their group.
- **Owner as break-glass account.** `lauradev` is the superuser and owns all objects. It is intended for emergencies and setup, not daily work. Future tables get the right grants through `ALTER DEFAULT PRIVILEGES`.

### Setup order

1. `roles.sql`: create roles and memberships
2. `schema.sql`: create tables, then apply grants
3. Run the `seed_manufacturer_dag` and `simulate_manufacturing_cycle` DAGs

## Note to Recruiters

This repository represents an ongoing learning project rather than a
finished product.

Every new technology I study is incorporated into this database where
appropriate, allowing me to practice industry concepts in a realistic
environment. The commit history reflects continuous development,
experimentation, refactoring, and incremental improvements.

My objective is not simply to complete a project, but to demonstrate
curiosity, disciplined learning, and the ability to translate new
technical concepts into practical implementations.
