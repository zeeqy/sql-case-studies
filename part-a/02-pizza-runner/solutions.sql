-- Case 2: Pizza Runner. My own solutions (PostgreSQL 16).
-- Uses the clean_ tables built by cleaning.sql (see that file for what was fixed).
-- "Delivered" means clean_runner_orders.cancellation IS NULL.
SET search_path = pizza_runner;

-- =====================================================================
-- A. Pizza metrics
-- =====================================================================

-- A1. Pizzas ordered (one row = one pizza).
SELECT COUNT(*) AS pizzas_ordered FROM clean_customer_orders;

-- A2. Unique customer orders.
SELECT COUNT(DISTINCT order_id) AS orders FROM clean_customer_orders;

-- A3. Successful deliveries per runner.
SELECT runner_id, COUNT(*) AS delivered_orders
FROM clean_runner_orders
WHERE cancellation IS NULL
GROUP BY runner_id
ORDER BY runner_id;

-- A4. Delivered pizzas by type.
SELECT pn.pizza_name, COUNT(*) AS delivered
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
JOIN pizza_names pn USING (pizza_id)
WHERE ro.cancellation IS NULL
GROUP BY pn.pizza_name;

-- A5. Pizzas ordered per customer by type, as one row per customer.
-- FILTER is Postgres's tidy form of SUM(CASE WHEN ... THEN 1 END).
SELECT co.customer_id,
       COUNT(*) FILTER (WHERE pn.pizza_name = 'Meatlovers')  AS meatlovers,
       COUNT(*) FILTER (WHERE pn.pizza_name = 'Vegetarian') AS vegetarian
FROM clean_customer_orders co
JOIN pizza_names pn USING (pizza_id)
GROUP BY co.customer_id
ORDER BY co.customer_id;

-- A6. Most pizzas delivered in one order.
SELECT co.order_id, COUNT(*) AS pizzas
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
WHERE ro.cancellation IS NULL
GROUP BY co.order_id
ORDER BY pizzas DESC
LIMIT 1;

-- A7. Per customer: delivered pizzas with at least one change vs none.
-- cardinality() is the length of an array; a change is any exclusion or extra.
SELECT co.customer_id,
       COUNT(*) FILTER (WHERE cardinality(co.exclusions) + cardinality(co.extras) > 0) AS changed,
       COUNT(*) FILTER (WHERE cardinality(co.exclusions) + cardinality(co.extras) = 0) AS unchanged
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
WHERE ro.cancellation IS NULL
GROUP BY co.customer_id
ORDER BY co.customer_id;

-- A8. Delivered pizzas with both exclusions and extras.
SELECT COUNT(*) AS both_changes
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
WHERE ro.cancellation IS NULL
  AND cardinality(co.exclusions) > 0
  AND cardinality(co.extras) > 0;

-- A9. Pizza volume by hour of day.
SELECT EXTRACT(HOUR FROM order_time)::INT AS hour, COUNT(*) AS pizzas
FROM clean_customer_orders
GROUP BY hour
ORDER BY hour;

-- A10. Order volume by day of week (ISODOW: 1 = Monday, used only for sorting).
SELECT TO_CHAR(order_time, 'Day') AS weekday, COUNT(DISTINCT order_id) AS orders
FROM clean_customer_orders
GROUP BY weekday, EXTRACT(ISODOW FROM order_time)
ORDER BY EXTRACT(ISODOW FROM order_time);

-- =====================================================================
-- B. Runner and customer experience
-- =====================================================================

-- B1. Runner sign-ups per week, with weeks starting on 2021-01-01.
-- Integer division of the day offset by 7 gives the week number. date_trunc('week')
-- would start on Mondays instead, which is not what was asked.
SELECT (registration_date - DATE '2021-01-01') / 7 + 1 AS week,
       DATE '2021-01-01' + ((registration_date - DATE '2021-01-01') / 7) * 7 AS week_start,
       COUNT(*) AS runners
FROM runners
GROUP BY 1, 2
ORDER BY 1;

