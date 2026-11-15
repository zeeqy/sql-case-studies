-- Q12. Why "round amount" alone is a weak fraud signal: how common round P2P amounts are
-- for everyone, by amount band.
SET search_path = ewallet;

SELECT CASE WHEN amount < 20  THEN '1: below RM20'
            WHEN amount < 100 THEN '2: RM20-99'
            WHEN amount < 500 THEN '3: RM100-499'
            ELSE                   '4: RM500+' END AS band,
       COUNT(*) AS transfers,
       ROUND(100.0 * AVG((amount % 10 = 0)::INT), 1)  AS round_10_pct,
       ROUND(100.0 * AVG((amount % 100 = 0)::INT), 1) AS round_100_pct
FROM transactions
WHERE txn_type = 'p2p' AND status = 'success'
GROUP BY band
ORDER BY band;
