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
  AND    (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID
          OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
  AND    (NVL(:P80_EXCLUDE_INTERCO,'N') = 'N' OR l.partner_company_id IS NULL)
),
leaf AS (
  SELECT CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END AS company_id,
         a.account_code, SUM(open_bal) open_bal, SUM(dr) dr, SUM(cr) cr
  FROM   mv JOIN accounts a ON a.account_id = mv.account_id
  GROUP  BY CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END, a.account_code
),
tb AS (
  SELECT c.name_ar company, p.account_code, p.name_ar,
         SUM(CASE WHEN leaf.open_bal > 0 THEN leaf.open_bal ELSE 0 END)   ob_dr,
         SUM(CASE WHEN leaf.open_bal < 0 THEN -leaf.open_bal ELSE 0 END)  ob_cr,
         SUM(leaf.dr) mv_dr, SUM(leaf.cr) mv_cr,
         GREATEST(SUM(leaf.open_bal + leaf.dr - leaf.cr), 0)  cb_dr,
         GREATEST(-SUM(leaf.open_bal + leaf.dr - leaf.cr), 0) cb_cr
  FROM   accounts p
  JOIN   leaf ON leaf.account_code LIKE p.account_code || '%'
  LEFT JOIN companies c ON c.company_id = leaf.company_id
  WHERE  p.acc_level = :P80_LEVEL
  GROUP  BY c.name_ar, p.account_code, p.name_ar
  HAVING SUM(ABS(leaf.open_bal)) + SUM(leaf.dr) + SUM(leaf.cr) <> 0
)
-- سطور الحسابات ثم سطر الإجمالي في آخر الميزان
SELECT '1' || NVL(company, ' ') || account_code AS sort_key,
       company      AS "الشركة",
       account_code AS "رقم الحساب",
       name_ar      AS "اسم الحساب",
       ob_dr AS "رصيد أول مدين", ob_cr AS "رصيد أول دائن",
       mv_dr AS "حركة مدين",     mv_cr AS "حركة دائن",
       cb_dr AS "رصيد آخر مدين", cb_cr AS "رصيد آخر دائن"
FROM   tb
UNION ALL
SELECT '2', NULL, NULL, 'الإجمالي',
       NVL(SUM(ob_dr), 0), NVL(SUM(ob_cr), 0), NVL(SUM(mv_dr), 0), NVL(SUM(mv_cr), 0),
       NVL(SUM(cb_dr), 0), NVL(SUM(cb_cr), 0)
FROM   tb
ORDER  BY 1
