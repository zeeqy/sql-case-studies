-- Q15. When do people pay? Merchant payments by hour and weekday (a heatmap as a table).
-- ISODOW: 1 = Monday ... 7 = Sunday.
SET search_path = ewallet;

SELECT EXTRACT(HOUR FROM txn_ts)::INT AS hour,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 1) AS mon,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 2) AS tue,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 3) AS wed,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 4) AS thu,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 5) AS fri,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 6) AS sat,
       COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM txn_ts) = 7) AS sun,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all
FROM v_merchant_txn
GROUP BY hour
ORDER BY hour;
