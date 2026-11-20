/*
DAY 5: WINDOW FUNCTIONS

ASSUMPTIONS:
- Revenue and order amounts are calculated using quantity * unit_price from order_items.
- Cancelled orders are excluded from revenue and customer spending calculations.
- Orders are considered chronologically using order_date.
- Customers are grouped by their city using the city column in the customers table.
- Month-over-month growth is calculated against the immediately preceding month.
- For running revenue, only completed orders (delivered and shipped) are included.
*/

-- PROBLEM 1: Number each customer's orders from first to latest.
SELECT 
    c.customer_id AS customer_id, 
    o.order_id AS order_id, 
    o.order_date AS order_date, 
    ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY o.order_date ASC) as order_sequence 
FROM customers c 
LEFT JOIN orders o 
    ON c.customer_id = o.customer_id 
WHERE o.status IS DISTINCT FROM 'cancelled' 
;

-- PROBLEM 2: Show only each customer's most recent order.
WITH recent_order AS
    (SELECT
        c.customer_id AS customer_id, 
        o.order_id AS order_id, 
        o.order_date AS order_date, 
        ROW_NUMBER() OVER 
            (PARTITION BY c.customer_id ORDER BY o.order_date DESC, o.order_id DESC) as order_sequence 
    FROM customers c
    LEFT JOIN orders o 
        ON c.customer_id = o.customer_id 
    WHERE o.status IS DISTINCT FROM 'cancelled') 
SELECT 
    customer_id, 
    order_id,
    order_date 
FROM recent_order 
WHERE order_sequence=1
    AND order_id IS NOT NULL
ORDER BY customer_id;

-- PROBLEM 3: Rank products by total quantity sold using both RANK() and DENSE_RANK() in the same query.
WITH qty_sold AS (
    SELECT 
        p.product_id AS product_id, 
        SUM(oi.quantity) AS total_quantity
    FROM products p 
    LEFT JOIN order_items oi
        ON p.product_id = oi.product_id
    GROUP BY p.product_id
)
SELECT 
    product_id, 
    total_quantity, 
    RANK() OVER(ORDER BY total_quantity DESC NULLS LAST) AS ranked_product, 
    DENSE_RANK() OVER(ORDER BY total_quantity DESC NULLS LAST) AS dense_ranked 
FROM qty_sold;

--   RANK() assigns the same rank to tied products and skips the next rank.
--   DENSE_RANK() assigns the same rank to tied products but does not skip the next rank.

-- PROBLEM 4: Find the top 3 customers by total spend in each city.
WITH revenue AS(
    SELECT 
        c.customer_id AS customer_id, 
        c.city AS city, 
        COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
    FROM customers c 
    LEFT JOIN orders o 
        ON c.customer_id = o.customer_id 
        AND o.status IS DISTINCT FROM 'cancelled' 
    LEFT JOIN order_items oi 
    ON o.order_id = oi.order_id
    GROUP BY c.customer_id, c.city
), 
ranked_revenue AS(
    SELECT 
        customer_id, 
        city, 
        revenue, 
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY revenue DESC) AS spend_rank
    FROM revenue)
SELECT * 
FROM ranked_revenue 
WHERE spend_rank <=3
ORDER BY city, spend_rank;

-- PROBLEM 5: Show daily revenue with a running total using a window function.
WITH revenue AS(
    SELECT
        o.order_date, 
        SUM(oi.quantity * oi.unit_price) AS revenue 
    FROM orders o 
    INNER JOIN order_items oi 
        ON o.order_id = oi.order_id 
    WHERE o.status IN ('delivered', 'shipped')  -- Only include completed orders for revenue calculation
    GROUP BY o.order_date
) 
SELECT 
    order_date, 
    revenue, 
    SUM(revenue) 
        OVER(ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total 
FROM revenue;

-- PROBLEM 6: Calculate month-over-month revenue change and percentage growth using LAG().
WITH monthly_revenue AS (
    SELECT 
        DATE_TRUNC('month', o.order_date) AS month_start,
        TO_CHAR(DATE_TRUNC('month', o.order_date), 'Mon-YYYY') AS month_year,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders AS o
    INNER JOIN order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.status IS DISTINCT FROM 'cancelled'  -- Excludes cancelled orders from the revenue calculation
        AND o.order_date >= '2026-01-01' 
        AND o.order_date < '2027-01-01'  -- Filters for orders in 2026
    GROUP BY DATE_TRUNC('month', o.order_date)
),
lagged AS (
    SELECT
        month_year,
        revenue,
        LAG(revenue) OVER (ORDER BY month_start) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    month_year,
    revenue,
    previous_month_revenue,
    revenue - previous_month_revenue AS revenue_change,
    ROUND(100.0 * (revenue - previous_month_revenue)
    / NULLIF(previous_month_revenue, 0), 2) AS percentage_growth
FROM lagged;

-- PROBLEM 7: For each customer, show the number of days between each order and their previous order.
WITH customer_orders AS(
    SELECT
        c.customer_id,
        o.order_date,
        LAG(o.order_date) OVER (
            PARTITION BY c.customer_id
            ORDER BY o.order_date ASC
        ) AS previous_order_date
    FROM customers c
    INNER JOIN orders o
        ON c.customer_id = o.customer_id 
    WHERE o.order_date IS NOT NULL
        AND o.status IS DISTINCT FROM 'cancelled'
    ORDER BY c.customer_id, o.order_date
)
SELECT 
    customer_id AS customer_id,
    order_date AS order_date,
    previous_order_date AS previous_order_date,
    NULLIF(DATE_PART('day', order_date - previous_order_date), 0) AS days_between_orders
FROM customer_orders;

-- PROBLEM 8: List each order with:
--  - The order_id.
--  - The customer_id.
--  - The order amount.
--  - The customer's average order amount alongside it.
-- First, calculate the average using: AVG() OVER (PARTITION BY ...).
WITH order_amounts AS(
    SELECT 
        o.order_id AS order_id,
        o.customer_id AS customer_id,
        SUM(oi.quantity * oi.unit_price) AS order_amount
    FROM orders o
    LEFT JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY o.order_id, o.customer_id
)
SELECT
    order_id AS order_id,
    customer_id AS customer_id,
    order_amount,
    ROUND(AVG(order_amount) OVER (PARTITION BY customer_id), 2) AS average_order_amount
FROM order_amounts;
-- Then write the same average using GROUP BY and compare both outputs.
WITH order_amounts AS(
    SELECT 
        o.order_id AS order_id,
        o.customer_id AS customer_id,
        SUM(oi.quantity * oi.unit_price) AS order_amount
    FROM orders o
    LEFT JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.status IS DISTINCT FROM 'cancelled'
    GROUP BY o.order_id, o.customer_id
),
customers_average AS(
    SELECT 
        customer_id,
        ROUND(AVG(order_amount), 2) AS average_order_amount
    FROM order_amounts
    GROUP BY customer_id
)
SELECT 
    oa.order_id AS order_id,
    oa.customer_id AS customer_id,
    oa.order_amount AS order_amount,
    ca.average_order_amount AS average_order_amount
FROM order_amounts oa
LEFT JOIN customers_average ca
    ON oa.customer_id = ca.customer_id
ORDER BY oa.customer_id, oa.order_id;

-- Both methods yield the same average order amount for each customer, but the first method uses
-- a window function to calculate the average alongside each order, while the second method uses 
-- a separate aggregation step with GROUP BY to calculate the average for each customer. The window 
-- function approach is often more efficient and concise, especially when you need to retain the individual order details alongside the aggregated average.
-- The GROUP BY approach is useful when you only need the aggregated results.