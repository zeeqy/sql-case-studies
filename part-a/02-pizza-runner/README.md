# Case 2: Pizza Runner

6 tables, 14 pizzas over 10 orders, 4 runners. This case is mostly about **cleaning dirty data** before any analysis.
Questions: [questions.md](questions.md) · Cleaning: [cleaning.sql](cleaning.sql) · Answers: [solutions.sql](solutions.sql)

## Cleaning (the main lesson)
| Raw problem | Fix |
|---|---|
| `''`, `'null'` (text) and `NULL` all mean "none" | `NULLIF` twice, then `COALESCE` to an empty array |
| Topping lists stored as text `'1, 5'` | `string_to_array(...)::INTEGER[]` |
| No primary key; order 4 has two identical rows | New table with an `item_id` identity column |
| `distance` = `'20km'`, `'23.4 km'`, `'10'` | `regexp_replace` to digits, cast to `NUMERIC` |
| `duration` = `'32 minutes'`, `'20 mins'`, `'40'` | `regexp_replace`, cast to `INTEGER` |
| Recipes as a comma list | `unnest` to one row per (pizza, topping) |

The raw tables stay untouched. Clean copies sit next to them, so every fix can be checked.

## Key insights
- **8 of 10 orders were delivered**, 12 of 14 pizzas. Runner 1 delivered all 4 of theirs. Runner 3 managed 1 of 2.
- **Meat Lovers dominates:** 9 of 12 delivered pizzas, and $138 of revenue before costs.
- **Prep time grows with order size:** about 12 minutes for 1 pizza, 18 for 2, 29 for 3 (≈10 min per pizza).
  The kitchen, not the runners, sets most of the wait.
- **Runner 2's speed is suspect:** from 35 to 94 km/h on similar ~23 km trips. 94 km/h is unlikely for a delivery rider,
  so I'd check the data first rather than praise the runner.
- **Bacon is the most added extra and cheese the most removed.** That's useful when the menu is next updated.
- **Paying runners $0.30/km takes about a third of revenue** ($43.56 of $138), leaving $94.44 before ingredients and other costs.

## Assumptions and data notes
- "Ordered" questions include cancelled orders. "Delivered" questions exclude them.
- Runner sign-up dates (2021) come *after* the orders (2020). That is a known quirk of the dataset, and I left it as is.
- The ratings in D3 are my own made-up values, as the case asks. They are not real data.
- The bonus DML runs in a `BEGIN … ROLLBACK` block, so re-running the file never changes the dataset.

## SQL concepts used
| Concept | Where |
|---|---|
| `NULLIF`, `COALESCE`, `regexp_replace`, casts | cleaning.sql |
| Arrays: `string_to_array`, `cardinality`, `= ANY`, `unnest` | cleaning.sql, A7, C2–C6 |
| `CROSS JOIN LATERAL unnest(...)` | C2, C3, C5, C6 |
| `COUNT(*) FILTER (WHERE ...)` (pivot) | A5, A7 |
| `EXTRACT(EPOCH/HOUR/ISODOW)`, interval maths | A9, A10, B2, B3 |
| Window `AVG() OVER (PARTITION BY ...)` | B6 |
| `UNION ALL` to build a bag of ingredients | C5, C6 |
| DDL with `PRIMARY KEY`, `REFERENCES`, `CHECK` | D3 |
| Avoiding fan-out when combining per-pizza and per-order numbers | D5 |
| Transactions (`BEGIN` / `ROLLBACK`) | E |
