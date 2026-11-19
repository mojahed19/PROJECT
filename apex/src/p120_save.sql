DECLARE
  l_clob CLOB := apex_application.g_clob_01;
  l_errs apex_t_varchar2 := apex_t_varchar2();
  l_company NUMBER := JSON_VALUE(l_clob, '$.header.COMPANY_ID' RETURNING NUMBER);
  l_year    NUMBER := JSON_VALUE(l_clob, '$.header.FY_YEAR'    RETURNING NUMBER);
  l_name    VARCHAR2(150) := JSON_VALUE(l_clob, '$.header.NAME');
  l_id      NUMBER;
  l_status  VARCHAR2(10);
  l_cnt     NUMBER;
  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR (:G_USER_ROLE = 'ACCOUNTANT' AND l_company = :G_COMPANY_ID);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على موازنة هذه الشركة'); END IF;
  IF apex_application.g_x01 = 'APPROVE' AND :G_USER_ROLE <> 'GM' THEN err('الاعتماد للمدير العام فقط'); END IF;

  BEGIN
    SELECT budget_id, status INTO l_id, l_status FROM budgets
    WHERE company_id = l_company AND fy_year = l_year FOR UPDATE;
    IF l_status = 'APPROVED' THEN err('الموازنة معتمدة ولا يمكن تعديلها'); END IF;
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;

  SELECT COUNT(*) INTO l_cnt FROM (
    SELECT account_id FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (account_id NUMBER PATH '$.ACCOUNT_ID'))
    GROUP BY account_id HAVING COUNT(*) > 1);
  IF l_cnt > 0 THEN err('يوجد حساب مكرر في الموازنة'); END IF;

  SELECT COUNT(*) INTO l_cnt
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (account_id NUMBER PATH '$.ACCOUNT_ID')) j
  WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.account_id = j.account_id AND a.is_postable = 'Y');
  IF l_cnt > 0 THEN err('كل الحسابات يجب أن تكون تحليلية'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  IF l_id IS NULL THEN
    INSERT INTO budgets (company_id, fy_year, name_ar, created_by)
    VALUES (l_company, l_year, NVL(l_name, 'موازنة ' || l_year), :APP_USER)
    RETURNING budget_id INTO l_id;
  ELSE
    UPDATE budgets SET name_ar = NVL(l_name, name_ar) WHERE budget_id = l_id;
    DELETE FROM budget_lines WHERE budget_id = l_id;
  END IF;

  INSERT INTO budget_lines (budget_id, account_id, m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11, m12)
  SELECT l_id, account_id, NVL(m01,0), NVL(m02,0), NVL(m03,0), NVL(m04,0), NVL(m05,0), NVL(m06,0),
         NVL(m07,0), NVL(m08,0), NVL(m09,0), NVL(m10,0), NVL(m11,0), NVL(m12,0)
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
         account_id NUMBER PATH '$.ACCOUNT_ID',
         m01 NUMBER PATH '$.M01', m02 NUMBER PATH '$.M02', m03 NUMBER PATH '$.M03', m04 NUMBER PATH '$.M04',
         m05 NUMBER PATH '$.M05', m06 NUMBER PATH '$.M06', m07 NUMBER PATH '$.M07', m08 NUMBER PATH '$.M08',
         m09 NUMBER PATH '$.M09', m10 NUMBER PATH '$.M10', m11 NUMBER PATH '$.M11', m12 NUMBER PATH '$.M12'));

  IF apex_application.g_x01 = 'APPROVE' THEN
    UPDATE budgets SET status = 'APPROVED', approved_by = :APP_USER WHERE budget_id = l_id;
  END IF;

  apex_json.open_object; apex_json.write('ok', TRUE); apex_json.write('id', l_id);
  apex_json.write('message', CASE apex_application.g_x01 WHEN 'APPROVE' THEN 'تم اعتماد الموازنة' ELSE 'تم حفظ الموازنة' END);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
