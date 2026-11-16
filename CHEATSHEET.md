# SQL cheat sheet (PostgreSQL)

Patterns used in this repo, with where each one appears. Written for interview revision: what it does, when to reach
for it, and the trap.

## Ranking and "top N per group"
```sql
SELECT *, RANK() OVER (PARTITION BY state ORDER BY gmv DESC) AS rnk FROM g;   -- then WHERE rnk <= 3
```
| Function | Ties | Gaps after ties |
|---|---|---|
| `ROW_NUMBER()` | broken arbitrarily | n/a (always 1,2,3) |
| `RANK()` | same rank | yes (1,1,3) |
| `DENSE_RANK()` | same rank | no (1,1,2) |

**Trap:** `ROW_NUMBER` picks a random winner among ties. Use `RANK`/`DENSE_RANK` to keep ties, or add a tiebreaker column.
Where: Part A case 1 (Q3, Q5), Part B Q8.

## Latest row per group
```sql
SELECT DISTINCT ON (customer_id) customer_id, plan_id
FROM subscriptions WHERE start_date <= '2020-12-31'
ORDER BY customer_id, start_date DESC;
```
Postgres-only and very readable. Elsewhere: `ROW_NUMBER() ... = 1`. Where: Foodie-Fi B7.

## Previous / next row
```sql
LAG(plan_id)  OVER (PARTITION BY customer_id ORDER BY start_date) AS prev_plan,
LEAD(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan
```
Use it for "what happened right after X" (trial → churn), durations and transitions. Where: Foodie-Fi, Part B Q1.

## Running totals and the frame trap
```sql
SUM(amount) OVER (PARTITION BY wallet ORDER BY txn_date, txn_id ROWS UNBOUNDED PRECEDING)
```
**Trap:** with only `ORDER BY txn_date`, the default frame is `RANGE`, so every row on the same date gets the *end-of-day*
total. Use `ROWS` plus a unique tiebreaker for a true running total. Where: Data Bank C1.

## Rolling window over *time*, not rows
```sql
AVG(balance) OVER (PARTITION BY customer ORDER BY day ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)
```
This means "the last 30 days" only if there is **one row per day**. Build a date spine first (below). Where: Data Bank C3.

## Date spine (fill the gaps)
```sql
SELECT c.customer_id, d::DATE AS day
FROM customers c
CROSS JOIN generate_series(DATE '2020-01-01', DATE '2020-04-30', INTERVAL '1 day') AS d;
-- LEFT JOIN the facts onto it, COALESCE(x, 0)
```
Without it, days and months with no activity disappear from `GROUP BY`, and running balances or retention go wrong.
Where: Data Bank views, Part B v_promo_effect.
**Trap:** `generate_series(date, date, interval)` returns `timestamptz`. Use integer offsets (`start + k`) to stay `DATE`.

## Gaps-and-islands (sessionising)
```sql
-- 1. flag where a new group starts   2. running SUM of flags = group id   3. GROUP BY it
CASE WHEN ts - LAG(ts) OVER w <= INTERVAL '30 minutes' THEN 0 ELSE 1 END AS new_burst
SUM(new_burst) OVER (PARTITION BY wallet ORDER BY ts) AS burst_no
```
Merges consecutive rows into "stays" or "sessions". Where: Data Bank A4 (same-node stints), Part B fraud bursts.

## Conditional aggregation / pivot
```sql
COUNT(*) FILTER (WHERE pizza = 'Meatlovers') AS meatlovers,
SUM(amount) FILTER (WHERE txn_date >= start_date) AS in_window
```
`FILTER` is the Postgres form of `SUM(CASE WHEN ... THEN 1 END)`. Where: almost everywhere.

## Share of total
```sql
100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct
```
A window over the aggregate, so there's no second query. Where: Foodie-Fi B6, Part B Q5.

## Subtotals
```sql
GROUP BY ROLLUP (kyc_level, pays_bills)   -- adds per-kyc subtotals and a grand total (NULL keys)
```
Where: Part B Q4, Q13.

## Percentiles
```sql
PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY days)   -- interpolates; PERCENTILE_DISC picks a real value
```
Where: Data Bank A5, Part B Q13.

## Buckets and quantiles
```sql
NTILE(5) OVER (ORDER BY monetary, wallet_id)   -- quintiles
(days - 1) / 30                                 -- 30-day buckets: day 30 -> bucket 0, day 31 -> bucket 1
```
**Trap:** `NTILE` splits *equal* values arbitrarily. Always add a unique tiebreaker, or results change between runs.
A test in this repo caught exactly that. Where: Part B Q5, Foodie-Fi B10.

## Cleaning text that should be numbers / NULLs
```sql
NULLIF(NULLIF(extras, ''), 'null')                          -- '', 'null' -> NULL
string_to_array(x, ', ')::INTEGER[]                         -- '1, 5' -> {1,5}
NULLIF(regexp_replace(distance, '[^0-9.]', '', 'g'), '')::NUMERIC   -- '23.4 km' -> 23.4
```
Keep raw tables untouched and build `clean_` copies, so every fix can be checked. Where: Pizza Runner cleaning.sql.

## Arrays
```sql
cardinality(extras) > 0                              -- non-empty
topping_id = ANY (exclusions)                        -- membership
CROSS JOIN LATERAL unnest(extras) AS e(topping_id)   -- one row per element
```
Where: Pizza Runner, Part B promotions (`eligible_mcc`).

## Expanding rows with LATERAL
```sql
CROSS JOIN LATERAL generate_series(0, 12) AS n      -- one row per month of a subscription
(start_date + n * INTERVAL '1 month')::DATE         -- always from the ORIGINAL date
```
**Trap:** stepping a date by `'1 month'` repeatedly drifts (31 Jan → 29 Feb → 29 Mar). Multiply from the start date
instead. Where: Foodie-Fi payments.

## Recursion
```sql
WITH RECURSIVE walk AS (
    SELECT ... WHERE i = 1
    UNION ALL
    SELECT ... FROM walk w JOIN base b ON b.i = w.i + 1
) ...
```
Use it when each row depends on the previous row's *result*, which a window can't express (e.g. compound interest).
Where: Data Bank D2.

## Avoiding fan-out
Joining per-order data (distance) to per-pizza rows repeats each order's distance, once per pizza. Aggregate each grain
separately, then combine. Where: Pizza Runner D5, Part B v_promo_effect.

## Right-censoring in cohorts
A cohort that joined in Nov 2025 can't have a "month 6" yet. Show **NULL**, not 0%. Where: Part B Q3.

## Measuring an effect: difference-in-differences
```
uplift = (treated_after / treated_before) / (control_after / control_before)
```
The control group (non-eligible categories, same days) absorbs growth and seasonality. A plain before/after doesn't.
Where: Part B views.sql `v_promo_effect`.

## Indexes and EXPLAIN
```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
CREATE INDEX ON transactions (wallet_id, txn_ts);                                   -- equality col first, range second
CREATE INDEX ON transactions (counterparty_wallet_id, txn_ts) WHERE counterparty_wallet_id IS NOT NULL;  -- partial
CREATE INDEX ON transactions USING brin (txn_ts);                                   -- tiny, for append-only time data
```
- Read plans bottom-up. Compare *actual* rows with estimated rows; a big gap means stale stats (`ANALYZE`).
- `OR` across two columns can use **BitmapOr** if both columns are indexed.
- Indexes help **selective** queries. A query reading most of the table should seq-scan, and that's correct.

Where: Part B indexes.sql, explain/.
