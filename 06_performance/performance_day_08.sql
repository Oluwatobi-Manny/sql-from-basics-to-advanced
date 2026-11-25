/*
DAY 8: DATABASE INDEXING AND QUERY PERFORMANCE

ASSUMPTIONS:
- The practice table orders_big is separate from the original Zuri Market tables.
- customer_id is randomly generated between 1 and 60.
- order_date contains random dates within a one-year period.
- status values are sampled from the actual distinct statuses in the orders table.
- amount is a randomly generated numeric value.
- ANALYZE is run after major data changes so PostgreSQL has updated table statistics.
- Execution times may vary depending on hardware, cache state, PostgreSQL configuration and concurrent activity.
- EXPLAIN ANALYZE actually executes the query, not just estimates its cost.
- Run performance tests multiple times and compare execution times rather than relying on one run.
- For a fair index comparison, use the same dataset and query conditions.
*/

-- PROBLEM 1: Create a table called orders_big containing 1,000,000 rows
DROP TABLE IF EXISTS orders_big;

CREATE TABLE orders_big (
    order_id BIGINT PRIMARY KEY,
    customer_id INTEGER,
    order_date DATE,
    status VARCHAR(30),
    amount NUMERIC(12,2)
);

INSERT INTO orders_big (order_id, customer_id, order_date, status, amount)
SELECT
    gs,
    FLOOR(RANDOM() * 60 + 1)::INT,
    DATE '2025-01-01' + FLOOR(RANDOM() * 365)::INT,
    (ARRAY[
        'returned',
        'pending',
        'shipped',
        'cancelled',
        'delivered'
    ])[FLOOR(RANDOM() * 5 + 1)::INT],
    ROUND((RANDOM() * 5000)::NUMERIC, 2)
FROM generate_series(1, 1000000) AS gs;

ANALYZE VERBOSE orders_big;

-- PROBLEM 2: Test query performance without an index
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE customer_id = 7;

-- QUERY PLAN                                                    
-- Scan type: Sequential scan on orders_big
-- Estimated cost: 15667.03
-- Actual execution time: 69.894 ms
-- Actual number of rows returned: 16967
-- Filter: (customer_id = 7)
-- Rows Removed by Filter: 327780
-- Planning Time: 0.061 ms

-- PROBLEM 3: Create an index and compare performance
CREATE INDEX idx_orders_big_customer_id ON orders_big(customer_id);

ANALYZE VERBOSE orders_big;

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE customer_id = 7;

-- QUERY PLAN                                             
-- Scan type: Bitmap Index scan on idx_orders_big_customer_id
-- Estimated cost: 8184.18
-- Actual execution time: 20.010 ms
-- Actual number of rows returned: 16967
-- Index Cond: (customer_id = 7)
-- Heap Blocks: exact=6880
-- Planning Time: 0.584 ms

-- Adding the index allows PostgreSQL to scan for the customer_id without scanning through all the rows of 
-- the database. The scan type also moved from an sequential scan (scanning all rows one after to the other)
-- to index cond (filtering out on columns with index for the filter).

-- PROBLEM 4: FUNCTION-BASED FILTERING VS DATE RANGE FILTERING
-- Write a query that filters orders by month using a function on order_date.
SELECT 
    order_id,
    order_date,
    DATE_TRUNC('month', order_date) AS month_start,
    status
FROM orders_big
WHERE DATE_TRUNC('month', order_date) = '2025-02-01'
ORDER BY month_start
LIMIT 20;

-- Create an index on order_date.
CREATE INDEX idx_orders_big_order_date ON orders_big(order_date);

EXPLAIN ANALYZE
SELECT 
    order_id,
    order_date,
    DATE_TRUNC('month', order_date) AS month_start,
    status
FROM orders_big
WHERE DATE_TRUNC('month', order_date) = '2025-02-01'
ORDER BY month_start;

-- PostgreSQL uses a parallel sequential scan for the above

-- Rewrite the query using a date range:
EXPLAIN ANALYZE
SELECT
    order_id,
    order_date,
    status
FROM orders_big
WHERE order_date >= '2025-02-01'
    AND order_date < '2025-03-01';

-- PostgreSQL uses a bitmap index scan on the index idx_orders_big_order_date.
-- Execution time in the function based query is about 5X of the date range filter.
-- A normal B-tree index on order_date cannot directly support function expression. Rewriting the expression
-- to date range makes the predicate index-friendly.

-- PROBLEM 5: COMPOSITE INDEXES
-- Create a composite index 
CREATE INDEX idx_orders_big_status_order_date ON orders_big(status, order_date);

ANALYZE VERBOSE orders_big;

-- Test two queries:
-- A. A query filtering on both status and order_date.
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE status = 'delivered'
AND (order_date >= '2025-01-01' AND order_date < '2025-02-01');

