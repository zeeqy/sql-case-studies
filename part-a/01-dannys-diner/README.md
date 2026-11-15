# Case 1: Danny's Diner

3 tables, 15 sales, 3 customers, January 2021. A warm-up case on joins, aggregation and ranking.
Questions: [questions.md](questions.md) · Answers: [solutions.sql](solutions.sql)

## Key insights
- **Ramen is the best seller** (8 of 15 sales) and the favourite of A and C. B buys all three items equally (2 each).
- **B visits most often** (6 days) but **A spends most** ($76 vs B $74, C $36). A buys more per visit.
- **C is not a member** and has spent the least ($36, 2 visits). C is the clearest target for a sign-up offer.
- **Joining changes little for B:** B bought sushi just before joining and again right after. A switched from curry/sushi to ramen.
- **The first-week double-points promo favours early, frequent members:** A ends January with 1,370 points against B's 820, because A bought more during their first week.

## Assumptions
- An order on the join date counts as a member purchase (Q6, Q10).
- Orders have no time of day, so same-day items are ties. I keep every tied item with `DENSE_RANK` instead of picking one at random.
- Points are earned on every purchase, before and after joining (Q9, Q10).

## SQL concepts used
| Concept | Where |
|---|---|
| `JOIN ... USING`, `GROUP BY`, `SUM`, `COUNT(DISTINCT)` | Q1, Q2, Q8 |
| CTE + `DENSE_RANK() OVER (PARTITION BY ... ORDER BY ...)` | Q3, Q5, Q6, Q7 |
| Window function over an aggregate (`ORDER BY COUNT(*)`) | Q5 |
| `CASE` inside `SUM` (conditional aggregation) | Q9, Q10 |
| Date arithmetic (`join_date + 6`) and `BETWEEN` | Q10 |
| `LEFT JOIN` to keep non-members, `STRING_AGG` for ties | Q3, Bonus |
