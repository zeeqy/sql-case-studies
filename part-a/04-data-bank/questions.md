# Case 4: Data Bank: questions

Source: [8 Week SQL Challenge, Case Study #4](https://8weeksqlchallenge.com/case-study-4/) by Danny Ma.
The questions are reworded here. See the original page for the full brief.

A digital-only "neo-bank" whose customers also get cloud data storage linked to their account balance.
Customers are moved between secure nodes in 5 regions. 500 customers, 5,868 transactions (Jan–Apr 2020).

## A. Customer nodes
1. How many unique nodes are there?
2. Nodes per region.
3. Customers per region.
4. Average days before a customer is moved to a different node.
5. Median, 80th and 95th percentile of that metric per region.

## B. Customer transactions
1. Count and total amount per transaction type.
2. Average number of deposits and average deposit total per customer.
3. Per month: customers with more than one deposit and at least one purchase or withdrawal.
4. Closing balance per customer at each month end.
5. Share of customers who grew their closing balance by more than 5%.

## C. Data allocation challenge
Generate a running balance, month-end balances, and min/avg/max balance per customer. Then estimate
the data needed each month if allocation is based on:
1. the previous month's closing balance,
2. the average balance over the previous 30 days, or
3. the balance in real time.

## D. Extra challenge
Data grows like a savings account at 6% a year, credited daily. How much data per month, without and with daily compounding?

## Extension
Headline insights for investors and customers, and a one-page summary of the allocation options for management.
