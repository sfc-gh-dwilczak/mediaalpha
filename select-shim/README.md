# SELECT Routing Shim

A Perl-based query routing shim that directs `SELECT` statements to either **MySQL** (recent data) or **Snowflake** (archived data) based on the `created_at` date range in the query.

```
Your App (SQL query)
        |
     Shim (Perl DBI wrapper + web UI)
        |
   +-----------+-----------+
   |                       |
MySQL (core)         Snowflake (archive)
```

## How It Works

The shim computes a **cutoff date** (today minus `ROUTE_DAYS`, default 365 days). When you submit a query:

- If the `BETWEEN` start date is **on or after** the cutoff &rarr; routes to **MySQL**
- If the start date is **before** the cutoff &rarr; routes to **Snowflake**

Queries must contain a `created_at BETWEEN 'YYYY-MM-DD' AND 'YYYY-MM-DD'` clause. Only `SELECT` statements are supported.

## Project Structure

```
select-shim/
  docker-compose.yml     # MySQL + shim services
  mysql/
    init.sql             # Sample MySQL schema and data
  perl/
    Dockerfile           # Perl 5.38 + ODBC drivers + dependencies
    cpanfile             # Perl module dependencies
    shim.pl              # Web app (Mojolicious::Lite)
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (with Rosetta enabled on Apple Silicon)
- A Snowflake account with ODBC connectivity

## Snowflake Setup

Run the following in a Snowflake worksheet to create the archive table:

```sql
CREATE DATABASE IF NOT EXISTS ARCHIVEDB;
CREATE SCHEMA IF NOT EXISTS ARCHIVEDB.PUBLIC;

CREATE TABLE IF NOT EXISTS ARCHIVEDB.PUBLIC.orders (
  id INTEGER,
  created_at DATE,
  customer STRING,
  amount NUMBER(10,2)
);

INSERT INTO ARCHIVEDB.PUBLIC.orders VALUES
(1001, '2024-01-01', 'carol', 300.00),
(1002, '2023-06-01', 'dave', 400.00);
```

## Configuration

Edit the environment variables in `docker-compose.yml` under the `shim` service:

| Variable | Description |
|----------|-------------|
| `CORE_DSN` | DBI connection string for MySQL (pre-configured for the Docker MySQL container) |
| `CORE_USER` | MySQL username |
| `CORE_PASS` | MySQL password |
| `SF_DSN` | ODBC connection string for Snowflake (DSN-less, uses full driver path) |
| `SF_USER` | Snowflake username |
| `SF_PASS` | Snowflake password or token |
| `ROUTE_DAYS` | Number of days back from today that defines the cutoff (default: `365`) |

### Snowflake DSN Format

The `SF_DSN` uses a DSN-less connection string pointing directly to the Snowflake ODBC driver installed in the container:

```
Driver=/usr/lib/snowflake/odbc/lib/libSnowflake.so;Server=<account>.snowflakecomputing.com;Database=ARCHIVEDB;Schema=PUBLIC
```

Replace `<account>` with your Snowflake account identifier.

## Running

```bash
cd select-shim
docker compose up --build
```

Then open **http://localhost:3000** in your browser.

The web UI shows the current cutoff date and provides a text area to paste queries. Results are displayed in a table with a badge indicating which database handled the query.

## Example Queries

Route to **MySQL** (recent data, start date >= cutoff):

```sql
SELECT id, created_at, customer, amount
FROM orders
WHERE created_at BETWEEN '2025-07-01' AND '2026-03-01';
```

Route to **Snowflake** (archived data, start date < cutoff):

```sql
SELECT id, created_at, customer, amount
FROM orders
WHERE created_at BETWEEN '2023-01-01' AND '2024-12-31';
```

## Stopping

```bash
docker compose down
```

## Notes

- The shim container runs as `linux/amd64` because the Snowflake ODBC driver is only distributed for x86_64. On Apple Silicon Macs this uses Rosetta emulation.
- MySQL connection has a retry loop (up to 30 attempts, 2 seconds apart) to handle startup race conditions.
- The MySQL sample data includes two rows: alice (2026-01-01) and bob (2025-07-01). The Snowflake sample data includes carol (2024-01-01) and dave (2023-06-01).
