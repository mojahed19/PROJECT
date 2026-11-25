WITH mv AS (
  SELECT j.company_id, c.name_ar company, j.journal_date, a.acc_type, a.account_code, a.cash_bank,
         l.debit_base - l.credit_base AS bal, l.partner_company_id
  FROM journals j
  JOIN journal_lines l ON l.journal_id = j.journal_id
  JOIN accounts a ON a.account_id = l.account_id
  JOIN companies c ON c.company_id = j.company_id
  WHERE j.status IN ('POSTED','REVERSED') AND j.source_type <> 'CLOSING'   -- قيد الإقفال لا يدخل في الأرباح
  AND (:P1_COMPANY_ID IS NULL OR j.company_id = :P1_COMPANY_ID)
  AND (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID)
  AND (NVL(:P1_MODE,'SEP') = 'SEP' OR l.partner_company_id IS NULL)
)
SELECT 'المبيعات' AS "البيان",
       TO_CHAR(-SUM(CASE WHEN account_code LIKE '41%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990') AS "القيمة"
FROM mv
UNION ALL
SELECT 'تكلفة المبيعات',
       TO_CHAR(SUM(CASE WHEN account_code LIKE '51%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'المصروفات',
       TO_CHAR(SUM(CASE WHEN account_code LIKE '52%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'صافي الربح',
       TO_CHAR(-SUM(CASE WHEN acc_type IN ('REV','EXP') AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'النقدية والبنوك', TO_CHAR(SUM(CASE WHEN cash_bank IN ('C','B') THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'ذمم العملاء', TO_CHAR(SUM(CASE WHEN account_code LIKE '1106%' THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'قيمة المخزون', TO_CHAR((SELECT ROUND(SUM(qty_base * avg_cost)) FROM v_stock_balance
                                WHERE :P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID), 'FM999G999G999G990')
FROM dual
