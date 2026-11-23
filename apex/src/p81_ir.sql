WITH acc AS (
  -- الحساب المختار وكل ما تحته من حسابات تحليلية
  SELECT d.account_id FROM accounts d, accounts p
  WHERE  p.account_id = :P81_ACCOUNT_ID
  AND    d.account_code LIKE p.account_code || '%' AND d.acc_level = 4
),
rows_ AS (
  -- القيود المرحّلة فقط (القيد المعكوس وقيد عكسه يظهران معاً فيتصفّران)
  SELECT j.journal_date, j.journal_no, t.name_ar jt_name, j.journal_id, l.line_id,
         NVL(l.description, j.description) description, j.currency_code,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.debit_base  ELSE l.debit  END dr,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.credit_base ELSE l.credit END cr
  FROM   journals j
  JOIN   journal_lines l ON l.journal_id = j.journal_id
  JOIN   journal_types t ON t.jt_code    = j.jt_code
  WHERE  l.account_id IN (SELECT account_id FROM acc)
  AND    j.status IN ('POSTED','REVERSED')
  AND    (:P81_CURRENCY IS NULL OR j.currency_code = :P81_CURRENCY)
),
opening AS (
  SELECT NVL(SUM(dr - cr), 0) bal FROM rows_ WHERE journal_date < TO_DATE(:P81_FROM, 'DD/MM/YYYY')
),
period AS (
  SELECT r.*,
         (SELECT bal FROM opening)
         + SUM(dr - cr) OVER (ORDER BY journal_date, journal_id, line_id ROWS UNBOUNDED PRECEDING) run_bal,
         ROW_NUMBER() OVER (ORDER BY journal_date, journal_id, line_id) rn
  FROM   rows_ r
  WHERE  journal_date BETWEEN TO_DATE(:P81_FROM, 'DD/MM/YYYY') AND TO_DATE(:P81_TO, 'DD/MM/YYYY')
)
SELECT 0 AS sort_key, NULL AS journal_id, TO_DATE(:P81_FROM, 'DD/MM/YYYY') AS "التاريخ", NULL AS "رقم القيد",
       'رصيد أول المدة' AS "النوع", NULL AS "البيان", NULL AS "العملة",
       GREATEST(o.bal, 0) AS "مدين", GREATEST(-o.bal, 0) AS "دائن",
       ABS(o.bal) AS "الرصيد", CASE WHEN o.bal > 0 THEN 'مدين' WHEN o.bal < 0 THEN 'دائن' END AS "طبيعة الرصيد"
FROM   opening o
UNION ALL
SELECT p.rn, p.journal_id, p.journal_date, p.journal_no, p.jt_name, p.description, p.currency_code,
       p.dr, p.cr,
       ABS(p.run_bal), CASE WHEN p.run_bal > 0 THEN 'مدين' WHEN p.run_bal < 0 THEN 'دائن' END
FROM   period p
UNION ALL
SELECT 999999999, NULL, TO_DATE(:P81_TO, 'DD/MM/YYYY'), NULL, 'إجمالي الحركة والرصيد الختامي', NULL, NULL,
       NVL((SELECT SUM(dr) FROM period), 0), NVL((SELECT SUM(cr) FROM period), 0),
       ABS(o.bal + NVL((SELECT SUM(dr - cr) FROM period), 0)),
       CASE WHEN o.bal + NVL((SELECT SUM(dr - cr) FROM period), 0) > 0 THEN 'مدين'
            WHEN o.bal + NVL((SELECT SUM(dr - cr) FROM period), 0) < 0 THEN 'دائن' END
FROM   opening o
ORDER  BY 1