-- QUERY PLAN                                             
-- Scan type: Bitmap Index scan on idx_orders_big_status_order_date
-- Estimated cost: 10341.69
-- Actual execution time: 49.791 ms
-- Actual number of rows returned: 68215
-- Index Cond: ((order_date >= '2025-01-01'::date) AND (order_date < '2025-02-01'::date))
-- Heap Blocks: exact=7761
-- Planning Time: 0.186 ms

-- B. A query filtering on order_date only.
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE order_date >= '2025-01-01' 
    AND order_date < '2025-02-01';

-- QUERY PLAN                                             
-- Scan type: Bitmap Index scan on idx_orders_big_order_date
-- Estimated cost: 10139.16
-- Actual execution time: 34.728 ms
-- Actual number of rows returned: 85024
-- Index Cond: ((order_date >= '2025-01-01'::date) AND (order_date < '2025-02-01'::date))
-- Heap Blocks: exact=7761
-- Planning Time: 0.173 ms

-- The leading column matters because a B-tree indexes are organised according to their column order.
-- Queries filtering by status and order_date can benefit from this index. An index beginning with
-- status is generally most useful for queries that constrain status before using the subsequent order_date column.

--PROBLEM 6: INDEX SELECTIVITY
-- Create a separate index on status.
CREATE INDEX idx_orders_big_status ON orders_big(status);

-- Identify the most common status in orders_big
SELECT 
    status,
    COUNT(status) AS status_count
FROM orders_big
GROUP BY status
ORDER BY status_count DESC;

-- The commonest is 'pending'

-- Filter orders_big using 'pending' and run EXPLAIN ANALYZE.
EXPLAIN ANALYZE
SELECT * 
FROM orders_big
WHERE status = 'pending';

-- PostgreSQL chooses an Index Scan on idx_orders_big_status.
-- Planning Time: 0.203 ms
-- Execution Time: 224.076 ms

-- PostgreSQL may still choose a Sequential Scan even when an index exists. If a large percentage of the
-- table matches the condition, scanning the table sequentially may be cheaper than using the index and
-- fetching many individual rows. This is termed selectivity.

-- PROBLEM 7: MEASURE THE COST OF INDEXES
-- Compare the time required to insert 100,000 additional rows into orders_big under two conditions.

-- A. WITH ALL INDEXES
DROP TABLE IF EXISTS extra_orders;

CREATE TEMP TABLE extra_orders AS
SELECT
    gs AS order_id,
    FLOOR(RANDOM() * 60 + 1)::INT AS customer_id,
    DATE '2025-01-01' + FLOOR(RANDOM() * 365)::INT AS order_date,
    (ARRAY[
        'returned',
        'pending',
        'shipped',
        'cancelled',
        'delivered'
    ])[FLOOR(RANDOM() * 5 + 1)::INT] AS status,
    ROUND((RANDOM() * 5000)::NUMERIC, 2) AS amount
FROM generate_series(1000001, 1100000) AS gs;

\timing on

-- Insert 100,000 additional rows.
INSERT INTO orders_big
SELECT * FROM extra_orders;

-- Record the execution time.
-- Time: 4723.779 ms (00:04.724)

-- B. WITH ONLY THE PRIMARY KEY

-- Drop the extra orders.
DELETE FROM orders_big
WHERE order_id > 1000000;

-- Drop the additional indexes.
DROP INDEX IF EXISTS idx_orders_big_customer_id;
DROP INDEX IF EXISTS idx_orders_big_order_date;
DROP INDEX IF EXISTS idx_orders_big_status;
DROP INDEX IF EXISTS idx_orders_big_status_order_date;

-- Reset the orders_big table
DROP TABLE IF EXISTS orders_big;

CREATE TABLE orders_big (
    order_id BIGINT PRIMARY KEY,
    customer_id INTEGER,
    order_date DATE,
    status VARCHAR(30),
    amount NUMERIC(12,2)
);

INSERT INTO orders_big (order_id, customer_id, order_date, status, amount)
SELECT
    gs,
    FLOOR(RANDOM() * 60 + 1)::INT,
    DATE '2025-01-01' + FLOOR(RANDOM() * 365)::INT,
    (ARRAY[
        'returned',
        'pending',
        'shipped',
        'cancelled',
        'delivered'
    ])[FLOOR(RANDOM() * 5 + 1)::INT],
    ROUND((RANDOM() * 5000)::NUMERIC, 2)
FROM generate_series(1, 1000000) AS gs;

-- Insert 100,000 additional rows.
INSERT INTO orders_big
SELECT * FROM extra_orders;

-- Record the execution time.
-- Time: 1114.297 ms (00:01.114)

-- Compare the results.
-- Additional indexes increase write overhead because PostgreSQL must update every
-- affected index whenever new rows are inserted. Fewer indexes can improve insertion,
-- performance but can negatively affect read performance.

