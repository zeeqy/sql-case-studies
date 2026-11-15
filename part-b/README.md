# Part B: DompetKu, a Malaysian e-wallet case (custom)

18 business questions over a **synthetic** e-wallet: 8,000 users, 569 merchants, 6 cashback campaigns and about 382k
transactions (Jan 2024–Dec 2025, MYR, Malaysia time). How the data is made, and which patterns were planted: [DATA.md](DATA.md).
Questions: [questions.md](questions.md) · SQL: [queries/](queries/) · Outputs: [results/](results/) · Shared logic: [views.sql](views.sql)

```bash
uv run sqlcases up        # start Postgres, load Part A + generate Part B (~1 min)
uv run sqlcases results   # run all 18 queries, write results/*.txt
uv run sqlcases explain   # EXPLAIN ANALYZE before/after indexes
```

## Headline findings
| # | Finding |
|---|---|
| 1 | MAU grew from 100 to **3,067**. Growth slowed from 50–120% a month at launch to about 4%. Stickiness (DAU/MAU) settled around **22%**. |
| 3 | About two thirds of new users are active again the next month, and **~30% after a year**. Most of the loss happens in the first month. Recent cohorts are shown as blank, not 0%, because they can't be observed yet. |
| 4 | 62.5% of wallets older than two months have churned. **Full-KYC bill payers churn least (41%), basic-KYC non-payers most (74%).** |
| 5 | **Champions are 23% of wallets but 57% of spend.** "At risk" users (lapsed, but used to be frequent) hold 16% of spend. They are the obvious win-back target. |
| 6–7 | Public transport is the fastest-growing category (+48% share, +286% GMV). Petrol and clothing lose share. Growth is almost all **more transactions**: average tickets moved only 0–4%. |
| 8 | Big-ticket merchants top most states (electronics in 7 of 16). The #1 merchant takes 12–24% of GMV in the large states but 48–100% in Perlis, Labuan and Putrajaya, where we have only a handful of merchants. That's a coverage gap. |
| 9–10 | Naive before/after comparisons **overstate campaign effects up to 2×**. All six campaigns lose money on MDR alone. "Fast Food Frenzy" costs **RM71 per RM100 of extra spend**, and 90% of its cashback went on spend that would have happened anyway. |
| 11 | The full mule rule flags **13 wallets with 100% precision**. The naive "burst of round transfers" rule flags 65 (20% precision). |
| 12 | 52–55% of everyday P2P under RM100 is already a round RM10 multiple, so "round" alone means little. |
| 13 | Full-KYC signups activate better: 88% pay at least once and 72% return the next month, vs 79% and 57% for basic. |
| 14 | Rural states reload at cash counters about 30% of the time vs 6% in the cities. About 56% of top-ups are "just in time" (a payment follows within 30 minutes). |
| 15 | Payments peak at 12:00 and 19:00. Weekdays and weekends look almost the same. |
| 16 | Failure rates are steady at about 1.5% (top-ups about 1.9%), with no channel drifting. |
| 17 | Bill payers spend twice as much per active month (RM383 vs RM186) and stay longer. **This is correlation, not proof:** 62% of them are full-KYC. |
| 18 | 29% of P2P relationships go both ways. 37% of P2P money crosses state lines. |

## Campaign measurement (Q9–Q10)
A campaign's before/after jump mixes three things: the campaign, user growth, and seasonality (Raya, 11.11, December).
I estimate the uplift three ways and compare against the true uplift planted in the generator:

| Campaign | Naive | Per user | DiD | **True** |
|---|---:|---:|---:|---:|
| Raya Cashback 2024 (all categories) | 2.65 | 1.69 | n/a | 1.35 |
| Grocery Saver July | 1.37 | 1.15 | **1.24** | 1.25 |
| 11.11 Mega Sale | 2.07 | 1.95 | 1.75 | 2.20 |
| Transit Rewards | 2.04 | 1.65 | **1.47** | 1.60 |
| Raya Cashback 2025 (all categories) | 1.45 | **1.32** | n/a | 1.30 |
| Fast Food Frenzy | 1.16 | 1.09 | **1.11** | 1.03 |

