# Case 3: Foodie-Fi

2 tables, 2,650 plan events, 1,000 subscribers. A subscription business. The skills are **customer journeys,
churn and building a billing table from business rules**.
Questions: [questions.md](questions.md) · Answers: [solutions.sql](solutions.sql)

## A. Sample journeys (in one line each)
| Customer | Journey |
|---|---|
| 1 | Trial → basic monthly after 7 days, and stays. |
| 2 | Trial → straight to pro annual. Highest-value path. |
| 11 | Trial → churned at the end of the trial. |
| 13 | Trial → basic → upgraded to pro monthly about 3 months later. |
| 15 | Trial → pro monthly → churned after one paid month. |
| 16 | Trial → basic → pro annual after about 4.5 months. |
| 18 | Trial → pro monthly, and stays. |
| 19 | Trial → pro monthly → pro annual after 2 months. |

## Key insights
- **The trial converts well:** 91% of customers pay after the trial. Only 9% (92) churn straight away.
- **Basic is the default choice:** 54.6% go to basic monthly after the trial, 32.5% to pro monthly, 3.7% straight to annual.
- **Churn still hurts:** 30.7% of customers (307) had churned by April 2021. By 31 Dec 2020, 23.6% had already left.
- **Annual takes time:** customers take 105 days on average to go annual. Most do it within 6 months, often in the first 30 days.
  An "annual discount at month 3" offer would target the peak.
- **No pro → basic downgrades in 2020.** Unhappy customers churn instead of downgrading, so a cheaper "save" plan
  offered at cancellation could keep some of them.
- **2020 billing:** 4,446 payments from 891 paying customers, **$100,555 revenue**. The paying base grew by a net 655,
  but churn rose in the second half (about 25–32 a month vs 9 in January).

## How the payments table works (C)
1. Number each customer's plans with `LAG`/`LEAD`, so every plan knows the previous plan and when the next one starts.
2. **Monthly plans:** `generate_series(0, 12)` month offsets from the start date, kept while before the next plan and inside 2020.
   I add `n * interval '1 month'` to the original date, so a plan started on the 31st doesn't drift to the 29th.
3. **Annual plans:** charged on the start date. Coming from pro monthly, the charge moves to the next monthly billing date (end of the current period).
4. **Upgrade from basic:** the first pro charge is reduced by $9.90 already paid (e.g. customer 16: $189.10).
5. Checked with queries: no duplicate charge dates, no payments on or after churn, no zero or negative amounts.

Assumption: the brief doesn't cover downgrades, so a downgrade starts on its own date with no refund. There are none in 2020 anyway.

## SQL concepts used
| Concept | Where |
|---|---|
| `LAG` / `LEAD` with a named `WINDOW` | A, B5, B6, B11, C |
| `DISTINCT ON` for "latest row per group" | B7 |
| `COUNT(...) FILTER`, `MIN(...) FILTER` | B4, B9, B10 |
| Share of total with `SUM(COUNT(*)) OVER ()` | B6, B7 |
| Bucketing with integer division | B10 |
| `CROSS JOIN LATERAL generate_series` to expand rows | C |
| Interval arithmetic and month-end behaviour | C |
| `CREATE TABLE AS` from a multi-CTE query | C |
| Running total (`SUM(...) OVER (ORDER BY month)`) | D |
