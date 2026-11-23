SELECT e.emp_no AS "الرقم", e.name_ar AS "الموظف",
       DECODE(e.emp_type, 'EMPLOYEE', 'موظف', 'WORKER', 'عامل', 'SOLDIER', 'عسكري', 'OFFICER', 'ضابط') AS "النوع",
       mr.name_ar AS "الرتبة",
       l.months_paid AS "عدد الشهور المصروفة",
       l.salaries_paid AS "المرتبات المصروفة",
       l.amount AS "مبلغ الحافز"
FROM   annual_incentive_lines l
JOIN   employees e ON e.employee_id = l.employee_id
LEFT JOIN military_ranks mr ON mr.rank_id = e.rank_id
WHERE  l.inc_id = :P105_INC_ID
ORDER BY e.emp_no
