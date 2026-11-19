DECLARE
  l_emp   CLOB;
  l_lines CLOB;
BEGIN
  -- الموظفون الفعّالون (كل الشركات للمدير العام وHR الأم، وإلا موظفو شركة المستخدم)
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'id'      VALUE e.employee_id,
           'code'    VALUE e.emp_no,
           'name'    VALUE e.name_ar,
           'company' VALUE c.name_ar,
           'grade'   VALUE g.grade_code)
         ORDER BY e.emp_no RETURNING CLOB)
  INTO   l_emp
  FROM   employees e
  JOIN   companies  c ON c.company_id = e.company_id
  JOIN   job_grades g ON g.grade_id   = e.grade_id
  WHERE  e.is_active = 'Y'
  AND    (:G_USER_ROLE IN ('GM','HR') AND :G_COMPANY_ID = :G_PARENT_ID
          OR e.company_id = :G_COMPANY_ID);

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'EMPLOYEE_ID' VALUE l.employee_id, 'DIRECTION' VALUE l.direction,
           'AMOUNT' VALUE l.amount, 'NOTES' VALUE l.notes)
         ORDER BY l.line_no RETURNING CLOB)
  INTO   l_lines
  FROM   payroll_adj_lines l
  WHERE  l.adj_id = TO_NUMBER(apex_application.g_x01);

  apex_util.prn('{"employees":' || COALESCE(l_emp,   TO_CLOB('[]')) ||
                ',"lines":'     || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
