# Case 4: Data Bank (fintech)

3 tables, 500 customers, 5,868 transactions (Jan–Apr 2020), 3,500 node assignments. A neo-bank whose cloud
storage allowance follows each customer's balance. This is the most fintech-like case, so I added data-quality checks, a
daily balance model and a written decision summary.
Questions: [questions.md](questions.md) · Answers: [solutions.sql](solutions.sql)

## Data quality findings (before any answer)
| Finding | Impact | What I did |
|---|---|---|
| `end_date = 9999-12-31` on 500 rows | A "current node" sentinel. It would add ~8,000 years to any average | Excluded from duration metrics |
| 607 rows re-assign a customer to **the same node** | Naive averages count non-moves as moves | Merged with gaps-and-islands. The average stay rises from 15.6 to **18.9 days** |
| `node_id` 1–5 repeats in every region | "5 unique nodes" is misleading | Report both: 5 ids, **25 physical (region, node) nodes** |
| 157 of 500 customers end January at ≤ $0 | % growth from a zero/negative base is meaningless | Excluded from B5(a) and reported the count |
| Months with no transactions | They disappear from a plain `GROUP BY` | Month and day spines carry balances forward |

## Key insights
- **Security story:** customers are moved to a different node every **~19 days** (median 18, 95th percentile 37–43).
  The pattern is the same in all 5 regions, so no region is a weak spot.
- **Australia is the biggest region** (110 customers), Europe the smallest (88).
- **Money flow:** $1.36M deposited against $1.60M purchased plus withdrawn. Outflows exceed deposits, so many accounts
  run negative (157 below $0 by end of January).
- **Engagement:** customers with 2+ deposits and some spending in a month grew from 168 (Jan) to 192 (Mar).
  April looks low (70) only because the data stops on 28 April.
- **Balance growth:** 34% of customers who started positive ended April more than 5% higher. 37% had at least one month
  with more than 5% growth.

## One-page summary for management: data allocation options
1 GB per $1 of positive balance. Negative balances get 0 GB.

| Month (2020) | Opt 1: last month-end | Opt 2: 30-day average | Opt 3: real time (peak) | Interest 6% simple | 6% daily compound |
|---|---:|---:|---:|---:|---:|
| Jan | n/a | n/a | 236,157 | 236,184 | 236,185 |
| Feb | 235,595 | 128,433 | 274,699 | 263,090 | 263,095 |
| Mar | 261,508 | 244,605 | 275,616 | 263,536 | 263,549 |
| Apr | 260,971 | 257,327 | 266,913 | 268,530 | 268,557 |

**Reading it:**
- **Real time is the most expensive to provision.** You must cover the busiest day, about 2–17% above Option 1 each month.
  It also means constant reallocation.
- **The 30-day average is the cheapest and smoothest.** Short spikes don't trigger extra storage. February is low only
  because the 30-day window still includes early January, before most customers had deposited. That is a start-up effect, not a real saving.
- **Previous month-end is simple and predictable,** but always one month behind.
- **Interest adds little:** 6% a year adds about 4,600 GB by April (≈1.7%). Daily compounding adds only ~27 GB more.
  It's a cheap loyalty feature.
- **Recommendation:** Option 2 for provisioning, plus the simple-interest bonus as a marketing hook. Re-check once data
  beyond April exists, since four months is a short window.

## Interview-worthy details
- **Gaps-and-islands (A4/A5):** `LAG` flags a node change, and a running `SUM` of the flags gives each unbroken run an id.
  Then `GROUP BY` that id. This is a standard pattern for sessionising events.
- **Window frames (C1):** with `ORDER BY txn_date`, the default `RANGE` frame gives every same-day transaction the
  end-of-day balance. `ROWS UNBOUNDED PRECEDING` plus a tiebreaker shows each step.
- **Rolling average (C3):** `ROWS BETWEEN 29 PRECEDING AND CURRENT ROW` over a *daily* spine. Over sparse transaction rows
  it would mean "last 30 transactions", not "last 30 days".
- **Why recursion for compounding (D2):** each day's balance depends on the previous day's result, and a window
  function can't refer to its own output. This query is the slowest in the case (a few seconds for 60,500 customer-days).

## SQL concepts used
| Concept | Where |
|---|---|
| Views to share logic (`v_txn`, `v_daily_balance`, `v_month_end`) | top, B4 |
| Gaps-and-islands with `LAG` + running `SUM` | A4, A5 |
| `PERCENTILE_CONT ... WITHIN GROUP` | A5 |
| Row-value `COUNT(DISTINCT (a, b))` | A1 |
| Date spines with `generate_series` + `CROSS JOIN` | views, B4 |
| `FILTER` aggregates, conditional pivots | B3, B5 |
| Window frames: `ROWS UNBOUNDED PRECEDING`, `ROWS BETWEEN 29 PRECEDING` | C1–C3 |
| `GREATEST` to floor negatives | C3, D |
| `WITH RECURSIVE` | D2 |
