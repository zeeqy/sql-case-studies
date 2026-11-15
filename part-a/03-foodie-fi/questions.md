# Case 3: Foodie-Fi: questions

Source: [8 Week SQL Challenge, Case Study #3](https://8weeksqlchallenge.com/case-study-3/) by Danny Ma.
The questions are reworded here. See the original page for the full brief.

A food-video streaming subscription: free 7-day trial, then basic monthly, pro monthly, pro annual, or churn.
2,650 plan events for 1,000 customers (2020 to April 2021).

## A. Customer journey
Describe the onboarding journey of the 8 sample customers (1, 2, 11, 13, 15, 16, 18, 19).

## B. Data analysis
1. How many customers has Foodie-Fi ever had?
2. Trial starts per month.
3. Plan events starting after 2020, by plan.
4. Number and share of customers who churned.
5. Number and share who churned straight after the free trial.
6. Number and share of each plan chosen right after the trial.
7. Customer count and share per plan on 2020-12-31.
8. Customers who upgraded to the annual plan in 2020.
9. Average days from joining to the annual plan.
10. That average broken into 30-day buckets.
11. Downgrades from pro monthly to basic monthly in 2020.

## C. Payments challenge
Build a 2020 `payments` table following the billing rules (same day each month, prorated upgrades from basic,
annual upgrades from pro monthly charged at the end of the current period, nothing after churn).

## D. Beyond the brief
How fast is the paying base growing, month by month?
