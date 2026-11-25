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
SELECT TO_CHAR(journal_date, 'MM') AS "الشهر",
       -SUM(CASE WHEN acc_type = 'REV' THEN bal END) AS "الإيرادات",
        SUM(CASE WHEN acc_type = 'EXP' THEN bal END) AS "المصروفات",
       -SUM(CASE WHEN acc_type IN ('REV','EXP') THEN bal END) AS "صافي الربح"
FROM mv
WHERE EXTRACT(YEAR FROM journal_date) = :P1_YEAR
GROUP BY TO_CHAR(journal_date, 'MM')
ORDER BY 1
