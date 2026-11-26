/*
DAY 9: ADVANCED QUERY OPTIMIZATION, COVERING INDEXES,
PAGINATION, ELT AND MATERIALIZED VIEWS

ASSUMPTIONS:
- orders_big initially contains exactly 1,000,000 rows.
- order_id is the primary key.
- customer_id, order_date, status and amount retain the structure from Day 8.
- Indexes on customer_id and order_date are created before running the exercises.
- VACUUM ANALYZE is run after recreating the practice table to update statistics and visibility information.
- For customer comparisons, the real customers table is used.
- The customers table contains a city column, and New York is the target city.
- Cancelled orders are excluded from analytical calculations unless a problem explicitly says otherwise.
- All performance comparisons should use the same dataset and query conditions.
- Run EXPLAIN ANALYZE multiple times and record the actual execution times.
- Execution times may vary depending on caching, hardware and PostgreSQL configuration.
- For pagination, order_id is assumed to be unique and indexed through its primary key.
- The materialized view stores daily revenue and order count by status.
- REFRESH MATERIALIZED VIEW completely rebuilds the materialized view from its underlying query.
*/

-- PROBLEM 1: RECREATE THE PRACTICE TABLE
-- Recreate orders_big with 1,000,000 rows using Day 8 setup.
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

-- Create indexes on customer_id and order_date
CREATE INDEX idx_orders_big_customer_id ON orders_big(customer_id);
CREATE INDEX idx_orders_big_order_date ON orders_big(order_date);

-- Run
VACUUM VERBOSE ANALYZE orders_big;

-- PROBLEM 2: COVERING INDEXES
-- Run the following query before creating a covering index:

EXPLAIN ANALYZE
SELECT customer_id, order_date
FROM orders_big
WHERE customer_id = 7;

-- Record the execution plan

-- Query plan
-- Scan type: Bitmap Index scan on idx_orders_big_customer_id
-- Estimated cost: 8174.11
-- Actual execution time: 31.727 ms
-- Actual number of rows returned: 16609
-- Index Cond: (customer_id = 7)
-- Heap Blocks: exact=6851
-- Planning Time: 0.270 ms

-- Create a composite index on
CREATE INDEX idx_orders_big_customer_id_order_date ON orders_big(customer_id, order_date);

-- Run 
VACUUM VERBOSE ANALYZE orders_big;

-- Execute the same query again.
EXPLAIN ANALYZE
SELECT customer_id, order_date
FROM orders_big
WHERE customer_id = 7;

-- -- Query plan
-- Scan type: Index Only Scan using idx_orders_big_customer_id_order_date
-- Estimated cost: 330.60
-- Actual execution time: 3.052 ms
-- Actual number of rows returned: 16609
-- Index Cond: (customer_id = 7)
-- Heap Fetches: 0
-- Planning Time: 0.252 ms

-- An Index Only Scan is faster than a normal Index Scan because all the columns
-- requested by the query are already stored inside the index itself. Instead of
-- finding matching entries in the index and then jumping back to the main table (heap)
-- to fetch the rest of the row data, PostgreSQL reads directly from the smaller index,
-- drastically reducing disk I/O and memory reads provided the visibility map confirms
-- the pages are all visible.


-- PROBLEM 3: Find all orders belonging to customers whose city is New York.
-- A. Using IN with a subquery
EXPLAIN ANALYZE
SELECT 
    order_id,
    customer_id,
    order_date,
    status,
    amount
FROM orders_big
WHERE customer_id IN (
    SELECT customer_id
    FROM customers
    WHERE city = 'New York'
    )
    AND status IS DISTINCT FROM 'cancelled'
;

-- QUERY PLAN                                             
-- Execution Plans: Hash Join -> Seq Scan on orders_big -> Hash -> Seq Scan on customers
-- Scan types: Seq Scan on orders_big -> Seq Scan on customers
-- Join Strategies: Hash Join
-- Execution time: 355.789 ms
-- Number of rows returned: 66915
-- Planning time: 0.754 ms

-- B. Using EXISTS with a correlated subquery.
EXPLAIN ANALYZE
SELECT 
    order_id,
    customer_id,
    order_date,
    status,
    amount
FROM orders_big o
WHERE EXISTS (
    SELECT 1
    FROM customers c
    WHERE o.customer_id = c.customer_id
        AND c.city = 'New York'
    )
    AND status IS DISTINCT FROM 'cancelled'
