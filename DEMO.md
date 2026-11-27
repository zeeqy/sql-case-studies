# Demo video script (60–90 s)

**Hook (on camera or over the dashboard, 5 s):**
"A cashback campaign looked like it doubled spending. Using only SQL, I showed about half of that lift was fake."

## Shots

1. **One command, real database (10 s)**
   *Screen:* terminal, `uv run sqlcases up`, Docker starting Postgres 16 and the seed log ending in `transactions=382,279`.
   *Say:* "One command starts Postgres in Docker and loads four SQL case studies plus a Malaysian e-wallet I simulated:
   8,000 users, 569 merchants, about 382 thousand ringgit transactions."

2. **Campaign uplift, naive vs difference-in-differences (20 s)**
   *Screen:* `part-b/queries` campaign query and its result in `part-b/results/`, naive vs DiD columns side by side.
   *Say:* "A naive before/after comparison overstates the campaigns by up to two times, because user growth and Raya
   seasonality ride along. Difference-in-differences compares against users who didn't get the promo, and lands at 1.24
   against a true 1.25. The worst campaign cost RM71 for every RM100 of extra spend."

3. **Fraud rule scored against the truth (15 s)**
   *Screen:* `part-b/eval/fraud_eval.sql` output: naive rule 65 wallets at 20% precision, combined rule 13 wallets at 100%.
   *Say:* "Flagging bursts of round transfers catches 65 wallets, but only 20% are mules. Adding 'money passed on within
   30 minutes' catches the 13 planted mules with no false alarms. I planted them, so I can actually measure it."

4. **Indexes are not magic (15 s)**
   *Screen:* `part-b/explain/summary.md` table.
   *Say:* "A wallet statement goes from 26.8 milliseconds to 0.2 with two indexes: 119 times faster. But a full-history
   aggregate stays at 80 milliseconds, because a sequential scan was already the right plan."

5. **Dashboard (10 s)**
   *Screen:* Streamlit app: MAU chart, RFM segments, the "view SQL" expanders.
   *Say:* "The dashboard runs off a 108 KB parquet snapshot, so it's free to host. Champions are 23% of wallets but
   57% of spend."

6. **Tests and CI (8 s)**
   *Screen:* `uv run pytest -q` ending in `46 passed`, then the green GitHub Actions badge.
   *Say:* "46 tests run every query against Postgres 16 on each push, and CI fails if the saved results go stale."

**Closing line (5 s):**
"The data is synthetic, and I say so. The point is that every answer here is checked, not just run.
Repo: github.com/zeeqy/sql-case-studies."
