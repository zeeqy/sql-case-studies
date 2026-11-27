# LEARN.md: defending sql-case-studies in an interview

## 1. What it does (3 sentences)
It answers four classic SQL practice cases (a diner, a pizza delivery start-up, a streaming subscription and a digital bank)
in PostgreSQL, with my own solutions and a short write-up of insights for each. It then adds a case I built: a synthetic
Malaysian e-wallet with 18 business questions, including whether cashback campaigns worked, a fraud-lite rule, and an
indexing benchmark. Everything loads with one command, every query is tested in CI, and a Streamlit dashboard shows the results.

## 2. Major decisions
| Decision | Chosen | Alternative | Why |
|---|---|---|---|
| Database | PostgreSQL 16 in Docker | SQLite / DuckDB | What most analyst jobs and tests use. Has window functions, `FILTER`, `DISTINCT ON`, arrays, BRIN and real `EXPLAIN ANALYZE`. Docker makes it one command. |
| Host port | 54432 (env `DB_PORT`) | 5432, or 55432 | 5432 clashes with a local Postgres or Supabase; 55432 fell inside a Windows-reserved port range on my laptop, so the port is now an env var. |
| One schema per case | `dannys_diner`, `ewallet`, ... | one shared schema | Cases can't collide, and `reset` drops and reloads one case cleanly. |
| Pizza Runner cleaning | new `clean_` tables | `UPDATE` the raw tables | Raw data stays as evidence, so every fix can be checked against it. |
| Part B data | seeded simulation with planted patterns | a public dataset | No public Malaysian e-wallet transaction data exists. Planting known answers means I can *measure* whether a query works, not just run it. |
| Faker | dropped; curated Malaysian name lists | Faker | Faker has no `ms_MY` locale, and its generic names would look out of place. |
| Ground truth | separate `ewallet_truth` schema | flags in the main tables | Analysis queries physically can't peek at the answers. Only `eval/` and tests read it. |
| Loading | `COPY` | `INSERT` | 382k rows in seconds instead of minutes. |
| Money in the generator | integer sen | floats | No rounding drift, so balances provably never go negative. |
| Campaign uplift | difference-in-differences | before/after | Before/after includes user growth and Raya seasonality, so it overstated effects by up to 2×. |
| Fraud rule | burst + round amounts + fast cash-out | any single signal | Group collections (kutu, shared meals) look like bursts too. Only the cash-out separates them. |
| Indexes | composite B-tree, partial, BRIN | index everything | Each one matches a real access pattern. The full-scan example shows when indexes don't help. |
| Dashboard data | parquet snapshot of the query outputs | live DB connection | Free hosting (Streamlit Cloud) can't run Postgres. The snapshot is 108 KB, and a test proves it equals a fresh run. |
| CI | Postgres service + full suite + output-drift check | lint only | Every query is executed on every push, and stale committed results fail the build. |

## 3. Concepts I must understand
- **Window functions** (`RANK`, `LAG`, running `SUM`): compute across related rows without collapsing them. Unlike `GROUP BY`,
  every row stays. *Data Bank, Foodie-Fi, Part B Q1/Q8.*
- **`RANGE` vs `ROWS` frame:** with `ORDER BY date`, the default `RANGE` frame treats same-date rows as one peer group,
  so they share a total. `ROWS` steps row by row. *part-a/04-data-bank/solutions.sql C1.*
- **Gaps-and-islands:** flag where a new group starts with `LAG`, take a running `SUM` of the flags to get a group id,
  then `GROUP BY` it. *Data Bank A4, part-b/views.sql v_p2p_bursts.*
- **Date spine:** `generate_series` + `CROSS JOIN` gives one row per entity per day/month, so silent periods don't vanish.
  *Data Bank v_month_end, v_daily_balance.*
- **Right-censoring:** you can't observe month 12 for a cohort that joined last month. Show NULL, not 0%.
  *part-b/queries/03_retention_cohorts.sql.*
- **Difference-in-differences:** (treated after/before) ÷ (control after/before). Shared shocks cancel. Its assumption: both
  groups would have moved in parallel without the campaign. *part-b/views.sql v_promo_effect.*
- **Precision and recall:** precision = flagged that are real / all flagged; recall = real ones caught / all real.
  The naive rule had 100% recall but 20% precision. *part-b/eval/fraud_eval.sql.*
- **RFM + `NTILE`:** score recency, frequency and monetary into quintiles. `NTILE` needs a unique tiebreaker or the
  results aren't deterministic. *part-b/queries/05_rfm_segments.sql.*
- **B-tree vs BRIN vs partial index:** a B-tree finds exact rows. BRIN stores min/max per block range, so it is tiny and great
  for time-ordered data. A partial index only covers rows matching a `WHERE`. *part-b/indexes.sql.*
- **Reading `EXPLAIN ANALYZE`:** bottom-up. Look at the scan type, actual vs estimated rows, and time. BitmapOr = two indexes
  combined for an `OR`. *part-b/explain/.*
