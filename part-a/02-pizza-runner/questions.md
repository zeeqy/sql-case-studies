# Case 2: Pizza Runner: questions

Source: [8 Week SQL Challenge, Case Study #2](https://8weeksqlchallenge.com/case-study-2/) by Danny Ma.
The questions are reworded here. See the original page for the full brief.

A pizza delivery start-up with its own runners. The raw order tables are messy (text 'null's, units inside numbers),
so the data is cleaned first in [cleaning.sql](cleaning.sql).

## A. Pizza metrics
1. Total pizzas ordered.
2. Number of distinct orders.
3. Successful deliveries per runner.
4. Delivered pizzas by type.
5. Meat Lovers vs Vegetarian ordered by each customer.
6. Largest number of pizzas delivered in one order.
7. Per customer, delivered pizzas with at least one change vs none.
8. Delivered pizzas with both exclusions and extras.
9. Pizzas ordered by hour of day.
10. Orders by day of week.

## B. Runner and customer experience
1. Runner sign-ups per week (weeks start 2021-01-01).
2. Average minutes from order to pickup, per runner.
3. Relationship between pizzas per order and preparation time.
4. Average delivery distance per customer.
5. Longest minus shortest delivery time.
6. Speed of each delivery per runner, and any trend.
7. Successful delivery rate per runner.

## C. Ingredient optimisation
1. Standard ingredients of each pizza.
2. Most common extra.
3. Most common exclusion.
4. A readable label for every ordered pizza (e.g. "Meat Lovers - Exclude Beef - Extra Bacon").
5. An alphabetical ingredient list per pizza with "2x" for doubled toppings.
6. Total quantity of each ingredient in delivered pizzas, most used first.

## D. Pricing and ratings
1. Revenue at $12 Meat Lovers / $10 Vegetarian, no change fees.
2. Revenue with $1 per extra.
3. Design a runner ratings table and fill it for delivered orders.
4. One table of successful deliveries with rating, timings, speed and pizza count.
5. Money left after paying runners $0.30 per km.

## E. Bonus
Add a "Supreme" pizza with every topping (DML).
