/*
DAY 10: COHORT ANALYSIS, INCREMENTAL LOADS AND SLIDING WINDOWS

ASSUMPTIONS:
- Exclude cancelled orders from all calculations unless a problem explicitly says otherwise.
- Revenue is calculated as quantity * unit_price from order_items.
- A customer's cohort month is the month of their first non-cancelled order.
- Month numbers are zero-based: the cohort month is month 0, the following month is month 1, and so on.
- For retention, count each customer only once per month, even if they placed multiple orders.
- For returning-customer analysis, a customer is returning if they were active in the current month and had at least one non-cancelled order in an earlier month.
- For daily revenue, use the DATE portion of order_date.
- The daily_revenue_summary table should have one row per date, with date as its primary key.
*/

-- PROBLEM 1: COHORT ASSIGNMENT
-- For each customer, find the month of their first non-cancelled order.
WITH monthly_orders AS (
    SELECT 
        c.customer_id,
        o.order_date,
        DATE_TRUNC('month', o.order_date)::DATE AS cohort_month,
        ROW_NUMBER () OVER (PARTITION BY c.customer_id ORDER BY o.order_date ASC) AS ranked
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
)
SELECT
    customer_id,
    cohort_month
FROM monthly_orders
WHERE ranked = 1
ORDER BY customer_id;

-- PROBLEM 2: COHORT SIZES
--  Count the number of customers assigned to each cohort month.
WITH monthly_orders AS (
    SELECT 
        c.customer_id,
        DATE_TRUNC('month', MIN(o.order_date))::DATE AS cohort_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id
)
SELECT
    cohort_month,
    COUNT(customer_id) AS customer_count
FROM monthly_orders
GROUP BY cohort_month
ORDER BY cohort_month;

/* Result
cohort_month | customer_count
--------------+----------------
2026-01-01   |              8
2026-02-01   |             16
2026-03-01   |             12
2026-04-01   |             14
2026-05-01   |              3
2026-06-01   |              8
2026-07-01   |              4
2026-08-01   |              6
2026-09-01   |              6
2026-10-01   |              3
2026-11-01   |              2
*/

-- PROBLEM 3: CUSTOMER MONTHLY ACTIVITY
-- For each customer and each month in which they had at least one non-cancelled order, calculate:
WITH customer_activity AS (
    SELECT DISTINCT
        c.customer_id,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
),
cohort_assigned AS(
    SELECT
        customer_id,
        activity_month,
        FIRST_VALUE(activity_month) OVER (
            PARTITION BY customer_id
            ORDER BY activity_month ASC
        ) AS cohort_month
    FROM customer_activity
)
SELECT
    customer_id,
    cohort_month,
    activity_month,
    (
    (EXTRACT(YEAR FROM activity_month) - EXTRACT(YEAR FROM cohort_month)) * 12 +
    (EXTRACT(MONTH FROM activity_month) - EXTRACT(MONTH FROM cohort_month))
    )::INT AS month_number
FROM cohort_assigned
ORDER BY customer_id, activity_month;

-- PROBLEM 4: RETENTION COUNTS
-- Using the cohort assignment and monthly activity results, count active customers for each cohort_month and month_number
WITH customer_cohort AS (
    SELECT 
        c.customer_id,
        DATE_TRUNC('month', MIN(o.order_date))::DATE AS cohort_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id
),
monthly_activity AS (
    SELECT DISTINCT
        c.customer_id,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
),
count_activity AS (
    SELECT 
        cc.cohort_month,
        (
        (EXTRACT(YEAR FROM ma.activity_month) - EXTRACT(YEAR FROM cc.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM ma.activity_month) - EXTRACT(MONTH FROM cc.cohort_month))
        )::INT AS month_number,
        COUNT(DISTINCT cc.customer_id) AS active_customers
    FROM customer_cohort cc
    JOIN monthly_activity ma
        ON cc.customer_id = ma.customer_id
    GROUP BY cc.cohort_month, month_number
)
SELECT
    cohort_month,
    month_number,
    active_customers
