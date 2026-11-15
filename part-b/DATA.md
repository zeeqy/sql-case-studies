# Part B data: synthetic Malaysian e-wallet ("DompetKu")

**All of this data is synthetic.** A seeded Python simulation generates it ([src/sqlcases/generator](../src/sqlcases/generator)).
No real people, merchants or transactions are included. The same seed always gives the same rows, so every number in Part B can be reproduced.

| Table | Rows (seed 42) | What it holds |
|---|---:|---|
| `users` | 8,000 | name (built from common name parts), state, age band, KYC level, signup time |
| `wallets` | 8,000 | one per user, `wallet_id = user_id + 100000`, lite/premium tier |
| `merchants` | 569 | 13 merchant categories with ISO 18245 MCC codes. Ride-hailing and transit are `National` |
| `promotions` | 6 | cashback campaigns with % rate, per-transaction cap and budget |
| `transactions` | ~382k | top-up, P2P transfer, merchant payment, bill pay. Jan 2024 to Dec 2025, MYT |

## How it's simulated
- **Signups** grow over the two years, with extra signups during the two Raya campaigns. State shares follow DOSM population, weighted towards urban e-wallet use.
- **Retention:** a share of users try the app and leave within days. More of them are basic-KYC. The rest churn about 5–7% a month.
- **Spending:** each user has an activity level (lognormal) and their own category preferences. Spending peaks at lunch and dinner and around Hari Raya, 11.11 and December. About 80% of payments go to merchants in the user's home state.
- **Balances:** events are replayed in time order. When a payment would overdraw a wallet, a top-up is added before it: just in time (minutes before) or planned (1–72 hours before, a bigger round amount). Rural states use cash counters more. About 2% of top-ups fail first and are retried. Balances never go negative, and a test checks this.
- **Friendships are two-way,** so P2P relationships can be reciprocal.

## Planted patterns (what Part B's queries should find)
| Pattern | Planted as |
|---|---|
| Category trends | Public transport share grows fastest, ride-hailing grows, petrol declines |
| Campaign effects | Each promotion has a hidden true uplift (1.03× to 2.2×). "Fast Food Frenzy" is a deliberate dud |
| Fraud-lite mules | 13 wallets get bursts of 6–15 round-amount P2P transfers in under 30 minutes, then send the money on within 15 minutes |
| Decoys | Group collections (shared meals, *kutu* savings circles): many small round transfers arrive quickly, but the money stays |

The real answers sit in a separate schema, `ewallet_truth`. Analysis queries never read it. Tests use it to measure whether a query finds what was planted.

## Known limits
- Behaviour comes from my assumptions (see [config.py](../src/sqlcases/generator/config.py)), not real customer data.
  The findings show the SQL works, not how Malaysians actually use e-wallets.
- The before/after view of a promotion is deliberately confounded by growth and seasonality, as in real life.
