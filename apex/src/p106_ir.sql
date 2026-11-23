SELECT a.inc_id, a.inc_no AS "الرقم", a.fy_year AS "السنة", a.percent AS "النسبة",
       DECODE(a.basis, 'BASIC', 'الأساسي', 'إجمالي الاستحقاقات') AS "أساس الحساب",
       NVL(DECODE(a.emp_type, 'EMPLOYEE', 'موظف', 'WORKER', 'عامل', 'SOLDIER', 'عسكري', 'OFFICER', 'ضابط'), 'الكل') AS "النوع",
       (SELECT COUNT(*) FROM annual_incentive_lines l WHERE l.inc_id = a.inc_id) AS "عدد الموظفين",
       a.total_amount AS "الإجمالي",
       DECODE(a.status, 'DRAFT', 'مسودة', 'RETURNED', 'معاد للمدخل', 'REVIEWED', 'مُراجَع',
              'POSTED', 'معتمد ومرحّل', 'REVERSED', 'معكوس') AS "الحالة",
       a.created_by AS "المدخل", a.approved_by AS "المعتمد"
FROM   annual_incentives a
ORDER BY a.inc_id DESC
