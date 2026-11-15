-- Case 2: Pizza Runner, data cleaning. Runs after schema.sql (via `sqlcases seed`).
-- The raw tables are left untouched. Clean copies get a clean_ prefix.
SET search_path = pizza_runner;

-- Problems found in the raw data:
--   customer_orders.exclusions / extras: '' , 'null' (text) and NULL all mean "none";
--     the real values are comma-separated id lists stored as text ('1, 5').
--   customer_orders has no primary key, and order 4 contains two identical rows,
--     so one pizza cannot be told apart from another. An item_id fixes that.
--   runner_orders.distance: '20km', '13.4km', '23.4 km', '10'   -> numeric km
--   runner_orders.duration: '32 minutes', '20 mins', '15 minute', '40' -> integer minutes
--   runner_orders.pickup_time: text, sometimes 'null'           -> timestamp
--   runner_orders.cancellation: '', 'null', NULL mean "not cancelled".

DROP TABLE IF EXISTS clean_customer_orders;
CREATE TABLE clean_customer_orders (
    item_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    INTEGER NOT NULL,
    customer_id INTEGER NOT NULL,
    pizza_id    INTEGER NOT NULL,
    exclusions  INTEGER[] NOT NULL DEFAULT '{}',  -- topping ids; empty array = none
    extras      INTEGER[] NOT NULL DEFAULT '{}',
    order_time  TIMESTAMP NOT NULL
);

-- NULLIF turns '' and 'null' into real NULLs; string_to_array + cast gives an int[].
-- COALESCE then turns "none" into an empty array, so later code never has to handle NULL.
INSERT INTO clean_customer_orders (order_id, customer_id, pizza_id, exclusions, extras, order_time)
SELECT order_id, customer_id, pizza_id,
       COALESCE(string_to_array(NULLIF(NULLIF(exclusions, ''), 'null'), ', ')::INTEGER[], '{}'),
       COALESCE(string_to_array(NULLIF(NULLIF(extras, ''), 'null'), ', ')::INTEGER[], '{}'),
       order_time
FROM customer_orders
ORDER BY order_id, pizza_id;

DROP TABLE IF EXISTS clean_runner_orders;
CREATE TABLE clean_runner_orders AS
SELECT order_id,
       runner_id,
       NULLIF(pickup_time, 'null')::TIMESTAMP                               AS pickup_time,
       -- keep only digits and the decimal point, then cast
       NULLIF(regexp_replace(distance, '[^0-9.]', '', 'g'), '')::NUMERIC(5, 1) AS distance_km,
       NULLIF(regexp_replace(duration, '[^0-9]', '', 'g'), '')::INTEGER      AS duration_min,
       NULLIF(NULLIF(cancellation, ''), 'null')                             AS cancellation
FROM runner_orders;

ALTER TABLE clean_runner_orders ADD PRIMARY KEY (order_id);

-- Recipes: one row per (pizza, topping) is far easier to join than '1, 2, 3'.
DROP TABLE IF EXISTS clean_recipe_toppings;
CREATE TABLE clean_recipe_toppings AS
SELECT pizza_id, unnest(string_to_array(toppings, ', '))::INTEGER AS topping_id
FROM pizza_recipes;