-- B2. Average minutes from order to pickup, per runner.
-- One row per order first (DISTINCT), otherwise multi-pizza orders count several times.
WITH orders AS (
    SELECT DISTINCT co.order_id, ro.runner_id, co.order_time, ro.pickup_time
    FROM clean_customer_orders co
    JOIN clean_runner_orders ro USING (order_id)
    WHERE ro.pickup_time IS NOT NULL
)
SELECT runner_id,
       ROUND(AVG(EXTRACT(EPOCH FROM pickup_time - order_time) / 60), 1) AS avg_pickup_min
FROM orders
GROUP BY runner_id
ORDER BY runner_id;

-- B3. Do bigger orders take longer to prepare? (prep = order to pickup)
WITH orders AS (
    SELECT co.order_id, COUNT(*) AS pizzas,
           EXTRACT(EPOCH FROM MAX(ro.pickup_time) - MAX(co.order_time)) / 60 AS prep_min
    FROM clean_customer_orders co
    JOIN clean_runner_orders ro USING (order_id)
    WHERE ro.pickup_time IS NOT NULL
    GROUP BY co.order_id
)
SELECT pizzas, COUNT(*) AS orders, ROUND(AVG(prep_min), 1) AS avg_prep_min,
       ROUND(AVG(prep_min) / pizzas, 1) AS min_per_pizza
FROM orders
GROUP BY pizzas
ORDER BY pizzas;

-- B4. Average delivery distance per customer (per order, not per pizza).
SELECT customer_id, ROUND(AVG(distance_km), 1) AS avg_km
FROM (SELECT DISTINCT co.order_id, co.customer_id, ro.distance_km
      FROM clean_customer_orders co
      JOIN clean_runner_orders ro USING (order_id)
      WHERE ro.cancellation IS NULL) o
GROUP BY customer_id
ORDER BY customer_id;

-- B5. Longest minus shortest delivery time.
SELECT MAX(duration_min) - MIN(duration_min) AS range_min
FROM clean_runner_orders;

-- B6. Speed per delivery (km/h) and the trend per runner.
SELECT runner_id, order_id, distance_km, duration_min,
       ROUND(distance_km / (duration_min / 60.0), 1) AS speed_kmh,
       ROUND(AVG(distance_km / (duration_min / 60.0)) OVER (PARTITION BY runner_id), 1)
           AS runner_avg_kmh
FROM clean_runner_orders
WHERE cancellation IS NULL
ORDER BY runner_id, order_id;

-- B7. Successful delivery percentage per runner.
-- AVG over a boolean cast to int gives the share of TRUE rows.
SELECT runner_id,
       ROUND(100 * AVG((cancellation IS NULL)::INT), 0) AS success_pct
FROM clean_runner_orders
GROUP BY runner_id
ORDER BY runner_id;

-- =====================================================================
-- C. Ingredient optimisation
-- =====================================================================

-- C1. Standard ingredients for each pizza.
SELECT pn.pizza_name, STRING_AGG(pt.topping_name, ', ' ORDER BY lower(pt.topping_name)) AS ingredients
FROM clean_recipe_toppings rt
JOIN pizza_names pn USING (pizza_id)
JOIN pizza_toppings pt USING (topping_id)
GROUP BY pn.pizza_name;

-- C2. Most commonly added extra. unnest() turns the array into one row per topping.
SELECT pt.topping_name, COUNT(*) AS times_added
FROM clean_customer_orders co
CROSS JOIN LATERAL unnest(co.extras) AS e(topping_id)
JOIN pizza_toppings pt USING (topping_id)
GROUP BY pt.topping_name
ORDER BY times_added DESC
LIMIT 1;

-- C3. Most common exclusion.
SELECT pt.topping_name, COUNT(*) AS times_excluded
FROM clean_customer_orders co
CROSS JOIN LATERAL unnest(co.exclusions) AS x(topping_id)
JOIN pizza_toppings pt USING (topping_id)
GROUP BY pt.topping_name
ORDER BY times_excluded DESC
LIMIT 1;