- **Fan-out:** joining a one-row-per-order fact to many rows per order duplicates it. Aggregate each grain first.
  *Pizza Runner D5.*
- **Recursive CTE:** for row-by-row dependencies a window can't express (compound interest). *Data Bank D2.*

## 4. Interview questions and honest answers
1. **Why build your own dataset instead of using a real one?**
   There's no public Malaysian e-wallet transaction data. Synthetic data let me plant known effects, so I could check that my
   campaign and fraud queries actually find them. The trade-off is that the findings say nothing about real users. I say that up front.
2. **How do you know the campaign estimates are right?**
   The generator stores the true uplift. Difference-in-differences lands within about 0.15 of it for 3 of 4 targeted campaigns.
   It underestimates the 5-day 11.11 sale (1.75 vs 2.20) because the window is short and noisy. In real life I'd use a holdout group
   and report confidence intervals.
3. **What's difference-in-differences, in one sentence?**
   Compare how much the treated group changed against how much a similar untreated group changed over the same period, so
   anything that hit both (growth, Raya) cancels out.
4. **Your fraud rule has 100% precision. Isn't that suspicious?**
   Yes, because I planted the pattern. The real lesson is the comparison: a single signal gave 20% precision, and adding the
   cash-out signal removed the look-alike decoys. Real mules adapt, so a rule like this needs labelled cases and monitoring.
5. **When would an index not help?**
   When the query reads most of the table. My full-history aggregate ran at 80 ms with or without indexes, and a sequential scan was
   already optimal. Indexes also slow down writes and take space.
6. **Why BRIN on the timestamp?**
   Rows are inserted in time order, so each block covers a narrow time range. BRIN stores just min/max per block range: 24 kB
   vs 12 MB for a B-tree, and it still cut the last-7-days query from 25 ms to 5 ms.
7. **What was the messiest data problem?**
   Pizza Runner: `'null'` as text, empty strings, units inside numbers ("20km", "15 minute") and no primary key. I built clean
   copies with `NULLIF`, `regexp_replace` and arrays, and kept the raw tables for comparison.
8. **What's a data-quality issue you caught that changed an answer?**
   Data Bank had 607 node "reallocations" to the same node. Merging them with gaps-and-islands raised the average stay from
   15.6 to 18.9 days. Also, a reproducibility test showed my RFM segments changed between runs because `NTILE` splits ties
   arbitrarily. I fixed it with a tiebreaker.
9. **How is this tested?**
   CI starts Postgres 16, loads everything, and runs 46 tests: every solution and query, key answers, generator invariants
   (balances never negative, reproducible seed), the fraud and uplift checks against the truth, and the dashboard. It also fails if the
   committed outputs differ from a fresh run.
10. **What would you do with real data?**
    Validate against finance totals first, set up a holdout for campaigns, partition transactions by month, move repeated logic
    into dbt models, and add alerting on failure rates (Q16) and mule bursts (Q11).

## 5. What is weak, and how to say it
- **Synthetic Part B.** "The data is simulated from my own assumptions, so the numbers show the method, not real behaviour.
  The upside is that I could check my queries against a known truth."
- **Fraud rule tuned on planted data.** "100% only says the SQL finds what I planted. In production I'd measure it on
  investigated cases and expect much lower precision."
- **One seed, no confidence intervals.** "Campaign estimates are point estimates. A bootstrap or multiple seeds would show the
  spread. 11.11 shows why that matters."
- **Small scale.** "About 382k rows; real wallets have billions. The index lessons hold, but I'd add partitioning and look at
  query plans at scale."
- **Part A is popular practice material.** "Many people have solved these. Mine adds cleaning layers, data-quality findings and
  tests, and I can explain every query."
- **ROI assumes a 1% MDR.** "That's a stated assumption. With real fee and margin data the ROI numbers would change, but the
  ranking of campaigns by cost per incremental RM100 is the fairer comparison anyway."

## 6. Resume bullets
- **[data]** Wrote 18 PostgreSQL analyses (cohort retention, RFM, merchant mix, activation funnel) on a 382k-transaction
  Malaysian e-wallet dataset; found that 23% of users drive 57% of spend and that full-KYC bill payers churn 34 points
  less than basic-KYC non-payers.
- **[data]** Measured 6 cashback campaigns with difference-in-differences in SQL, showing naive before/after overstated
  uplift by up to 2× and identifying a campaign that cost RM71 per RM100 of extra spend.
- **[data/SWE]** Built a fraud-lite SQL rule (gaps-and-islands bursts + cash-out timing) that raised precision from 20% to
  100% on planted mule accounts, and cut a wallet-statement query from 26.8 ms to 0.2 ms with composite, partial and BRIN indexes.
- **[SWE]** Packaged 4 SQL case studies and a seeded data generator into a one-command Docker + uv project with 45 pytest
  checks running every query against Postgres 16 in GitHub Actions.
- **[data]** Built a Streamlit dashboard served from a 108 KB parquet snapshot of the query outputs, with each chart linked to
  its SQL, deployable on a free tier with no database.