;

-- QUERY PLAN                                             
-- Execution Plans: Hash Join -> Seq Scan on orders_big o -> Hash -> Seq Scan on customers c
-- Scan types: Seq Scan on orders_big o -> Seq Scan on customers c
-- Join Strategies: Hash Join
-- Execution time: 325.326 ms
-- Number of rows returned: 66915
-- Planning time: 0.225 ms

-- C. Using a JOIN to the real customers table.
EXPLAIN ANALYZE
SELECT 
    o.order_id,
    o.customer_id,
    o.order_date,
    o.status,
    o.amount
FROM orders_big o
JOIN customers c
    ON o.customer_id = c.customer_id
    AND c.city = 'New York'
WHERE o.status IS DISTINCT FROM 'cancelled'
;

-- QUERY PLAN                                             
-- Execution Plans: Hash Join -> Seq Scan on orders_big o -> Hash -> Seq Scan on customers c
-- Scan types: Seq Scan on orders_big o -> Seq Scan on customers c
-- Join Strategies: Hash Join
-- Execution time: 345.973 ms
-- Number of rows returned: 66915
-- Planning time: 0.410 ms

-- PostgreSQL is smart enough to rewrite IN, EXISTS and JOIN into identical
-- execution plan (Hash Join in this case). Because the query optimizer transforms
-- them into the same underlying logic, their runtime performance and cost are usually
-- identical.

-- For readability, EXISTS is preferred because it explicitly communicates
-- the intent without risking accidental duplicate rows and handles NULL values
-- safely (in NOT EXISTS).

-- PROBLEM 4: Find orders whose amount is greater than the average amount of orders placed by the same customer
-- A. CORRELATED SUBQUERY
EXPLAIN ANALYZE
SELECT 
    o.order_id,
    o.customer_id,
    o.amount
FROM orders_big o
WHERE o.amount > (
        SELECT ROUND(AVG(ob.amount), 2)
        FROM orders_big ob
        WHERE o.customer_id = ob.customer_id
        AND ob.status IS DISTINCT FROM 'cancelled'
    )
    AND o.status IS DISTINCT FROM 'cancelled'
;

-- QUERY PLAN                                             
-- Execution Plans: Seq Scan on orders_big o -> Aggregate -> Bitmap Heap Scan on orders_big ob -> Bitmap Index Scan on idx_orders_big_customer_id_order_date
-- Scan types: Seq Scan on orders_big o -> Bitmap Heap Scan on orders_big ob -> Bitmap Index Scan on idx_orders_big_customer_id_order_date
-- Join Strategies: 
-- Execution time: 
-- Number of rows returned: 
-- Planning time: 

-- B. AGGREGATED CTE
EXPLAIN ANALYZE
WITH avg_orders AS (
    SELECT
        customer_id,
        ROUND(AVG(amount), 2) AS avg_amount
    FROM orders_big
    WHERE status IS DISTINCT FROM 'cancelled'
    GROUP BY customer_id
)
SELECT
    o.order_id,
    o.customer_id,
    a.avg_amount
FROM avg_orders a
JOIN orders_big o
    ON a.customer_id = o.customer_id
WHERE o.amount > a.avg_amount
    AND status IS DISTINCT FROM 'cancelled';

-- Query
-- Execution Plans: Hash Join -> Seq Scan on orders_big o -> Hash -> Subquery Scan on a -> Seq Scan on customers c
-- -> Finalize GroupAggregate -> Gather Merge -> Sort -> Partial HashAggregate ->  Parallel Seq Scan on orders_big
-- Scan types: Seq Scan on orders_big o -> Subquery Scan on a -> Seq Scan on customers c ->  Parallel Seq Scan on orders_big
-- Join Strategies: Hash Join
-- Execution time: 674.236 ms
-- Number of rows returned: 399607
-- Planning time: 0.289 ms

-- C. WINDOW FUNCTION
EXPLAIN ANALYZE
WITH customer_averages AS (
    SELECT
        order_id,
        customer_id,
        amount,
        ROUND(AVG(amount) OVER (PARTITION BY customer_id), 2) AS avg_amount
    FROM orders_big
    WHERE status IS DISTINCT FROM 'cancelled'
)
SELECT
    order_id,
    customer_id,
    amount
FROM customer_averages
WHERE amount > avg_amount
;

