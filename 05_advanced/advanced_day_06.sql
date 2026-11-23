/*
DAY 6: DATA QUALITY, DEDUPLICATION, IDEMPOTENT LOADING,
RECURSIVE CTEs, GAPS AND ISLANDS

ASSUMPTIONS:
- customers_raw is a practice copy of the original customers table.
- customer_id is unique and can be used to identify individual customer records.
- Email addresses should be unique across customers.
- When duplicate emails exist, the record with the earliest (lowest) customer_id is retained.
- The original customers table remains unchanged throughout the exercises.
- Duplicate rows inserted into customers_raw are copies of existing customers.
- For idempotent loading, email is treated as the unique business key.
- Cancelled orders are excluded when calculating consecutive days with orders.
- A day with at least one non-cancelled order counts as an active day.
- Calendar days are based on the minimum and maximum order_date in the orders table.
- Date gaps are measured using calendar days, not business days.

*/

-- PROBLEM 1: Create a practice table then insert 5 duplicate rows of copies of existing customers,
-- so that 5 customers now appear twice.
CREATE TABLE customers_raw AS
SELECT * FROM customers;

-- Insert 5 random customers into customers_raw to create duplicates.
INSERT INTO customers_raw(customer_id, first_name, last_name, email, phone_number, city, signed_up)
SELECT customer_id, first_name, last_name, email, phone_number, city, signed_up
FROM customers
ORDER BY RANDOM()
LIMIT 5;

-- PROBLEM 2: Find duplicate customers by email using GROUP BY and HAVING.
SELECT customer_id, email, COUNT(email) AS duplicate_count
FROM customers_raw
GROUP BY email, customer_id
HAVING COUNT(email) > 1
ORDER BY customer_id ASC;

-- PROBLEM 3: Using ROW_NUMBER(), show every row with a duplicate number.
SELECT customer_id, email,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY customer_id ASC) AS row_num
FROM customers_raw
ORDER BY customer_id ASC;

-- PROBLEM 4: Delete the duplicate records from customers_raw, keeping only the earliest customer_id.
BEGIN;

DELETE FROM customers_raw
WHERE ctid IN(
    SELECT ctid
    FROM (
        SELECT ctid,
                ROW_NUMBER() OVER (PARTITION BY email ORDER BY customer_id ASC, ctid ASC) AS row_num
        FROM customers_raw
    ) AS t
    WHERE row_num > 1
);

-- Confirm the deletion by checking the row count of customers_raw.
SELECT 
    (SELECT COUNT(*) FROM customers_raw) AS customers_raw_count,
    (SELECT COUNT(*) FROM customers) AS customers_count;

-- If the row counts match, commit the transaction; otherwise, rollback.
COMMIT; -- if the counts match, otherwise use ROLLBACK;

-- PROBLEM 5: Make the loading process idempotent.
-- Add a UNIQUE constraint on email in customers_raw.
ALTER TABLE customers_raw
ADD CONSTRAINT customers_email_unique UNIQUE (email);
-- Write an INSERT statement that loads records from customers. Use ON CONFLICT (email) DO NOTHING.
SELECT COUNT(*) AS count_before_insert
FROM customers_raw;

TRUNCATE TABLE customers_raw;

-- The above count should match the count after the insert below, demonstrating idempotency.
INSERT INTO customers_raw(customer_id, first_name, last_name, email, phone_number, city, signed_up)
SELECT customer_id, first_name, last_name, email, phone_number, city, signed_up
FROM customers
ORDER BY customer_id ASC
ON CONFLICT (email) DO NOTHING;

-- Count the rows after the first insert to confirm that no duplicates were created.
SELECT COUNT(*) AS count_after_insert_1
FROM customers_raw;

-- Run the INSERT statement twice.
INSERT INTO customers_raw(customer_id, first_name, last_name, email, phone_number, city, signed_up)
SELECT customer_id, first_name, last_name, email, phone_number, city, signed_up
FROM customers
ORDER BY customer_id ASC
ON CONFLICT (email) DO NOTHING;

-- Check that the row count remains unchanged after the second run.
SELECT COUNT(*) AS count_after_insert_2
FROM customers_raw;

-- With a `UNIQUE` constraint on email and the `ON CONFLICT DO NOTHING` clause, PostgreSQL will treat a duplicate
-- email as a conflict. The `ON CONFLICT DO NOTHING` clause ensures that if a record with the same email already 
-- exists in the `customers_raw` table, the insert operation will skip that record and not create a duplicate.

-- PROBLEM 6: Using a recursive CTE, list every category with its full hierarchy path and depth.
WITH RECURSIVE category_tree AS (
	SELECT
		category_id AS id,
		name,
		parent_category_id AS parent_id,
		name::TEXT AS full_path,
		1 AS depth
	FROM categories
    WHERE parent_category_id IS NULL

	UNION ALL

	SELECT
		c.category_id,
		c.name,
		c.parent_category_id,
		ct.full_path || ' > ' || c.name,
		ct.depth + 1
	FROM categories c
	INNER JOIN category_tree ct ON c.parent_category_id = ct.id
)
CYCLE id SET is_cycle USING path_array
SELECT
	id,
	'category' AS item_type,
	name,
	depth,
	full_path
FROM category_tree
WHERE NOT is_cycle

UNION ALL

SELECT
	p.product_id AS id,
	'product' AS item_type,
	p.name,
	ct.depth + 1 AS depth,
	ct.full_path || ' > ' || p.name AS full_path
FROM products p
INNER JOIN category_tree ct ON p.category_id = ct.id
WHERE NOT is_cycle
ORDER BY full_path;

--PROBLEM 7: Find the longest streak of consecutive calendar days that had at least one non-cancelled order.
WITH active_days AS (
	SELECT DISTINCT order_date::DATE AS order_day-- This deduplicate the order_date
	FROM orders
	WHERE status IS DISTINCT FROM 'cancelled'
),
grouped_streaks AS (
	SELECT 
		order_day,
		order_day::DATE - (ROW_NUMBER() OVER (ORDER BY order_day))::INT AS streak_group
	FROM active_days
)
SELECT
	MIN(order_day) AS start_date,
	MAX(order_day) AS end_date,
	COUNT(*) AS consecutive_days
FROM grouped_streaks
GROUP BY streak_group
ORDER BY consecutive_days DESC, start_date DESC     -- Use DESC to get the most recent streak in case of ties
LIMIT 1;

-- PROBLEM 8: Using GENERATE_SERIES(), find every calendar day within the minimum 
-- and maximum order_date range that had no orders.
WITH active_days AS (
	SELECT DISTINCT order_date::DATE AS order_day-- This deduplicate the order_date
	FROM orders
	WHERE status IS DISTINCT FROM 'cancelled'
),
calendar AS(
	SELECT generate_series(
		(SELECT MIN(order_day)::DATE FROM active_days),
		(SELECT MAX(order_day)::DATE FROM active_days),
		'1 day'::INTERVAL
	)::DATE AS calendar_date
)
SELECT
	c.calendar_date AS calendar_date
FROM calendar c
LEFT JOIN active_days a
	ON a.order_day = c.calendar_date
WHERE a.order_day IS NULL
ORDER BY calendar_date;