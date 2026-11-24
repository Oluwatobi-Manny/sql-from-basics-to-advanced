/*
DAY 7: PIVOTING, UNPIVOTING, SESSIONIZATION, DEDUPLICATION
AND OLTP VS OLAP

ASSUMPTIONS:
- Cancelled orders are excluded from all calculations unless a problem explicitly says otherwise.
- An order's amount is the sum of its line items:
      SUM(quantity * unit_price)
- Revenue is attributed to the month in which the order was placed (order_date).
- The payment method values are: card, bank_transfer, cash_on_delivery, wallet, other.
- Assume each order has one payment method. If multiple payment records exist per order, avoid duplicating order revenue.
- For sessionization, orders are arranged chronologically using order_date.
- For complex deduplication, email is treated as the unique business key.
- When duplicate emails exist, retain the record with the latest updated_at timestamp.
- If two records have the same updated_at timestamp, use a consistent tie-breaker.
- The original Zuri Market tables should remain unchanged during these exercises.
*/

-- PROBLEM 1: Show monthly revenue with one column per payment method:
WITH active_orders AS(
    SELECT 
        o.order_id,
        o.order_date,
        (oi.quantity * oi.unit_price) AS line_total,
        o.payment_method
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
),
monthly_revenue AS(
    SELECT
        DATE_TRUNC('month', order_date) AS month_start,
        TO_CHAR(DATE_TRUNC('month', order_date), 'Mon-YYYY') AS month_year,
        SUM(order_amount) FILTER(WHERE payment_method = 'card') AS "card",
        SUM(order_amount) FILTER(WHERE payment_method = 'bank_transfer') AS "bank_transfer",
        SUM(order_amount) FILTER(WHERE payment_method = 'cash_on_delivery') AS "cash_on_delivery",
        SUM(order_amount) FILTER(WHERE payment_method = 'wallet') AS "wallet",
        SUM(order_amount) FILTER(WHERE payment_method = 'other') AS "other"
    FROM active_orders
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT 
    month_year,
    card,
    bank_transfer,
    cash_on_delivery,
    wallet,
    other
FROM monthly_revenue
ORDER BY month_start;

-- PROBLEM 2: Show the number of orders per city (rows) by order status (columns).
WITH all_orders AS(
    SELECT 
        o.order_id,
        c.city,
        o.status
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
),
city_count AS (
    SELECT
        city,
        COUNT(order_id) FILTER (WHERE status = 'returned') AS "returned",
        COUNT(order_id) FILTER (WHERE status = 'pending') AS "pending",
        COUNT(order_id) FILTER (WHERE status = 'shipped') AS "shipped",
        COUNT(order_id) FILTER (WHERE status = 'cancelled') AS "cancelled",
        COUNT(order_id) FILTER (WHERE status = 'delivered') AS "delivered"
    FROM all_orders
    GROUP BY city
)
SELECT *
FROM city_count;

-- PROBLEM 3: Convert the payment method columns back into rows 
WITH active_orders AS(
    SELECT 
        o.order_id,
        o.order_date,
        (oi.quantity * oi.unit_price) AS order_amount,
        o.payment_method
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
),
monthly_revenue AS(
    SELECT
        DATE_TRUNC('month', order_date) AS month_start,
        TO_CHAR(DATE_TRUNC('month', order_date), 'Mon-YYYY') AS month_year,
        COALESCE(SUM(order_amount) FILTER(WHERE payment_method = 'card'), 0) AS "card",
        COALESCE(SUM(order_amount) FILTER(WHERE payment_method = 'bank_transfer'), 0) AS "bank_transfer",
        COALESCE(SUM(order_amount) FILTER(WHERE payment_method = 'cash_on_delivery'), 0) AS "cash_on_delivery",
        COALESCE(SUM(order_amount) FILTER(WHERE payment_method = 'wallet'), 0) AS "wallet",
        COALESCE(SUM(order_amount) FILTER(WHERE payment_method = 'other'), 0) AS "other"
    FROM active_orders
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT 
    mr.month_year,
    v.payment_method,
    v.order_amount
FROM monthly_revenue mr
CROSS JOIN LATERAL(
    VALUES
        ('card', mr.card),
        ('bank_transfer', mr.bank_transfer),
        ('cash_on_delivery', mr.cash_on_delivery),
        ('wallet', mr.wallet),
        ('other', mr.other)
) AS v(payment_method, order_amount)
ORDER BY month_start;


--PROBLEM 4: Group each customer's orders into buying bursts. A new burst starts whenever an order occurs more than
-- 30 days after the customer's previous order.
WITH daily_orders AS (
    SELECT
        c.customer_id AS customer_id,
        o.order_date::date AS order_date,
        COUNT(o.order_id) AS orders_count
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id, o.order_date::date
),
event_gaps AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        LAG(order_date) 
            OVER(PARTITION BY customer_id ORDER BY order_date) AS prev_order_date
    FROM daily_orders
),
session_flag AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        MIN(order_date) OVER (PARTITION BY customer_id) AS first_order_date,
        MAX(order_date) OVER (PARTITION BY customer_id) AS last_order_date,
        CASE
            WHEN prev_order_date IS NULL THEN 1
            WHEN order_date - prev_order_date > 30 THEN 1
            ELSE 0
        END AS is_session_count
    FROM event_gaps
),
session_number AS(
    SELECT
        customer_id,
        order_date,
        orders_count,
        first_order_date,
        last_order_date,
        SUM(is_session_count) OVER(
            PARTITION BY customer_id
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS burst_number
    FROM session_flag
)
SELECT
    customer_id,
    burst_number,
    MIN(order_date) AS burst_start,
    MAX(order_date) AS burst_end,
    SUM(orders_count) AS orders_count
FROM session_number
GROUP BY customer_id, burst_number
ORDER BY customer_id, burst_number;

-- To get detailed information as to the burst duration among others, run this:
WITH daily_orders AS (
    SELECT
        c.customer_id AS customer_id,
        o.order_date::date AS order_date,
        COUNT(o.order_id) AS orders_count
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id, o.order_date::date
),
event_gaps AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        LAG(order_date) 
            OVER(PARTITION BY customer_id ORDER BY order_date) AS prev_order_date
    FROM daily_orders
),
session_flag AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        MIN(order_date) OVER (PARTITION BY customer_id) AS first_order_date,
        MAX(order_date) OVER (PARTITION BY customer_id) AS last_order_date,
        CASE
            WHEN prev_order_date IS NULL THEN 1
            WHEN order_date - prev_order_date > 30 THEN 1
            ELSE 0
        END AS is_session_count
    FROM event_gaps
),
session_number AS(
    SELECT
        customer_id,
        order_date,
        orders_count,
        first_order_date,
        last_order_date,
        SUM(is_session_count) OVER(
            PARTITION BY customer_id
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS burst_number
    FROM session_flag
),
burst AS (
    SELECT
        customer_id,
        burst_number,
        MIN(order_date) AS burst_start,
        MAX(order_date) AS burst_end,
        SUM(orders_count) AS orders_count
    FROM session_number
    GROUP BY customer_id, burst_number
    ORDER BY customer_id, burst_number
)
SELECT
    customer_id,
    burst_number,
    burst_start,
    burst_end,
    burst_end - burst_start + 1 AS burst_length_days,
    orders_count,
    burst_start - LAG(burst_end) OVER (
        PARTITION BY customer_id ORDER BY burst_number
    ) AS days_since_prev_burst,
    CASE
        WHEN burst_number = 1 THEN 'first'
        ELSE 'returning'
    END AS burst_type,
    burst_number = MAX(burst_number) OVER (PARTITION BY customer_id) AS is_latest_burst,
    CURRENT_DATE - MAX(burst_end) OVER (PARTITION BY customer_id) AS days_since_last_order
FROM burst
ORDER BY customer_id, burst_number;

-- PROBLEM 5: Find customers who have more than one buying burst.
WITH daily_orders AS (
    SELECT
        c.customer_id AS customer_id,
        o.order_date::date AS order_date,
        COUNT(o.order_id) AS orders_count
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id, o.order_date::date
),
event_gaps AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        LAG(order_date) 
            OVER(PARTITION BY customer_id ORDER BY order_date) AS prev_order_date
    FROM daily_orders
),
session_flag AS (
    SELECT
        customer_id,
        order_date,
        orders_count,
        MIN(order_date) OVER (PARTITION BY customer_id) AS first_order_date,
        MAX(order_date) OVER (PARTITION BY customer_id) AS last_order_date,
        CASE
            WHEN prev_order_date IS NULL THEN 1
            WHEN order_date - prev_order_date > 30 THEN 1
            ELSE 0
        END AS is_session_count
    FROM event_gaps
),
session_number AS(
    SELECT
        customer_id,
        order_date,
        orders_count,
        first_order_date,
        last_order_date,
        SUM(is_session_count) OVER(
            PARTITION BY customer_id
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS burst_number
    FROM session_flag
),
burst AS (
    SELECT
        customer_id,
        burst_number,
        MIN(order_date) AS burst_start,
        MAX(order_date) AS burst_end,
        SUM(orders_count) AS orders_count
    FROM session_number
    GROUP BY customer_id, burst_number
    ORDER BY customer_id, burst_number
)
SELECT
    customer_id,
    burst_number,
    burst_start,
    burst_end,
    orders_count
FROM burst
GROUP BY customer_id,
    burst_number,
    burst_start,
    burst_end,
    orders_count
HAVING MAX(burst_number) > 1;

-- PROBLEM 6: Create a table called customer_updates and insert approximately 8 records.
-- Keep only the latest record for each email.
CREATE TABLE IF NOT EXISTS customer_updates (
    customer_id SERIAL PRIMARY KEY,
    email VARCHAR(100),
    city VARCHAR (100),
    updated_at TIMESTAMP DEFAULT TIMESTAMP
);

TRUNCATE customer_updates;

INSERT INTO customer_updates (email, city, updated_at)
VALUES
    ('ade@example.com',   'Lagos',         '2026-01-10 09:15:00'),
    ('ade@example.com',   'Abuja',         '2026-04-22 14:30:00'),
    ('ade@example.com',   'Port Harcourt', '2026-09-05 11:00:00'),
    ('chioma@example.com','Enugu',         '2026-02-18 08:45:00'),
    ('chioma@example.com','Lagos',         '2026-07-30 16:20:00'),
    ('tunde@example.com', 'Ibadan',        '2026-03-12 10:10:00'),
    ('bisi@example.com',  'Kano',          '2026-05-27 13:05:00'),
    ('bisi@example.com',  'Kaduna',        '2026-10-14 17:40:00');

WITH dedup AS(
    SELECT 
        customer_id,
        email,
        city,
        updated_at,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY updated_at DESC) as ranked
    FROM customer_updates
)
SELECT
    customer_id,
    email,
    city,
    updated_at