FROM count_activity;

-- PROBLEM 5: RETENTION MATRIX
-- Build a retention matrix One row per cohort_month, columns for month 0 through month 5 and 
-- each cell showing the retention percentage.

WITH customer_cohort AS (
    SELECT 
        c.customer_id,
        DATE_TRUNC('month', MIN(o.order_date))::DATE AS cohort_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
    GROUP BY c.customer_id
),
monthly_activity AS (
    SELECT DISTINCT
        c.customer_id,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
),
retention_count AS (
    SELECT 
        cc.cohort_month,
        (
        (EXTRACT(YEAR FROM ma.activity_month) - EXTRACT(YEAR FROM cc.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM ma.activity_month) - EXTRACT(MONTH FROM cc.cohort_month))
        )::INT AS month_number,
        COUNT(DISTINCT cc.customer_id) AS active_customers
    FROM customer_cohort cc
    JOIN monthly_activity ma
        ON cc.customer_id = ma.customer_id
    GROUP BY cc.cohort_month, month_number
),
cohort_sizes AS(
    SELECT
        cohort_month,
        active_customers AS cohort_size
    FROM retention_count
    WHERE month_number = 0
)
SELECT
    rc.cohort_month,
    cs.cohort_size,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 0) / cs.cohort_size, 1) AS month_0,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 1) / cs.cohort_size, 1) AS month_1,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 2) / cs.cohort_size, 1) AS month_2,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 3) / cs.cohort_size, 1) AS month_3,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 4) / cs.cohort_size, 1) AS month_4,
    ROUND(100.0 * MAX(rc.active_customers) FILTER (WHERE rc.month_number = 5) / cs.cohort_size, 1) AS month_5
FROM retention_count rc
JOIN cohort_sizes cs
ON rc.cohort_month = cs.cohort_month
GROUP BY rc.cohort_month, cs.cohort_size
ORDER BY rc.cohort_month;

-- The dataset is small, so some cohort/month combinations will have no activity. 
-- Some cells may therefore be NULL or 0. This is expected and not necessarily indicate a query error.

-- PROBLEM 6: RETURNING CUSTOMERS
-- For each calendar month, calculate the percentage of active customers who had also placed at 
-- least one non-cancelled order in an earlier month.
WITH monthly_activity AS (
    SELECT DISTINCT
        c.customer_id,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
        AND o.status IS DISTINCT FROM 'cancelled'
),
customer_earliest_activity AS (
    SELECT
        customer_id,
        activity_month,
        MIN(activity_month) OVER (PARTITION BY customer_id) AS cohort_month
    FROM monthly_activity
)
SELECT
    activity_month,
    COUNT(customer_id) AS total_active_customers,
    COUNT(customer_id) FILTER (WHERE activity_month > cohort_month) AS total_returning_customers,
    ROUND(
        100.0 * COUNT(customer_id) FILTER (WHERE activity_month > cohort_month) 
        / NULLIF(COUNT(customer_id), 0), 2
    ) AS returning_customer_percentage
FROM customer_earliest_activity
GROUP BY activity_month
ORDER BY activity_month;

/* Result
activity_month | total_active_customers | total_returning_customers | returning_customer_percentage
----------------+------------------------+---------------------------+-------------------------------
2026-01-01     |                      8 |                         0 |                          0.00
2026-02-01     |                     16 |                         0 |                          0.00
2026-03-01     |                     14 |                         2 |                         14.29
2026-04-01     |                     20 |                         6 |                         30.00
2026-05-01     |                     16 |                        13 |                         81.25
2026-06-01     |                     11 |                         3 |                         27.27
2026-07-01     |                     13 |                         9 |                         69.23
2026-08-01     |                     14 |                         8 |                         57.14
2026-09-01     |                     18 |                        12 |                         66.67
2026-10-01     |                     10 |                         7 |                         70.00
2026-11-01     |                     10 |                         8 |                         80.00
*/

-- PROBLEM 7: INCREMENTAL BATCH LOAD: DAILY REVENUE SUMMARY
-- Create a table named daily_revenue_summary
DROP TABLE IF EXISTS daily_revenue_summary;

