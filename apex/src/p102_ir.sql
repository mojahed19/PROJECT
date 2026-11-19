SELECT c.name_ar "الشركة", COUNT(*) "عدد الموظفين",
       SUM(p.basic_salary) "الأساسي", SUM(p.total_allowances) "العلاوات",
       SUM(p.total_incentives) "الحوافز", SUM(p.total_diff) "الفروقات",
       SUM(p.total_deductions) "الخصومات", SUM(p.net_salary) "الصافي",
       ROUND(100 * RATIO_TO_REPORT(SUM(p.net_salary)) OVER (), 1) "النسبة %"
FROM payroll_lines p
JOIN payroll_runs r ON r.run_id = p.run_id AND r.status = 'APPROVED'
JOIN companies c ON c.company_id = p.company_id
WHERE r.pay_period BETWEEN :P102_FROM AND :P102_TO
GROUP BY c.name_ar
ORDER BY 8 DESC
