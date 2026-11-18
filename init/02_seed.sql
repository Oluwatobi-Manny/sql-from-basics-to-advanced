-- Fixed seed so everyone gets the same random numbers
SELECT setseed(0.42);

-- Category tree (parent_category_id gives the self join and recursive relationship)
INSERT INTO categories (category_id, name, parent_category_id) VALUES
    (1, 'Electronics', NULL),
    (2, 'Computers', 1),
    (3, 'Laptops', 2),
    (4, 'Desktops', 2),
    (5, 'Smartphones', 1),
    (6, 'Cameras', 1),
    (7, 'Home Appliances', NULL),
    (8, 'Refrigerators', 7),
    (9, 'Washing Machines', 7),
    (10, 'Microwaves', 7);
SELECT setval('categories_category_id_seq', 10, true);

INSERT INTO products (category_id, name, unit_price, stock_quantity) VALUES
    (3, 'Gaming Laptop', 1500.00, 10),
    (3, 'Ultrabook Laptop', 1200.00, 15),
    (4, 'All-in-One Desktop', 1000.00, 5),
    (4, 'Gaming Desktop', 2000.00, 8),
    (5, 'Flagship Smartphone', 999.99, 20),
    (5, 'Budget Smartphone', 199.99, 50),
    (6, 'DSLR Camera', 800.00, 12),
    (6, 'Mirrorless Camera', 1200.00, 7),
    (8, 'Double Door Refrigerator', 1500.00, 6),
    (9, 'Front Load Washing Machine', 700.00, 10),
    (10, 'Convection Microwave Oven', 300.00, 15);

WITH generated_user_details AS (
    SELECT
        i,
        (ARRAY['John', 'Jane', 'Alice', 'Kofi', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Kwame'])[floor(random() * 10) + 1] AS first_name,
        (ARRAY['Okafor', 'Mensah', 'Johnson', 'Williams', 'Adeyemi', 'Ibrahim', 'Nwosu', 'Balogun', 'Osei', 'Rodriguez'])[floor(random() * 10) + 1] AS last_name,
        (ARRAY['123-456-7890', '234-567-8901', '345-678-9012', '456-789-0123', '567-890-1234', '678-901-2345', '789-012-3456', '890-123-4567', '901-234-5678', '012-345-6789'])[floor(random() * 10) + 1] AS phone_number,
        (ARRAY['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'San Jose'])[floor(random() * 10) + 1] AS city,
        NOW() - (random() * (INTERVAL '365 days')) AS signed_up,
        (ARRAY['example@org', 'mail.com', 'test.net', 'demo.org', 'sample.co'])[floor(random() * 5) + 1] AS email_domain
    FROM generate_series(1, 100) AS s(i))

INSERT INTO customers (first_name, last_name, email, phone_number, city, signed_up)
SELECT 
    first_name,
    last_name,
    first_name || '.' || last_name || i || '@' || email_domain AS email,
    phone_number,
    city,
    signed_up
FROM generated_user_details;

WITH customer_ids AS(
    SELECT array_agg(customer_id) AS ids FROM customers
)
INSERT INTO orders (customer_id, order_date, status, payment_method, total_amount)
SELECT 
    c.ids[floor(random() * array_length(c.ids, 1)) + 1] AS customer_id,
    NOW() - (random() * (INTERVAL '300 days')) AS order_date,
    (ARRAY['pending', 'shipped', 'delivered', 'cancelled', 'returned'])[floor(random() * 5) + 1] AS status,
    (ARRAY['card', 'bank_transfer', 'cash_on_delivery', 'wallet', 'other'])[floor(random() * 5) + 1] AS payment_method,
    ROUND((random() * 1000 + 50)::NUMERIC, 2) AS total_amount
FROM generate_series(1, 200) AS s(i)
CROSS JOIN customer_ids c;

-- Distinct products per order. Price is from the products table, quantity is random between 1 and 5
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.order_id AS order_id,
    p.product_id AS product_id,
    floor(random() * 5 + 1) AS quantity,
    p.unit_price AS unit_price
FROM orders o
CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 4)) AS gs(i)  -- Each order will have between 1 and 4 items
JOIN products p ON p.product_id = 1 + ((o.order_id * 3 + gs.i * 5) % 16)  
WHERE o.order_id IS NOT NULL;