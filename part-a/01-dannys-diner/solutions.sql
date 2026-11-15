-- Case 1: Danny's Diner. My own solutions (PostgreSQL 16).
-- Tables: sales(customer_id, order_date, product_id), menu(product_id, product_name, price),
--         members(customer_id, join_date)
SET search_path = dannys_diner;

-- Q1. Total spend per customer.
-- Join each sale to its price, then sum per customer.
SELECT s.customer_id, SUM(m.price) AS total_spent
FROM sales s
JOIN menu m USING (product_id)
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q2. Days visited per customer.
-- A customer can buy several items on one day, so count DISTINCT dates, not rows.
SELECT customer_id, COUNT(DISTINCT order_date) AS days_visited
FROM sales
GROUP BY customer_id
ORDER BY customer_id;

-- Q3. First item(s) each customer bought.
-- Orders have a date but no time, so items on the first day are a tie.
-- DENSE_RANK keeps every tied item instead of picking one at random (ROW_NUMBER would).
WITH ranked AS (
    SELECT s.customer_id, m.product_name,
           DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date) AS rnk
    FROM sales s
    JOIN menu m USING (product_id)
)
SELECT customer_id, STRING_AGG(DISTINCT product_name, ', ') AS first_items
FROM ranked
WHERE rnk = 1
GROUP BY customer_id
ORDER BY customer_id;

-- Q4. Most purchased item overall, and how often it was bought.
SELECT m.product_name, COUNT(*) AS times_purchased
FROM sales s
JOIN menu m USING (product_id)
GROUP BY m.product_name
ORDER BY times_purchased DESC
LIMIT 1;

-- Q5. Favourite item per customer (ties kept).
-- Count per customer+item first, then rank those counts inside each customer.
WITH counts AS (
    SELECT s.customer_id, m.product_name, COUNT(*) AS n,
           DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY COUNT(*) DESC) AS rnk
    FROM sales s
    JOIN menu m USING (product_id)
    GROUP BY s.customer_id, m.product_name
)
SELECT customer_id, STRING_AGG(product_name, ', ' ORDER BY product_name) AS favourite, n
FROM counts
WHERE rnk = 1
GROUP BY customer_id, n
ORDER BY customer_id;

-- Q6. First item bought after becoming a member.
-- Assumption: an order ON the join date counts as a member purchase.
WITH member_sales AS (
    SELECT s.customer_id, s.order_date, m.product_name,
           DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date) AS rnk
    FROM sales s
    JOIN members mb USING (customer_id)
    JOIN menu m USING (product_id)
    WHERE s.order_date >= mb.join_date
)
SELECT customer_id, order_date, product_name
FROM member_sales
WHERE rnk = 1
ORDER BY customer_id;

-- Q7. Last item(s) bought just before becoming a member.
-- Same idea as Q6, but ranked by date DESCENDING over pre-join orders.
WITH pre_member AS (
    SELECT s.customer_id, s.order_date, m.product_name,
           DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date DESC) AS rnk
    FROM sales s
    JOIN members mb USING (customer_id)
    JOIN menu m USING (product_id)
    WHERE s.order_date < mb.join_date
)
SELECT customer_id, order_date, STRING_AGG(product_name, ', ' ORDER BY product_name) AS items
FROM pre_member
WHERE rnk = 1
GROUP BY customer_id, order_date
ORDER BY customer_id;

-- Q8. Items and spend for each member before they joined.
SELECT s.customer_id, COUNT(*) AS items, SUM(m.price) AS spent
FROM sales s
JOIN members mb USING (customer_id)
JOIN menu m USING (product_id)
WHERE s.order_date < mb.join_date
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q9. Loyalty points: 10 points per $1, sushi earns double.
-- Assumption: every purchase earns points, member or not (the question doesn't restrict it).
SELECT s.customer_id,
       SUM(m.price * CASE WHEN m.product_name = 'sushi' THEN 20 ELSE 10 END) AS points
FROM sales s
JOIN menu m USING (product_id)
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q10. Points for members A and B by 31 Jan 2021, with double points on everything
-- during the first 7 days of membership (join date + 6 days).
-- Outside that week the Q9 rule applies. Pre-join purchases still earn points (Q9 assumption).
SELECT s.customer_id,
       SUM(m.price * CASE
               WHEN s.order_date BETWEEN mb.join_date AND mb.join_date + 6 THEN 20
               WHEN m.product_name = 'sushi' THEN 20
               ELSE 10
           END) AS points_jan
FROM sales s
JOIN members mb USING (customer_id)
JOIN menu m USING (product_id)
WHERE s.order_date <= DATE '2021-01-31'
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Bonus: one wide table with a member flag, and a ranking only for member purchases.
-- Non-member rows get NULL rank, which is what the business asked for.
WITH joined AS (
    SELECT s.customer_id, s.order_date, m.product_name, m.price,
           CASE WHEN s.order_date >= mb.join_date THEN 'Y' ELSE 'N' END AS member
    FROM sales s
    JOIN menu m USING (product_id)
    LEFT JOIN members mb USING (customer_id)
)
SELECT *,
       CASE WHEN member = 'Y'
            THEN DENSE_RANK() OVER (PARTITION BY customer_id, member ORDER BY order_date)
       END AS ranking
FROM joined
ORDER BY customer_id, order_date, product_name;
