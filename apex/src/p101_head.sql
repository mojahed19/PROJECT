SELECT e.emp_no "رقم الموظف", e.name_ar "الاسم", c.name_ar "الشركة", g.name_ar "الدرجة",
       SUBSTR(r.pay_period,1,4) || '-' || SUBSTR(r.pay_period,5,2) "الشهر",
       TO_CHAR(p.net_salary, 'FM999G999G999G990D00') || ' ' || r.currency_code "الصافي"
FROM payroll_lines p JOIN payroll_runs r ON r.run_id = p.run_id
JOIN employees e ON e.employee_id = p.employee_id
JOIN companies c ON c.company_id = p.company_id
JOIN job_grades g ON g.grade_id = p.grade_id
WHERE p.pline_id = :P101_PLINE_ID