- **Difference-in-differences** compares eligible categories with non-eligible ones over the same two periods. Whatever moves both (growth, Raya, payday) cancels out.
  It is the best estimate for 3 of the 4 targeted campaigns.
- **Where it misses:** on the 5-day 11.11 sale it underestimates (1.75 vs 2.20). There are only 5 days of mostly high-ticket electronics, so the numbers are noisy.
  A real analysis should report a confidence interval, or use a holdout group.
- **All-category campaigns have no control group.** The per-user ratio removes growth but not seasonality, so Raya 2024 still looks too good (1.69 vs 1.35).
  The honest fix is a randomised holdout: keep 5–10% of users out of the campaign.
- **ROI assumes a 1.0% merchant discount rate.** No campaign pays for itself on fees. That's normal: cashback is bought for acquisition and habit.
  Cost per RM100 of extra spend (RM16–71) is the fairer number to compare campaigns on.

## Fraud-lite (Q11–Q12)
Mules are planted in the generator, along with **decoys**: group collections (shared meals, *kutu* savings circles) that also bring many round transfers in quickly.
Scored in [eval/fraud_eval.sql](eval/fraud_eval.sql), the only file that reads the planted truth:

| Rule | Flagged | Mules found | Precision | Recall |
|---|---:|---:|---:|---:|
| Naive: burst of 5+ round transfers from 5+ senders | 65 | 13 / 13 | 20% | 100% |
| Full: burst **and** 70%+ passed on within 30 min | 13 | 13 / 13 | **100%** | 100% |

How to say this honestly: 100% is only possible because I wrote the pattern into the data. Real mule networks adapt
(smaller amounts, longer delays, chains of wallets). The point of this exercise is that **combining signals beats any
single one**, and that a rule must be measured against labelled cases before anyone trusts it.

## Indexing: EXPLAIN ANALYZE before/after
`uv run sqlcases explain` drops the indexes in [indexes.sql](indexes.sql), times 3 queries (best of 5 runs), recreates
the indexes and times them again. Full plans: [explain/before.txt](explain/before.txt), [explain/after.txt](explain/after.txt).

| Query | Before | After | Why |
|---|---:|---:|---|
| One wallet's Q4 statement (money in + out) | 26.8 ms | 0.2 ms | Seq scan of ~382k rows → **BitmapOr** of two B-tree index scans |
| Merchant GMV, last 7 days | 25.5 ms | 4.7 ms | **BRIN** on `txn_ts` skips all but the last block ranges (rows are stored in time order) |
| Merchant GMV, all history | 79.7 ms | 80.7 ms | Reads most of the table either way. A seq scan is right, and **indexes don't help** |

The BRIN index is **24 kB**, against **12 MB** for the `(wallet_id, txn_ts)` B-tree on a 37 MB table. The counterparty index is
**partial** (`WHERE counterparty_wallet_id IS NOT NULL`), so it only stores P2P rows. Timings are from my laptop and will vary.

## SQL concepts used
| Concept | Where |
|---|---|
| Views to keep business rules in one place | views.sql |
| CTE chains, `FILTER`, `ROLLUP` | most queries, Q4, Q13 |
| Window functions: `LAG`, running `SUM`, `NTILE`, `RANK`, share of total | Q1, Q2, Q5, Q8, Q11 |
| Gaps-and-islands (sessionising P2P bursts) | views.sql (`v_p2p_bursts`) |
| Cohort matrix with right-censoring | Q3 |
| Difference-in-differences in SQL | views.sql (`v_promo_effect`) |
| `CROSS JOIN LATERAL`, correlated `EXISTS` | views.sql, Q14 |
| Self-join for reciprocity | Q18 |
| `PERCENTILE_CONT ... WITHIN GROUP` | Q13 |
| B-tree (composite), partial and BRIN indexes, `EXPLAIN (ANALYZE, BUFFERS)` | indexes.sql, explain/ |

## Limitations
- **Synthetic data:** the findings show the SQL and the method work. They don't describe how Malaysians actually use e-wallets.
- One generator seed, so there are no confidence intervals on the campaign estimates.
- About 382k transactions is small for "performance" work. The index lessons hold, but at production scale you would also look at partitioning by month.