-- C4. A readable label per ordered pizza, e.g. 'Meat Lovers - Exclude Beef - Extra Bacon'.
-- Scalar subqueries turn each id array into topping names. CONCAT_WS skips NULL parts,
-- so the ' - Exclude' / ' - Extra' pieces only appear when the array is non-empty.
SELECT co.item_id, co.order_id,
       CONCAT_WS(' - ',
           CASE pn.pizza_name WHEN 'Meatlovers' THEN 'Meat Lovers' ELSE pn.pizza_name END,
           'Exclude ' || (SELECT STRING_AGG(topping_name, ', ' ORDER BY topping_name)
                          FROM pizza_toppings WHERE topping_id = ANY (co.exclusions)),
           'Extra ' || (SELECT STRING_AGG(topping_name, ', ' ORDER BY topping_name)
                        FROM pizza_toppings WHERE topping_id = ANY (co.extras))
       ) AS order_item
FROM clean_customer_orders co
JOIN pizza_names pn USING (pizza_id)
ORDER BY co.item_id;

-- C5. Alphabetical ingredient list per pizza with '2x' on doubled toppings,
-- e.g. 'Meat Lovers: 2xBacon, Beef, ...'.
-- Build every topping actually on the pizza: recipe minus exclusions, plus extras.
-- An extra that is already in the recipe ends up counted twice, hence 2x.
WITH toppings AS (
    SELECT co.item_id, rt.topping_id
    FROM clean_customer_orders co
    JOIN clean_recipe_toppings rt USING (pizza_id)
    WHERE NOT rt.topping_id = ANY (co.exclusions)
    UNION ALL
    SELECT co.item_id, e.topping_id
    FROM clean_customer_orders co
    CROSS JOIN LATERAL unnest(co.extras) AS e(topping_id)
),
counted AS (
    SELECT t.item_id, pt.topping_name, COUNT(*) AS n
    FROM toppings t
    JOIN pizza_toppings pt USING (topping_id)
    GROUP BY t.item_id, pt.topping_name
)
SELECT co.item_id, co.order_id,
       CASE pn.pizza_name WHEN 'Meatlovers' THEN 'Meat Lovers' ELSE pn.pizza_name END || ': ' ||
       STRING_AGG(CASE WHEN c.n > 1 THEN c.n || 'x' ELSE '' END || c.topping_name, ', '
                  ORDER BY lower(c.topping_name)) AS ingredients
FROM counted c
JOIN clean_customer_orders co USING (item_id)
JOIN pizza_names pn USING (pizza_id)
GROUP BY co.item_id, co.order_id, pn.pizza_name
ORDER BY co.item_id;

-- C6. Total quantity of each ingredient across delivered pizzas, most used first.
WITH toppings AS (
    SELECT co.order_id, rt.topping_id
    FROM clean_customer_orders co
    JOIN clean_recipe_toppings rt USING (pizza_id)
    WHERE NOT rt.topping_id = ANY (co.exclusions)
    UNION ALL
    SELECT co.order_id, e.topping_id
    FROM clean_customer_orders co
    CROSS JOIN LATERAL unnest(co.extras) AS e(topping_id)
)
SELECT pt.topping_name, COUNT(*) AS quantity
FROM toppings t
JOIN clean_runner_orders ro USING (order_id)
JOIN pizza_toppings pt USING (topping_id)
WHERE ro.cancellation IS NULL
GROUP BY pt.topping_name
ORDER BY quantity DESC, pt.topping_name;

-- =====================================================================
-- D. Pricing and ratings
-- =====================================================================

-- D1. Revenue from delivered pizzas: Meat Lovers $12, Vegetarian $10, no change fees.
SELECT SUM(CASE pn.pizza_name WHEN 'Meatlovers' THEN 12 ELSE 10 END) AS revenue
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
JOIN pizza_names pn USING (pizza_id)
WHERE ro.cancellation IS NULL;