-- QUERY PLAN                                 
-- Execution Plans: Subquery Scan on customer_averages -> WindowAgg -> Index Scan using idx_orders_big_customer_id on orders_big
-- Scan types: Subquery Scan on customer_averages -> Index Scan using idx_orders_big_customer_id on orders_big
-- Join Strategies: None 
-- Execution time: 1441.817 ms
-- Number of rows returned: 399607
-- Planning time: 0.228 ms

-- In production, I would prefer the CTE (with the join or window function) over the
-- correlated subquery for large datasets. CTE with the JOIN scans and aggregates once into a compact
-- custom summary and uses a single Hash Join. CTE with window function avoids the join which is very clean
-- especially when sorting a massive dataset. The CTE with window function is the cleanest and most
-- readable.

-- PROBLEM 5: PAGINATION: OFFSET VS KEYSET PAGINATION
-- Retrieve rows 900,001 to 900,020 ordered by order_id.

-- A. OFFSET PAGINATION
EXPLAIN ANALYZE
SELECT
    order_id,
    customer_id,
    status,
    amount
FROM orders_big
ORDER BY order_id
LIMIT 20 
OFFSET 900000
;

-- Execution Time: 314.685 ms

-- B. KEYSET PAGINATION
-- Use the last order_id from the preceding page as the cursor.
EXPLAIN ANALYZE
SELECT
    order_id,
    customer_id,
    status,
    amount
FROM orders_big
WHERE order_id > 900000
ORDER BY order_id
LIMIT 20 
;

-- Execution Time: 0.102 ms

-- PostgreSQL has no way to jump straight to row 900,001 using OFFSET alone. Even with an index,
-- it must count through all 900,000 preceding rows, fetch and then discard them before returning 
-- the 20 requested rows. By filtering with the WHERE clause for the KEYSET pagination. PostgreSQL uses 
-- the B-tree index on order_id to seek directly to the exact entry immediately following the previous
-- page's cursor reading only the needed 20 rows.

-- PROBLEM 6: EXPLAIN ANALYZE WITH BUFFERS
-- Choose one of your slower queries from the previous exercises.

EXPLAIN (ANALYZE, BUFFERS)
WITH customer_averages AS (
    SELECT
        order_id,
        customer_id,
        amount,
        AVG(amount) OVER (PARTITION BY customer_id) AS avg_amount
    FROM orders_big
    WHERE status IS DISTINCT FROM 'cancelled'
)
SELECT
    order_id,
    customer_id,
    amount
FROM customer_averages
WHERE amount > avg_amount
;

-- QUERY PLAN
-- Buffers: shared hit=413477
-- Buffers: shared read=0

-- shared hit: PostgreSQL found the required data in shared buffers.PostgreSQL read 413,477 8kb blocks 
-- directly from in-memory shared_buffers cache. Why so many hits? An index scan walks the index in customer_id
-- order and jumps back to the main table for each row to check status and read amount.
-- shared read: PostgreSQL had to read the required data into shared buffers from the storage layer. Because the entire dataset and index were already
-- warm in memory, shared read is not present and returns 0

-- PostgreSQL uses a two-tier caching architecture: its own internal shared buffers pool and the OS page
-- cache. Because shared read is zero, every single one of the 413,477 8kb page was served directly out
-- of shared buffers. This warm cache may be responsible for changes in execution times.

--PROBLEM 7: ELT-STYLE TRANSFORMATION USING A MATERIALIZED VIEW
-- Treat orders_big as your raw loaded data.
CREATE MATERIALIZED VIEW daily_revenue AS
SELECT
    order_date,
    status,
    SUM(amount) AS total_revenue,
    COUNT(order_id) AS order_count
FROM orders_big
WHERE status IS DISTINCT FROM 'cancelled'
GROUP BY order_date, status
ORDER BY order_date ASC;

-- Next, write two dashboard queries that calculate revenue for one selected month.
-- A. RAW TABLE QUERY
-- Calculate monthly revenue directly from orders_big.
EXPLAIN ANALYZE
SELECT
    order_date,
    status,
    SUM(amount) AS total_revenue,
    COUNT(order_id) AS order_count
FROM orders_big
WHERE status IS DISTINCT FROM 'cancelled'
    AND order_date >= DATE '2025-02-01'
    AND order_date < DATE '2025-03-01'
GROUP BY order_date, status
ORDER BY order_date;

