-- PROBLEM 1: Count the total number of orders whose status is 'delivered'.
SELECT COUNT(*) AS total_delivered_orders 
FROM orders
WHERE status = 'delivered';

-- PROBLEM 2: Retrieve all orders made using 'cash_on_delivery' as the payment method, 
-- arranging the results from newest to oldest.
SELECT * 
FROM orders
WHERE payment_method = 'cash_on_delivery'
ORDER BY order_date DESC;

-- PROBLEM 3: Calculate the total number of orders for each order status.
SELECT status, COUNT(*) AS total_orders_count
FROM orders
GROUP BY status
ORDER BY total_orders_count DESC;

-- PROBLEM 4: Calculate the average unit_price across all products.
SELECT ROUND(AVG(unit_price), 2) AS average_unit_price
FROM products;

-- PROBLEM 5: Count the number of customers in each city and arrange the results from the city with the 
-- highest customer count to the lowest.
SELECT city, COUNT(*) AS customer_count
FROM customers
GROUP BY city
ORDER BY customer_count DESC;

-- PROBLEM 6: Display only the cities with more than 8 customers.
SELECT city, COUNT(*) AS customer_count
FROM customers
GROUP BY city
HAVING COUNT(*) > 8
ORDER BY customer_count DESC;

-- PROBLEM 7: Calculate the total quantity sold for each product using the order_items table. 
-- Display only products whose total quantity sold exceeds 50.
SELECT product_id, SUM(quantity) AS total_quantity_sold
FROM order_items
GROUP BY product_id
HAVING SUM(quantity) > 50
ORDER BY total_quantity_sold DESC;

-- PROBLEM 8: Count the number of orders for each payment method, excluding orders with a 'cancelled' status. 
-- Display only payment methods with more than 30 orders. 
-- Use both WHERE and HAVING clauses to filter the records before and after grouping, respectively.
SELECT payment_method, COUNT(*) AS total_orders_count
FROM orders
WHERE status <> 'cancelled'
GROUP BY payment_method
HAVING COUNT(*) > 30
ORDER BY total_orders_count DESC;