-- D2. Same, plus $1 per extra topping (cheese included).
SELECT SUM(CASE pn.pizza_name WHEN 'Meatlovers' THEN 12 ELSE 10 END
           + cardinality(co.extras)) AS revenue_with_extras
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
JOIN pizza_names pn USING (pizza_id)
WHERE ro.cancellation IS NULL;

-- D3. A ratings table for runners, one rating per delivered order.
-- Design: order_id is the primary key (at most one rating per order) and a foreign key
-- to clean_runner_orders. A CHECK keeps scores in 1-5. The comment column is optional.
-- The ratings below are made up by me, as the case asks.
DROP TABLE IF EXISTS runner_ratings;
CREATE TABLE runner_ratings (
    order_id   INTEGER PRIMARY KEY REFERENCES clean_runner_orders (order_id),
    rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment    TEXT,
    rated_at   TIMESTAMP NOT NULL DEFAULT now()
);
INSERT INTO runner_ratings (order_id, rating, comment) VALUES
    (1, 5, NULL), (2, 4, NULL), (3, 4, 'a bit late'), (4, 2, 'cold pizza, 40 min'),
    (5, 5, NULL), (7, 4, NULL), (8, 5, 'very fast'), (10, 5, NULL);

-- D4. One table of successful deliveries with rating, timings and speed.
SELECT co.customer_id, co.order_id, ro.runner_id, rr.rating,
       co.order_time, ro.pickup_time,
       ROUND(EXTRACT(EPOCH FROM ro.pickup_time - co.order_time) / 60, 1) AS order_to_pickup_min,
       ro.duration_min AS delivery_min,
       ROUND(ro.distance_km / (ro.duration_min / 60.0), 1) AS avg_speed_kmh,
       COUNT(*) AS pizzas
FROM clean_customer_orders co
JOIN clean_runner_orders ro USING (order_id)
LEFT JOIN runner_ratings rr USING (order_id)
WHERE ro.cancellation IS NULL
GROUP BY co.customer_id, co.order_id, ro.runner_id, rr.rating, co.order_time,
         ro.pickup_time, ro.duration_min, ro.distance_km
ORDER BY co.order_id;

-- D5. Money left after paying runners $0.30 per km (no extra fees).
-- Revenue is per pizza but pay is per order, so aggregate them separately. Joining first
-- and summing distance would count a 3-pizza order's distance three times.
SELECT
    (SELECT SUM(CASE pn.pizza_name WHEN 'Meatlovers' THEN 12 ELSE 10 END)
     FROM clean_customer_orders co
     JOIN clean_runner_orders ro USING (order_id)
     JOIN pizza_names pn USING (pizza_id)
     WHERE ro.cancellation IS NULL)                                    AS revenue,
    (SELECT ROUND(SUM(distance_km) * 0.30, 2)
     FROM clean_runner_orders WHERE cancellation IS NULL)              AS runner_pay,
    (SELECT SUM(CASE pn.pizza_name WHEN 'Meatlovers' THEN 12 ELSE 10 END)
     FROM clean_customer_orders co
     JOIN clean_runner_orders ro USING (order_id)
     JOIN pizza_names pn USING (pizza_id)
     WHERE ro.cancellation IS NULL)
    - (SELECT ROUND(SUM(distance_km) * 0.30, 2)
       FROM clean_runner_orders WHERE cancellation IS NULL)            AS left_over;

-- =====================================================================
-- E. Bonus DML: add a Supreme pizza with every topping.
-- Done inside a transaction that is rolled back, so the shared dataset stays unchanged.
-- =====================================================================
BEGIN;
INSERT INTO pizza_names (pizza_id, pizza_name) VALUES (3, 'Supreme');
INSERT INTO pizza_recipes (pizza_id, toppings)
SELECT 3, STRING_AGG(topping_id::TEXT, ', ' ORDER BY topping_id) FROM pizza_toppings;
SELECT pn.pizza_id, pn.pizza_name, pr.toppings
FROM pizza_names pn JOIN pizza_recipes pr USING (pizza_id)
ORDER BY pn.pizza_id;
ROLLBACK;