CREATE TABLE IF NOT EXISTS daily_revenue_summary (
    revenue_date DATE PRIMARY KEY,
    revenue NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    order_count INTEGER NOT NULL DEFAULT 0
);

-- Write an incremental load.
INSERT INTO daily_revenue_summary(
    revenue_date,
    revenue,
    order_count
)
SELECT
    o.order_date::DATE AS revenue_date,
    COALESCE(ROUND(SUM(oi.quantity * oi.unit_price), 2), 0.00) AS revenue,
    COUNT(DISTINCT o.order_id) AS order_count
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status IS DISTINCT FROM 'cancelled'
    AND o.order_date >= COALESCE(
        (SELECT MAX(drs.revenue_date) - 3 
        FROM daily_revenue_summary drs), '1900-01-01'::DATE
    ) -- Incremental filter: reprocess the last 3 days up to today to catch late updates/cancellations
GROUP BY o.order_date::DATE
ON CONFLICT (revenue_date)
DO UPDATE SET
    revenue = EXCLUDED.revenue,
    order_count = EXCLUDED.order_count;

-- Test idempotency.
-- Run the load once.
-- Record the number of rows and inspect the summary.
SELECT COUNT(*) 
FROM daily_revenue_summary;

SELECT 
    SUM(revenue) AS total_revenue,
    SUM(order_count) AS total_order,
    COUNT(*) AS total_days,
    MIN(revenue_date) AS earliest_date,
    MAX(revenue_date) AS latest_date
FROM daily_revenue_summary
LIMIT 10;

/* Result
count
-------
    122

total_revenue | total_order | total_days | earliest_date | latest_date
---------------+-------------+------------+---------------+-------------
    978397.93 |         154 |        122 | 2026-01-22    | 2026-11-16
*/

-- Run the exact same load again.
SELECT COUNT(*) 
FROM daily_revenue_summary;

SELECT 
    SUM(revenue) AS total_revenue,
    SUM(order_count) AS total_order,
    COUNT(*) AS total_days,
    MIN(revenue_date) AS earliest_date,
    MAX(revenue_date) AS latest_date
FROM daily_revenue_summary
LIMIT 10;

/* Result
count
-------
    122

total_revenue | total_order | total_days | earliest_date | latest_date
---------------+-------------+------------+---------------+-------------
    978397.93 |         154 |        122 | 2026-01-22    | 2026-11-16
*/


-- Test a new batch.
-- Create a copy of your orders data.
DROP TABLE IF EXISTS orders_copy;

CREATE TABLE orders_copy (
    LIKE orders INCLUDING ALL
);

INSERT INTO orders_copy
SELECT *
FROM orders;

-- Insert a few new orders with dates later than the latest date in the summary.
WITH customer_ids AS(
    SELECT array_agg(customer_id) AS ids FROM customers
)
INSERT INTO orders_copy (customer_id, order_date, status, payment_method, total_amount)
SELECT 
    c.ids[floor(random() * array_length(c.ids, 1)) + 1] AS customer_id,
    NOW() - (random() * (INTERVAL '10 days')) AS order_date,
    (ARRAY['pending', 'shipped', 'delivered', 'cancelled', 'returned'])[floor(random() * 5) + 1] AS status,
    (ARRAY['card', 'bank_transfer', 'cash_on_delivery', 'wallet', 'other'])[floor(random() * 5) + 1] AS payment_method,
    ROUND((random() * 1000 + 50)::NUMERIC, 2) AS total_amount
FROM generate_series(201, 230) AS s(i)
CROSS JOIN customer_ids c;

-- Include corresponding order items so the new orders have revenue.
DROP TABLE IF EXISTS order_items_copy;

CREATE TABLE order_items_copy (
    LIKE order_items INCLUDING ALL
);

INSERT INTO order_items_copy
SELECT * FROM order_items;

