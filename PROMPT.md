# 01 SQL Case Studies

Prove the number one data analyst skill: SQL. Recruiters and technical tests focus on this.
Tracks shown: data analysis.

## Setup
- PostgreSQL in Docker Compose (+ pgAdmin or just psql). One `make up` / script to start and seed everything.

## Part A: 8 Week SQL Challenge (Danny Ma)
- Cases 1 to 4 (Danny's Diner, Pizza Runner, Foodie-Fi, Data Bank). Data Bank is fintech-flavoured, give it extra polish.
- Per case folder: `schema.sql`, `questions.md`, `solutions.sql` (one query per question, commented), `README.md` with key insights and which SQL concepts were used.
- Do not copy published solutions. Write your own and explain the approach.

## Part B: Custom fintech case (the standout part)
Generate a realistic synthetic Malaysian e-wallet dataset with a Python script (Faker, seeded for reproducibility):
users, wallets, transactions (top-up, P2P transfer, merchant payment, bill pay), merchants (MCC categories), promotions/cashback.
Answer 15+ business questions, e.g.:
- Monthly active users and retention cohorts
- RFM segmentation of users
- Cashback campaign ROI
- Merchant category growth, top merchants by state
- Suspicious patterns (rapid transfers, round amounts) as a fraud-lite query
Use CTEs, window functions, date bucketing, CASE, indexes. Include an `EXPLAIN ANALYZE` before/after indexing example.

## Extras
- A small dashboard (Metabase in Docker or Streamlit) on top of Part B.
- `CHEATSHEET.md`: SQL patterns used, for interview revision.