-- Compare index sizes
SELECT
    i.indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    pg_size_pretty(pg_relation_size('orders_big')) AS table_size,
    pg_size_pretty(pg_indexes_size('orders_big')) AS all_indexes_size,
    pg_size_pretty(pg_total_relation_size('orders_big')) AS total_size
FROM pg_stat_user_indexes i
WHERE i.relname = 'orders_big'
ORDER BY pg_relation_size(i.indexrelid) DESC;

-- Index size here is at 24mb.

-- Add the indexes and get the index sizes
CREATE INDEX idx_orders_big_customer_id ON orders_big(customer_id);
CREATE INDEX idx_orders_big_order_date ON orders_big(order_date);
CREATE INDEX idx_orders_big_status_order_date ON orders_big(status, order_date);
CREATE INDEX idx_orders_big_status ON orders_big(status);

SELECT
    i.indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    pg_size_pretty(pg_relation_size('orders_big')) AS table_size,
    pg_size_pretty(pg_indexes_size('orders_big')) AS all_indexes_size,
    pg_size_pretty(pg_total_relation_size('orders_big')) AS total_size
FROM pg_stat_user_indexes i
WHERE i.relname = 'orders_big'
ORDER BY pg_relation_size(i.indexrelid) DESC;

-- Index size
/*
orders_big_pkey                  | 24 MB      | 67 MB      | 53 MB            | 120 MB
idx_orders_big_status_order_date | 7904 kB    | 67 MB      | 53 MB            | 120 MB
idx_orders_big_order_date        | 7616 kB    | 67 MB      | 53 MB            | 120 MB
idx_orders_big_status            | 7544 kB    | 67 MB      | 53 MB            | 120 MB
idx_orders_big_customer_id       | 7488 kB    | 67 MB      | 53 MB            | 120 MB
*/

-- Indexes can improve SELECT performance because they let PostgreSQL jump straight to matching rows through 
-- a sorted structure instead of scanning the whole table.
-- Indexes introduce additional INSERT, UPDATE and DELETE work. Every index is a separate structure that must be
-- updated whenever the table's rows change so each write cost more
-- Indexes consume disk space. Each index stores its own copy of the indexed column values plus row pointers on
-- top of the table itself.
-- Creating indexes on every column is not necessarily good practice. Most indexes go unused while slowing every 
-- write and eating disk space.

-- PROBLEM 8: INSPECT EXISTING ZURI MARKET INDEXES
-- Use pg_indexes to list all existing indexes in the Zuri Market schema.
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename NOT IN ('orders_raw', 'orders_big', 'customers_raw')
ORDER BY tablename, indexname;

-- Inspect the foreign key columns in the real tables.
SELECT
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS referenced_table,
    ccu.column_name AS referenced_column,
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.constraint_schema = kcu.constraint_schema
JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
    AND tc.constraint_schema = ccu.constraint_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;

/*
Result:
table_name  |    column_name     | referenced_table | referenced_column |          constraint_name
-------------+--------------------+------------------+-------------------+------------------------------------
categories  | parent_category_id | categories       | category_id       | categories_parent_category_id_fkey
order_items | order_id           | orders           | order_id          | order_items_order_id_fkey
order_items | product_id         | products         | product_id        | order_items_product_id_fkey
orders      | customer_id        | customers        | customer_id       | orders_customer_id_fkey
products    | category_id        | categories       | category_id       | products_category_id_fkey
*/

-- Identify foreign key columns that do not have supporting indexes.
SELECT
    tc.table_name,
    kcu.column_name,
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.constraint_schema = kcu.constraint_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
    AND NOT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t
            ON t.oid = i.indrelid
        JOIN pg_attribute a
            ON a.attrelid = t.oid
            AND a.attnum = i.indkey[0]
        WHERE t.relname = tc.table_name
        AND t.relnamespace = (
            SELECT oid
            FROM pg_namespace
            WHERE nspname = 'public'
        )
        AND a.attname = kcu.column_name
        AND i.indisvalid
    )
ORDER BY tc.table_name, kcu.column_name;
/*
Result

table_name  |    column_name     |          constraint_name
-------------+--------------------+------------------------------------
categories  | parent_category_id | categories_parent_category_id_fkey
order_items | order_id           | order_items_order_id_fkey
order_items | product_id         | order_items_product_id_fkey
orders      | customer_id        | orders_customer_id_fkey
products    | category_id        | products_category_id_fkey

In production, I will look to add indexes to these
1. order_items.order_id: Index to speed up order-item lookups and joins.
2. orders.customer_id: Index to speed up customer order-history queries.
3. order_items.product_id: Index to support product-related lookups and joins.

PostgreSQL automatically indexes primary keys and unique constraints, but it does not automatically create indexes
on the referencing side of foreign keys.
*/

DROP TABLE IF EXISTS orders_big;