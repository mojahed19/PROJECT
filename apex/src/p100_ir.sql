SELECT p.pline_id, c.name_ar "الشركة", e.emp_no "الرقم", e.name_ar "الموظف", g.grade_code "الدرجة",
       p.basic_salary "الأساسي", p.total_allowances "العلاوات", p.total_incentives "الحوافز",
       p.total_diff "الفروقات", p.total_deductions "الخصومات", p.net_salary "الصافي",
       e.bank_account "الحساب البنكي"
FROM payroll_lines p
JOIN employees e  ON e.employee_id = p.employee_id
JOIN companies c  ON c.company_id  = p.company_id
JOIN job_grades g ON g.grade_id    = p.grade_id
WHERE p.run_id = :P100_RUN_ID
ORDER BY c.company_code, e.emp_no