-- QUERY PLAN                                       
-- Execution Plans: Sort -> HashAggregate -> Bitmap Heap Scan on orders_big -> Bitmap Index Scan on idx_orders_big_order_date
-- Scan types: Bitmap Heap Scan on orders_big -> Bitmap Index Scan on idx_orders_big_order_date
-- Planning time: 0.238 ms
-- Number of rows returned: 112
-- Heap Blocks: exact=7761
-- Execution time: 74.347 ms

-- B. MATERIALIZED VIEW QUERY
-- Calculate the same monthly revenue from daily_revenue.
EXPLAIN ANALYZE
SELECT
    order_date,
    status,
    total_revenue,
    order_count
FROM daily_revenue
WHERE order_date >= DATE '2025-02-01'
    AND order_date < DATE '2025-03-01'
ORDER BY order_date;

-- QUERY PLAN                                       
-- Execution Plans: Sort -> Seq Scan on daily_revenue
-- Scan types: Seq Scan on daily_revenue
-- Execution time: 0.093 ms
-- Number of rows returned: 112
-- Planning time: 0.327 ms

-- Both queries return the same revenue.

-- Standard view is just a saved SQL query. Every time a user or dashboard queries it,
-- PostgreSQL must re-scan orders_big, filter and compute aggregations from scratch. A
-- materialized view executes that query once and persists the summarized rows onto
-- disk like a physical table. Hence, indexes can be built on the materialized view.

-- The ELT approach:
-- Extract: obtain the raw order data.
-- Load: store the data in orders_big.
-- Transform: aggregate the raw data into daily_revenue.
-- Serve: allow dashboard queries to read the precomputed results.

-- Unlike the live query against orders_big, daily_revenue is a point in time snapshot. Until REFRESH
-- MATERIALIZED VIEW daily_revenue is run, new orders or changes will not  automatically update.

-- PROBLEM 8: TEST MATERIALIZED VIEW FRESHNESS AND REFRESH
-- Insert 1,000 new rows into orders_big.
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
FROM generate_series(1000001, 1001000) AS gs;

--Insert
INSERT INTO orders_big
SELECT * FROM extra_orders;

-- Query daily_revenue before refreshing it.
SELECT
    order_date::DATE,
    status,
    total_revenue,
    order_count
FROM daily_revenue
WHERE order_date::date >= DATE '2025-02-01'
    AND order_date::date < DATE '2025-03-01'
ORDER BY order_date::date;

-- Compare the result with a fresh aggregation directly from orders_big.
SELECT
    order_date,
    status,
    SUM(amount) AS total_revenue,
    COUNT(order_id) AS order_count
FROM orders_big
WHERE status IS DISTINCT FROM 'cancelled'
    AND order_date >= DATE '2025-02-01'
    AND order_date < DATE '2025-03-01'
GROUP BY order_date, status
ORDER BY order_date;

-- There are few changes in the total_revenue and order_count for the live query of orders_big
-- compared to the stale results of daily_revenue which still show result from the previous run.

-- Run
REFRESH MATERIALIZED VIEW daily_revenue;

-- Query the materialized view again and compare it with the raw table aggregation.
SELECT
    order_date::DATE,
    status,
    total_revenue,
    order_count
FROM daily_revenue
WHERE order_date::date >= DATE '2025-02-01'
    AND order_date::date < DATE '2025-03-01'

EXCEPT

SELECT
    order_date,
    status,
    SUM(amount) AS total_revenue,
    COUNT(order_id) AS order_count
FROM orders_big
WHERE status IS DISTINCT FROM 'cancelled'
    AND order_date >= DATE '2025-02-01'
    AND order_date < DATE '2025-03-01'
GROUP BY order_date, status
ORDER BY order_date;

-- Both now return the same results with the EXCEPT returning zero rows.

-- A transformation that can be safely rerun produces the same correct output from the same underlying source
-- data. Refreshing a materialized view rebuilds its stored results rather than simply adding the new 
-- rows to the previous totals.This avoids accumulating duplicate aggregates when the transformation is rerun.
-- If you plan to refresh this view without blocking concurrent SELECT queries (REFRESH MATERIALIZED VIEW 
-- CONCURRENTLY daily_revenue;), create a UNIQUE index on the grouping columns right after creating the view.

DROP TABLE IF EXISTS orders_big;
DROP MATERIALIZED TABLE IF EXISTS daily_revenue;