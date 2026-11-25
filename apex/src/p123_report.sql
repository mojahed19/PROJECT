WITH pl AS (
  -- خطة كل إدارة لكل بند (الخطط المعتمدة أو كلها حسب الاختيار)
  SELECT l.bitem_id, d.dept_code, d.name_ar dept, l.q1, l.q2, l.q3, l.q4
  FROM   budget_plan_lines l
  JOIN   budget_plans p ON p.plan_id = l.plan_id AND p.fy_year = TO_NUMBER(:P123_FY_YEAR)
                       AND (NVL(:P123_ONLY_APPROVED, 'N') = 'N' OR p.status = 'APPROVED')
  JOIN   departments d ON d.dept_id = p.dept_id
), act AS (
  -- الفعلي من القيود المرحّلة لحساب البند وما تحته بالأرباع
  SELECT b.bitem_id,
         SUM(CASE WHEN TO_CHAR(j.journal_date, 'Q') = '1' THEN x.amt END) a1,
         SUM(CASE WHEN TO_CHAR(j.journal_date, 'Q') = '2' THEN x.amt END) a2,
         SUM(CASE WHEN TO_CHAR(j.journal_date, 'Q') = '3' THEN x.amt END) a3,
         SUM(CASE WHEN TO_CHAR(j.journal_date, 'Q') = '4' THEN x.amt END) a4
  FROM   budget_items b
  JOIN   accounts pa ON pa.account_id = b.account_id
  JOIN   accounts a  ON a.account_code LIKE pa.account_code || '%'
  JOIN   journal_lines jl ON jl.account_id = a.account_id
  JOIN   journals j ON j.journal_id = jl.journal_id AND j.status = 'POSTED' AND j.source_type <> 'CLOSING'
                   AND EXTRACT(YEAR FROM j.journal_date) = TO_NUMBER(:P123_FY_YEAR)
  CROSS APPLY (SELECT CASE b.item_type WHEN 'EXP' THEN jl.debit_base - jl.credit_base
                                       ELSE jl.credit_base - jl.debit_base END amt FROM dual) x
  GROUP BY b.bitem_id
), tot AS (
  SELECT bitem_id, SUM(q1) q1, SUM(q2) q2, SUM(q3) q3, SUM(q4) q4 FROM pl GROUP BY bitem_id
)
SELECT r.sort_key, r.note_no AS "رقم الإيضاح", r.item_name AS "البند", r.line_label AS "الإدارة / البيان",
       r.q1 AS "الربع الأول", r.q2 AS "الربع الثاني", r.q3 AS "الربع الثالث", r.q4 AS "الربع الرابع",
       NVL(r.q1, 0) + NVL(r.q2, 0) + NVL(r.q3, 0) + NVL(r.q4, 0) AS "الإجمالي"
FROM (
  SELECT LPAD(b.sort_order, 6, '0') || b.note_no || '1' || pl.dept_code sort_key, b.note_no, b.name_ar item_name,
         pl.dept line_label, pl.q1, pl.q2, pl.q3, pl.q4
  FROM   budget_items b JOIN pl ON pl.bitem_id = b.bitem_id
  UNION ALL
  SELECT LPAD(b.sort_order, 6, '0') || b.note_no || '2', b.note_no, b.name_ar, 'إجمالي الخطة', t.q1, t.q2, t.q3, t.q4
  FROM   budget_items b JOIN tot t ON t.bitem_id = b.bitem_id
  UNION ALL
  SELECT LPAD(b.sort_order, 6, '0') || b.note_no || '3', b.note_no, b.name_ar, 'الفعلي', a.a1, a.a2, a.a3, a.a4
  FROM   budget_items b JOIN act a ON a.bitem_id = b.bitem_id
  WHERE  b.account_id IS NOT NULL
  UNION ALL
  SELECT LPAD(b.sort_order, 6, '0') || b.note_no || '4', b.note_no, b.name_ar, 'الانحراف (الفعلي - الخطة)',
         NVL(a.a1, 0) - NVL(t.q1, 0), NVL(a.a2, 0) - NVL(t.q2, 0), NVL(a.a3, 0) - NVL(t.q3, 0), NVL(a.a4, 0) - NVL(t.q4, 0)
  FROM   budget_items b LEFT JOIN tot t ON t.bitem_id = b.bitem_id LEFT JOIN act a ON a.bitem_id = b.bitem_id
  WHERE  b.account_id IS NOT NULL AND (t.bitem_id IS NOT NULL OR a.bitem_id IS NOT NULL)
) r
JOIN budget_items bi ON bi.note_no = r.note_no
WHERE :P123_BITEM_ID IS NULL OR bi.bitem_id = TO_NUMBER(:P123_BITEM_ID)
ORDER BY r.sort_key
