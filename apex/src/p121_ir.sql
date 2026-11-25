-- الفترة: من شهر (lo) إلى شهر (hi). "كل الشهور" = 1..12 ، "تراكمي" = 1..الشهر ، "الشهر وحده" = الشهر فقط
WITH p AS (
  SELECT CASE WHEN :P121_MODE = 'ONE' AND :P121_TO_MONTH IS NOT NULL THEN TO_NUMBER(:P121_TO_MONTH) ELSE 1 END lo,
         NVL(TO_NUMBER(:P121_TO_MONTH), 12) hi
  FROM dual
),
bud AS (
  SELECT b.company_id, bl.account_id,
         NVL(bl.m01,0) * CASE WHEN 1 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m02,0) * CASE WHEN 2 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m03,0) * CASE WHEN 3 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m04,0) * CASE WHEN 4 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m05,0) * CASE WHEN 5 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m06,0) * CASE WHEN 6 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m07,0) * CASE WHEN 7 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m08,0) * CASE WHEN 8 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m09,0) * CASE WHEN 9 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m10,0) * CASE WHEN 10 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m11,0) * CASE WHEN 11 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END
       + NVL(bl.m12,0) * CASE WHEN 12 BETWEEN p.lo AND p.hi THEN 1 ELSE 0 END AS budget,
         bl.total AS annual
  FROM budgets b JOIN budget_lines bl ON bl.budget_id = b.budget_id CROSS JOIN p
  WHERE b.fy_year = :P121_FY_YEAR AND b.status = 'APPROVED'
  AND (:P121_COMPANY_ID IS NULL OR b.company_id = :P121_COMPANY_ID)
),
act AS (
  SELECT j.company_id, l.account_id,
         SUM(CASE a.acc_type WHEN 'REV' THEN l.credit_base - l.debit_base
                             WHEN 'EXP' THEN l.debit_base - l.credit_base
                             ELSE l.debit_base - l.credit_base END) AS actual
  FROM journals j JOIN journal_lines l ON l.journal_id = j.journal_id
  JOIN accounts a ON a.account_id = l.account_id
  CROSS JOIN p
  WHERE j.status IN ('POSTED','REVERSED') AND j.source_type <> 'CLOSING'   -- قيد الإقفال لا يدخل في الفعلي
  AND EXTRACT(YEAR FROM j.journal_date) = :P121_FY_YEAR
  AND EXTRACT(MONTH FROM j.journal_date) BETWEEN p.lo AND p.hi
  AND (:P121_COMPANY_ID IS NULL OR j.company_id = :P121_COMPANY_ID)
  AND (:P121_COMPANY_ID IS NOT NULL OR l.partner_company_id IS NULL)    -- المجمّع: استبعاد البيني
  GROUP BY j.company_id, l.account_id
),
leaf AS (
  SELECT a.account_code, SUM(budget) budget, SUM(annual) annual, SUM(actual) actual
  FROM (SELECT account_id, budget, annual, 0 actual FROM bud
        UNION ALL
        SELECT account_id, 0, 0, actual FROM act) x
  JOIN accounts a ON a.account_id = x.account_id
  GROUP BY a.account_code
)
SELECT p.account_code "الحساب", p.name_ar "الاسم",
       DECODE(p.acc_type,'REV','إيراد','EXP','مصروف','أخرى') "النوع",
       SUM(leaf.annual) "الموازنة السنوية",
       SUM(leaf.budget) "الموازنة للفترة",
       SUM(leaf.actual) "الفعلي",
       SUM(leaf.actual) - SUM(leaf.budget) "الانحراف",
       ROUND(100 * SUM(leaf.actual) / NULLIF(SUM(leaf.budget), 0), 1) "نسبة التنفيذ %",
       CASE WHEN p.acc_type = 'EXP' AND SUM(leaf.actual) > SUM(leaf.budget) THEN 'تجاوز'
            WHEN p.acc_type = 'REV' AND SUM(leaf.actual) < SUM(leaf.budget) THEN 'أقل من المستهدف' END "تنبيه"
FROM accounts p
JOIN leaf ON leaf.account_code LIKE p.account_code || '%'
WHERE p.acc_level = :P121_LEVEL AND p.acc_type IN ('REV','EXP')
GROUP BY p.account_code, p.name_ar, p.acc_type
ORDER BY p.account_code
