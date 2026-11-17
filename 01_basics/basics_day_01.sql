-- PROBLEM 1: Retrieve all columns and all records from the customers table.
\d+ customers
SELECT * FROM customers LIMIT 10;

-- PROBLEM 2: Retrieve only the full_name and city columns for every customer.
SELECT COALESCE(NULLIF(CONCAT_WS(' ', first_name, last_name), ''), 'Unknown') AS full_name, city 
FROM customers;

-- PROBLEM 3: Calculate the total number of customers currently stored in the customers table.
SELECT COUNT(*) AS total_customers FROM customers;

-- PROBLEM 4: Retrieve a list of all unique cities represented in the customers table, ensuring that no city appears more than once.
SELECT DISTINCT city FROM customers;

-- PROBLEM 5: Retrieve the 10 customers with the most recent signup dates, displaying the newest signups first.
SELECT * FROM customers ORDER BY signed_up DESC LIMIT 10;

-- PROBLEM 6: Retrieve all customer records belonging to customers whose city is Lagos.
SELECT * FROM customers WHERE city = 'New York';

-- PROBLEM 7: Retrieve all products with a price greater than 100, arranging the results in ascending order of price (cheapest to most expensive).
SELECT * FROM products WHERE unit_price > 100 ORDER BY unit_price ASC;