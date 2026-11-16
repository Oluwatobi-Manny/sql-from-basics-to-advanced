# The Story: Zuri Market

*Zuri Market is a fictional company created for this portfolio. All data is synthetic.*

## The company

Zuri Market is an online retail store founded in 2024, selling phones, laptops, fashion, home goods, and groceries to customers in Lagos, Abuja, Port Harcourt, Accra, Kumasi, and Nairobi. Customers pay by card, bank transfer, wallet, or cash on delivery.

Growth has been fast. The store processed 400 orders in 2025 and has 60 registered customers, with more signing up every week. But the data lives in five database tables that nobody has properly analyzed. Decisions are made on gut feeling and spreadsheets.

## My role

I am the first data hire. The leadership team has questions, and I have a PostgreSQL database and SQL. Every folder in this repo is a stage of that job.

## The team and what they want

- **The CEO** wants to know if the business is growing, and which products and cities drive revenue.
- **Head of Operations** worries about stock, cancelled orders, and returns.
- **Marketing Lead** wants to know who the best customers are, who has gone quiet, and whether new customers come back.
- **Finance** wants clean monthly revenue and a breakdown by payment method.

## How the story unfolds

| Stage | Folder | The business question |
| --- | --- | --- |
| 1 | `01-basics` | How many orders, customers, and products do we have? Which items are low on stock? |
| 2 | `02-joins` | What does each customer spend? Which customers never ordered? Which products never sold? |
| 3 | `03-intermediate` | What is monthly revenue? How do we group customers into spend tiers? What share of orders are cancelled? |
| 4 | `04-window-functions` | Who are the top 3 customers in each city? What is month-over-month growth? How long between a customer's orders? |
| 5 | `05-advanced` | How does revenue roll up the category tree? Which customers have gone inactive? How do we find and remove duplicate records? |
| 6 | `06-performance` | The revenue report now takes too long. Why, and how do we fix it with indexes? |
| 7 | `07-real-world` | Build the full picture: cohort retention, return rate by category, and an executive summary. |

## The goal

By the end, Zuri Market's leadership has answers they trust, and I have a portfolio showing you can take messy business questions and turn them into reliable SQL.