FROM dedup
WHERE ranked = 1
ORDER BY customer_id, updated_at DESC;

-- PROBLEM 7: Repeat Problem 6 using PostgreSQL's DISTINCT ON.
SELECT DISTINCT ON (email)
    customer_id,
    email,
    city,
    updated_at
FROM customer_updates
ORDER BY email, updated_at DESC;

-- Their answers are the same. They both return the same rows. However, DISTINCT ON is a 
-- PostgreSQL-specific extension (also supported by a few Postgres-compatible engines like DuckDB), 
-- whereas ROW_NUMBER() is a standard ANSI SQL supported across almost all modern databases.
-- For quick, readable queries in PostgreSQL, DISTINCT ON is favoured and ROW_NUMBER() when there is a
-- need for portability, complex ranking or top-N per group. The ORDER BY clause in DISTINCT ON must
-- start with the exact columns listed in it.  PARTITION BY and ORDER BY inside OVER() are completely 
-- independent of the outer query's ORDER BY.

-- PROBLEM 8: Write two separate queries.
-- A. OLTP-STYLE QUERY: Fetch one specific order and all its associated order items using order_id.
SELECT
    o.order_id,
    o.order_date,
    c.customer_id,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name,
    p.product_id,
    p.name AS product_name,
    ca.category_id,
    ca.name AS category_name,
    oi.quantity,
    oi.unit_price,
    (oi.quantity * oi.unit_price) AS line_total
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
    AND o.status IS DISTINCT FROM 'cancelled'
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
JOIN categories ca
    ON p.category_id = ca.category_id
