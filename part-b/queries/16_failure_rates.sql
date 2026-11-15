-- Q16. Failure rate by transaction type and channel, per quarter.
-- A rising failure rate in one channel is an early warning for payments operations.
SET search_path = ewallet;

SELECT TO_CHAR(DATE_TRUNC('quarter', txn_ts), 'YYYY-"Q"Q') AS quarter,
       txn_type, channel, COUNT(*) AS txns,
       ROUND(100.0 * AVG((status = 'failed')::INT), 2) AS failed_pct
FROM transactions
GROUP BY 1, txn_type, channel
HAVING COUNT(*) >= 500
ORDER BY quarter, txn_type, channel;
