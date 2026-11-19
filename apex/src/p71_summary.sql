SELECT c.name_ar  AS "الشركة",
       e.emp_no   AS "رقم الموظف",
       e.name_ar  AS "الموظف",
       g.name_ar  AS "الدرجة",
       a.pay_period AS "الشهر",
       SUM(CASE WHEN a.adj_type = 'INC'  THEN l.amount * a.exchange_rate ELSE 0 END) AS "الحوافز",
       SUM(CASE WHEN a.adj_type = 'DED'  THEN l.amount * a.exchange_rate ELSE 0 END) AS "الخصومات",
       SUM(CASE WHEN a.adj_type = 'DIFF' THEN DECODE(l.direction,'+',1,-1) * l.amount * a.exchange_rate ELSE 0 END) AS "الفروقات",
       SUM(DECODE(l.direction,'+',1,-1) * l.amount * a.exchange_rate) AS "الصافي (بالعملة الأساسية)"
FROM   payroll_adj a
JOIN   payroll_adj_lines l ON l.adj_id = a.adj_id
JOIN   employees  e ON e.employee_id = l.employee_id
JOIN   job_grades g ON g.grade_id    = e.grade_id
JOIN   companies  c ON c.company_id  = l.company_id
WHERE  a.status IN ('APPROVED','APPLIED')
AND    (:P71_PERIOD  IS NULL OR a.pay_period = :P71_PERIOD)
AND    (:P71_COMPANY IS NULL OR l.company_id = :P71_COMPANY)
GROUP  BY c.name_ar, e.emp_no, e.name_ar, g.name_ar, a.pay_period
ORDER  BY c.name_ar, e.emp_no