WHERE o.order_id = 30;

-- B. OLAP-STYLE QUERY: Calculate revenue by city by month across all qualifying orders.
WITH active_orders AS (
    SELECT
        c.customer_id,
        c.city,
        o.order_date,
        (oi.quantity * oi.unit_price) AS line_total
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
    JOIN order_items oi
        ON o.order_id = oi.order_id
),
monthly_revenue AS (
    SELECT
        city,
        DATE_TRUNC('month', order_date) AS month_start,
        TO_CHAR(DATE_TRUNC('month', order_date), 'Mon-YYYY') AS month_year,
        SUM(line_total) AS revenue
    FROM active_orders
    GROUP BY city, DATE_TRUNC('month', order_date)
)
SELECT
    city,
    month_year,
    revenue
FROM monthly_revenue
ORDER BY city, month_start;


-- The OLTP query retrieves one order and its related records. It typically touches a small number of
-- rows and benefits from indexes on order_id and relevant foreign keys.

-- The OLAP query aggregates data across many orders, customers, and order items. It may scan and process 
-- a large portion of the dataset.

-- OLTP workloads benefit from efficient indexing and fast individual transactions.

-- OLAP workloads benefit from efficient aggregation, analytical query planning, and potentially 
-- partitioning or columnar storage as the dataset grows.

-- OLTP is usually normalized to eliminate duplicate data. This prevents update anomalies and keeps INSERT
-- and DELETE operations fast because a change only touches a row in one table

-- OLAP is usually in a Star or Snowflake schema to duplicate data into a wide fact table surrounded by
-- dimension tables