INSERT INTO order_items_copy (order_id, product_id, quantity, unit_price)
SELECT
    o.order_id AS order_id,
    p.product_id AS product_id,
    floor(random() * 5 + 1) AS quantity,
    p.unit_price AS unit_price
FROM (
    SELECT order_id
    FROM orders_copy
    WHERE order_id IS NOT NULL
    ORDER BY order_id DESC
    LIMIT 25
) o
CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 4)) AS gs(i)  -- Each order will have between 1 and 4 items
JOIN products p ON p.product_id = 1 + ((o.order_id * 3 + gs.i * 5) % 16)  
WHERE o.order_id IS NOT NULL;

-- Run the incremental load against the copied data.
INSERT INTO daily_revenue_summary(
    revenue_date,
    revenue,
    order_count
)
SELECT
    o.order_date::DATE AS revenue_date,
    COALESCE(ROUND(SUM(oi.quantity * oi.unit_price), 2), 0.00) AS revenue,
    COUNT(DISTINCT o.order_id) AS order_count
FROM orders_copy o
JOIN order_items_copy oi
    ON o.order_id = oi.order_id
WHERE o.status IS DISTINCT FROM 'cancelled'
    AND o.order_date >= COALESCE(
        (SELECT MAX(drs.revenue_date) - 3 
        FROM daily_revenue_summary drs), '1900-01-01'::DATE
    )
GROUP BY o.order_date::DATE
ON CONFLICT (revenue_date)
DO UPDATE SET
    revenue = EXCLUDED.revenue,
    order_count = EXCLUDED.order_count;

-- Confirm that only the new dates are added to the summary.
SELECT COUNT(*) 
FROM daily_revenue_summary;

SELECT 
    SUM(revenue) AS total_revenue,
    SUM(order_count) AS total_order,
    COUNT(*) AS total_days,
    MIN(revenue_date) AS earliest_date,
    MAX(revenue_date) AS latest_date
FROM daily_revenue_summary
LIMIT 10;


/* Result
count
-------
    131

total_revenue  | total_order | total_days | earliest_date | latest_date
---------------+-------------+------------+---------------+-------------
    1070497.74 |         172 |        131 | 2026-01-22    | 2026-11-27
*/

-- Day 6 used ON CONFLICT DO NOTHING to prevent duplicate records. Here, ON CONFLICT DO UPDATE ensures
-- that an existing date is updated instead of duplicated. The load uses the latest processed date to
-- avoid reprocessing older data. Running the same batch again should not create duplicate dates or
-- change already processed results.

-- Production orchestrators (e.g., Airflow, dbt, cron) frequently retry failed or timed-out jobs. Using 
-- ON CONFLICT (...) DO UPDATE ensures that re-running this script multiple times for the same date range 
-- overwrites rows cleanly rather than failing on primary key violations or double-counting revenue.

-- PROBLEM 8: SLIDING WINDOW: ROLLING 7-DAY REVENUE
-- Show daily revenue alongside a rolling 7-day revenue total.
WITH active_days AS (
	SELECT DISTINCT 
        o.order_date::DATE AS order_day,
        SUM(oi.quantity * oi.unit_price) AS line_amount
	FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
	WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY o.order_date::DATE
),
calendar AS(
	SELECT generate_series(
		(SELECT MIN(order_day)::DATE FROM active_days),
		(SELECT MAX(order_day)::DATE FROM active_days),
		'1 day'::INTERVAL
	)::DATE AS calendar_date
)
SELECT
	c.calendar_date AS calendar_date,
    a.line_amount AS daily_revenue,
    SUM(a.line_amount) OVER (
        ORDER BY c.calendar_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_total
FROM calendar c
LEFT JOIN active_days a
	ON a.order_day = c.calendar_date
ORDER BY calendar_date;

-- A streaming system would continuously receive new order events and update the rolling 7-day total as new events arrive.
-- It would maintain state for the relevant time window and remove or expire events that fall outside the 7-day range.
-- A batch process is sufficient for a daily report because the report only needs to be refreshed once per day, rather than updated continuously.
-- Streaming introduces additional complexity and is only necessary when the business requires near-real-time results.
