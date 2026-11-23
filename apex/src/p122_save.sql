DECLARE
  -- حفظ خطة إدارة لسنة (Ajax: p_clob_01 = {header, lines})
  l_clob CLOB := apex_application.g_clob_01;
  l_errs apex_t_varchar2 := apex_t_varchar2();
  l_id   NUMBER; l_year NUMBER; l_dept NUMBER; l_desc VARCHAR2(500); l_st VARCHAR2(10);
  l_co   NUMBER := NVL(:G_COMPANY_ID, :G_PARENT_ID);
  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT h.plan_id, h.fy_year, h.dept_id, h.description
  INTO   l_id, l_year, l_dept, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           plan_id NUMBER PATH '$.PLAN_ID', fy_year NUMBER PATH '$.FY_YEAR',
           dept_id NUMBER PATH '$.DEPT_ID', description VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('إدخال الخطة من صلاحية المدخل'); END IF;
  IF l_year IS NULL OR l_dept IS NULL THEN err('اختر السنة والإدارة'); END IF;
  IF l_id IS NULL THEN
    SELECT MAX(plan_id) INTO l_id FROM budget_plans WHERE fy_year = l_year AND dept_id = l_dept;
  END IF;
  IF l_id IS NOT NULL THEN
    SELECT status INTO l_st FROM budget_plans WHERE plan_id = l_id FOR UPDATE;
    IF l_st NOT IN ('DRAFT','RETURNED') THEN err('خطة هذه الإدارة لهذه السنة تمت مراجعتها أو اعتمادها ولا يمكن تعديلها'); END IF;
  END IF;
  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
               q1 NUMBER PATH '$.Q1', q2 NUMBER PATH '$.Q2', q3 NUMBER PATH '$.Q3', q4 NUMBER PATH '$.Q4'))) LOOP
    IF NVL(r.q1, 0) < 0 OR NVL(r.q2, 0) < 0 OR NVL(r.q3, 0) < 0 OR NVL(r.q4, 0) < 0 THEN
      err('لا تُقبل مبالغ سالبة'); EXIT;
    END IF;
  END LOOP;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  IF l_id IS NULL THEN
    INSERT INTO budget_plans (company_id, fy_year, dept_id, description, created_by)
    VALUES (l_co, l_year, l_dept, l_desc, :APP_USER)
    RETURNING plan_id INTO l_id;
  ELSE
    UPDATE budget_plans SET description = l_desc, status = 'DRAFT', return_note = NULL WHERE plan_id = l_id;
    DELETE FROM budget_plan_lines WHERE plan_id = l_id;
  END IF;

  INSERT INTO budget_plan_lines (plan_id, bitem_id, q1, q2, q3, q4, notes)
  SELECT l_id, bitem_id, NVL(q1, 0), NVL(q2, 0), NVL(q3, 0), NVL(q4, 0), notes
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           bitem_id NUMBER PATH '$.BITEM_ID', q1 NUMBER PATH '$.Q1', q2 NUMBER PATH '$.Q2',
           q3 NUMBER PATH '$.Q3', q4 NUMBER PATH '$.Q4', notes VARCHAR2(300) PATH '$.NOTES'))
  WHERE  bitem_id IS NOT NULL
  AND    (NVL(q1, 0) + NVL(q2, 0) + NVL(q3, 0) + NVL(q4, 0) > 0 OR notes IS NOT NULL);

  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('BUDGET_PLAN', l_id, 'SAVE', l_st, 'DRAFT', :APP_USER);

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('message', 'تم حفظ الخطة - بانتظار المراجعة');
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
