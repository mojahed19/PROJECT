WITH mv AS (   -- الحركات المرحّلة بالعملة الأساسية
  SELECT j.company_id, l.account_id,
         CASE WHEN j.journal_date <  TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.debit_base - l.credit_base ELSE 0 END AS open_bal,
         CASE WHEN j.journal_date >= TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.debit_base  ELSE 0 END AS dr,
         CASE WHEN j.journal_date >= TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.credit_base ELSE 0 END AS cr
  FROM   journals j
  JOIN   journal_lines l ON l.journal_id = j.journal_id
  WHERE  j.status IN ('POSTED','REVERSED')
  AND    j.journal_date <= TO_DATE(:P80_TO,'DD/MM/YYYY')
  AND    (:P80_COMPANY_ID IS NULL OR j.company_id = :P80_COMPANY_ID)
  AND    (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
          OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
  AND    (NVL(:P80_EXCLUDE_INTERCO,'N') = 'N' OR l.partner_company_id IS NULL)
),
leaf AS (
  SELECT CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END AS company_id,
         a.account_code, SUM(open_bal) open_bal, SUM(dr) dr, SUM(cr) cr
  FROM   mv JOIN accounts a ON a.account_id = mv.account_id
  GROUP  BY CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END, a.account_code
)
SELECT c.name_ar                                       AS "الشركة",
       p.account_code                                  AS "رقم الحساب",
       p.name_ar                                       AS "اسم الحساب",
       SUM(CASE WHEN leaf.open_bal > 0 THEN leaf.open_bal ELSE 0 END) AS "رصيد أول مدين",
       SUM(CASE WHEN leaf.open_bal < 0 THEN -leaf.open_bal ELSE 0 END) AS "رصيد أول دائن",
       SUM(leaf.dr)                                    AS "حركة مدين",
       SUM(leaf.cr)                                    AS "حركة دائن",
       GREATEST(SUM(leaf.open_bal + leaf.dr - leaf.cr), 0)  AS "رصيد آخر مدين",
       GREATEST(-SUM(leaf.open_bal + leaf.dr - leaf.cr), 0) AS "رصيد آخر دائن"
FROM   accounts p
JOIN   leaf ON leaf.account_code LIKE p.account_code || '%'
LEFT JOIN companies c ON c.company_id = leaf.company_id
WHERE  p.acc_level = :P80_LEVEL
GROUP  BY c.name_ar, p.account_code, p.name_ar
HAVING SUM(ABS(leaf.open_bal)) + SUM(leaf.dr) + SUM(leaf.cr) <> 0
ORDER  BY c.name_ar, p.account_code
