WITH acc AS (
  SELECT d.account_id FROM accounts d, accounts p
  WHERE  p.account_id = :P81_ACCOUNT_ID
  AND    d.account_code LIKE p.account_code || '%' AND d.acc_level = 4
),
rows_ AS (
  SELECT j.journal_date, j.journal_no, t.name_ar jt_name, j.journal_id, c.name_ar company,
         l.description, j.currency_code, j.exchange_rate,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.debit_base  ELSE l.debit  END dr,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.credit_base ELSE l.credit END cr
  FROM   journals j
  JOIN   journal_lines l ON l.journal_id = j.journal_id
  JOIN   journal_types t ON t.jt_code    = j.jt_code
  JOIN   companies c     ON c.company_id = j.company_id
  WHERE  l.account_id IN (SELECT account_id FROM acc)
  AND    j.status IN ('POSTED','REVERSED')
  AND    (:P81_CURRENCY   IS NULL OR j.currency_code = :P81_CURRENCY)
  AND    (:P81_COMPANY_ID IS NULL OR j.company_id = :P81_COMPANY_ID)
  AND    (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID)
)
SELECT NULL AS "التاريخ", NULL AS "رقم القيد", 'رصيد سابق' AS "النوع", NULL AS "الشركة",
       NULL AS "البيان", NULL AS "العملة",
       GREATEST(SUM(dr - cr), 0) AS "مدين", GREATEST(SUM(cr - dr), 0) AS "دائن",
       SUM(dr - cr) AS "الرصيد", 0 AS sort_key
FROM   rows_ WHERE journal_date < TO_DATE(:P81_FROM,'DD/MM/YYYY')
UNION ALL
SELECT journal_date, journal_no, jt_name, company, description, currency_code,
       dr, cr,
       (SELECT NVL(SUM(dr - cr), 0) FROM rows_ WHERE journal_date < TO_DATE(:P81_FROM,'DD/MM/YYYY'))
       + SUM(dr - cr) OVER (ORDER BY journal_date, journal_id ROWS UNBOUNDED PRECEDING),
       1
FROM   rows_
WHERE  journal_date BETWEEN TO_DATE(:P81_FROM,'DD/MM/YYYY') AND TO_DATE(:P81_TO,'DD/MM/YYYY')
ORDER  BY sort_key, 1, 2
