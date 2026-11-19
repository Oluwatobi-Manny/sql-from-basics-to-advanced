/*
DAY 4: SUBQUERIES, CTEs AND CASE STATEMENTS

ASSUMPTIONS:
- Cancelled orders are excluded from revenue calculations.
- Returned orders are treated as "lost" alongside cancelled orders.
- Delivered and shipped orders are treated as "completed".
- Revenue is calculated using quantity * unit_price from order_items.
- Monthly revenue is based on the order_date.
- For spend tiers, use the total amount spent by each customer, excluding cancelled orders.
- For price comparison, assume order_items.unit_price stores the price at the time the order was placed, while products.unit_price represents the current product price.

*/

-- PROBLEM 1: Find the products priced above the average product price (use a subquery).
SELECT 
    product_id, 
    name, 
    unit_price
FROM products
WHERE unit_price > (
    SELECT AVG(unit_price) 
    FROM products)
ORDER BY unit_price DESC
;

-- PROBLEM 2: Find customers who have placed at least one order using IN with a subquery.
SELECT 
    customer_id, 
    first_name, 
    last_name
FROM customers
WHERE customer_id IN (
    SELECT customer_id
    FROM orders
);

--   Then rewrite the query using EXISTS and check that both return the same rows.
SELECT 
    customer_id, 
    first_name, 
    last_name
FROM customers c
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.customer_id = c.customer_id
);

-- Both returns the same number of rows: 84, as they both identify customers who have placed at least one order. 
-- The IN clause checks for membership in a list of customer IDs from the orders table, while the EXISTS 
-- clause checks for the existence of any matching records in the orders table for each customer.

-- PROBLEM 3: Find customers who have never placed an order using NOT EXISTS.
SELECT 
    customer_id, 
    first_name, 
    last_name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.customer_id = c.customer_id
);

-- Compare the result with your Day 3 LEFT JOIN version.
SELECT 
    c.customer_id AS customer_id,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name
FROM customers AS c
LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- PROBLEM 4: Using a CTE, calculate monthly revenue for 2026, excluding cancelled orders.
-- Display the results in chronological month order.
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
)
SELECT 
    month_year, 
    revenue
FROM monthly_revenue
ORDER BY month_start;

-- PROBLEM 5: Classify customers into spend tiers (Low, Medium, High) using CASE,
-- built on a CTE containing each customer's total spent.
WITH customer_spend AS (
	SELECT c.customer_id AS customer_id,
		COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name,
		SUM(oi.quantity * oi.unit_price) AS total_spent
	FROM customers AS c
	LEFT JOIN orders AS o
		ON c.customer_id = o.customer_id
		AND o.status IS DISTINCT FROM 'cancelled'
	LEFT JOIN order_items AS oi
		ON o.order_id = oi.order_id
	GROUP BY c.customer_id,
		first_name,
		last_name
)
SELECT 
	customer_id, 
    full_name,
    total_spent,
	CASE 
	    WHEN total_spent IS NULL THEN 'Missing'
        ELSE CASE NTILE(3) OVER (ORDER BY total_spent)
	        WHEN 1 THEN 'Low'
	        WHEN 2 THEN 'Medium'
	        WHEN 3 THEN 'High'
	    END
    END AS spend_tier
FROM customer_spend
ORDER BY total_spent DESC NULLS LAST;

-- PROBLEM 6: Use CASE to group order statuses into:
--   - Completed: delivered, shipped.
--   - Pending: pending.
--   - Lost: cancelled, returned.
--   Then count the number of orders in each group.
WITH order_status AS (
	SELECT 
        order_id, 
        status,
	CASE 
		WHEN status IN ('shipped', 'delivered') THEN 'completed'
		WHEN status IN ('pending') THEN 'pending'
        WHEN status IN ('cancelled', 'returned') THEN 'lost'
		ELSE 'others'
	END AS status_group
	FROM orders
)
SELECT 
    status_group, 
    COUNT(status_group) AS status_count
FROM order_status
GROUP BY status_group
ORDER BY status_count DESC;

-- PROBLEM 7: Calculate the percentage of orders that were cancelled,
--   rounded to 1 decimal place.
SELECT status, 
    COUNT(status) AS status_count,
	ROUND(100.0 * COUNT(status) / SUM(COUNT(status)) OVER (), 1) AS status_percentage
FROM orders
GROUP BY status;

-- PROBLEM 8: Compare order_items.unit_price with products.unit_price and count
--   the rows where the two prices differ.
WITH price_comparison AS (
    SELECT 
        p.product_id AS product_id, 
        p.unit_price AS catalog_price, 
        oi.unit_price AS sold_price, 
        (p.unit_price - oi.unit_price) as differences
    FROM products AS p
    INNER JOIN order_items AS oi
        ON p.product_id = oi.product_id
    WHERE p.unit_price IS DISTINCT FROM oi.unit_price
)
SELECT COUNT(*) AS price_mismatch_count
FROM price_comparison;

-- The result is zero. Storing the price on order_items is important  because it allows for historical 
-- accuracy in financial reporting and analysis. Product prices can change over time and storing the price
-- at the time of the order ensures that revenue calculations reflect the actual transaction value
-- rather than the current product price. This is crucial for understanding past sales performance and customer behavior.
