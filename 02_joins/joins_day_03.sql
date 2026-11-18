-- PROBLEM 1: List each order's order_id, order_date, and the customer's name.
SELECT o.order_id AS order_id, o.order_date AS order_date,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name
FROM orders AS o
INNER JOIN customers AS c
    ON o.customer_id = c.customer_id;

-- PROBLEM 2: List each order item with the product name, quantity, and line total (quantity * unit_price).
SELECT oi.order_items_id AS order_item_id, p.name AS product_name,
    oi.quantity AS quantity, 
    (CASE WHEN oi.quantity IS NOT NULL AND oi.unit_price IS NOT NULL 
        THEN ROUND(oi.quantity * oi.unit_price, 2)
        ELSE NULL END) AS line_total
FROM order_items AS oi
LEFT JOIN products AS p
    ON oi.product_id = p.product_id;

-- PROBLEM 3: Find the total amount each customer has spent, highest spender first. 
SELECT c.customer_id AS customer_id,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_spent
FROM customers AS c
LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id
    AND o.status IS DISTINCT FROM 'cancelled'  -- Excludes cancelled orders from the total_spent
LEFT JOIN order_items AS oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_id,
        c.first_name,
        c.last_name
ORDER BY total_spent DESC;

-- PROBLEM 4: Find customers who have never placed an order.
SELECT c.customer_id AS customer_id,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name
FROM customers AS c
LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- PROBLEM 5: Find products that have never been sold.
SELECT p.product_id AS product_id, p.name AS product_name
FROM products AS p
LEFT JOIN order_items AS oi
    ON p.product_id = oi.product_id
WHERE oi.order_items_id IS NULL;

-- PROBLEM 6: Show the number of orders per customer, including customers with zero orders.
SELECT c.customer_id AS customer_id,
    COALESCE(NULLIF(CONCAT_WS(' ', c.first_name, c.last_name), ''), 'Unknown') AS full_name,
    COUNT(o.order_id) AS total_orders
FROM customers AS c
LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id
    AND o.status IS DISTINCT FROM 'cancelled'  -- Excludes cancelled orders from the total_spent
GROUP BY c.customer_id,
        c.first_name,
        c.last_name
ORDER BY total_orders DESC;

-- PROBLEM 7: List each product with its category.
SELECT p.product_id AS product_id, p.category_id AS category_id, 
    p.name AS product_name, ca.name AS category_name
FROM products AS p
LEFT JOIN categories AS ca
    ON p.category_id = ca.category_id
ORDER BY p.category_id, p.name;

-- PROBLEM 8: Run the customers-to-orders join twice:
-- Once using INNER JOIN.
SELECT *
FROM customers AS c
INNER JOIN orders AS o
ON c.customer_id = o.customer_id;

-- Once using LEFT JOIN.
SELECT *
FROM customers AS c
LEFT JOIN orders AS o
ON c.customer_id = o.customer_id;

-- Compare the row counts and explain the difference.
SELECT
    (SELECT COUNT(*)
    FROM customers AS c
    INNER JOIN orders AS o
    ON c.customer_id = o.customer_id) AS inner_join_count,
    (SELECT COUNT(*)
    FROM customers AS c
    LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id) AS left_join_count;

-- The inner join returned for rows where there was a match between customers and orders which is 200 rows.
-- The left join returned all rows from the customers table, including those without matching orders,
-- which totals 214 rows.
-- The difference is that left join includes all customers with an order as well as those with nulls.
-- The left join adds one row for each of the 14 customers with no orders (200 + 14 = 214). 
-- Those are the same customers found in Problem 4.