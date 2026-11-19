DECLARE
  l_clob    CLOB := apex_application.g_clob_01;
  l_errs    apex_t_varchar2 := apex_t_varchar2();
  l_company NUMBER := JSON_VALUE(l_clob, '$.header.COMPANY_ID' RETURNING NUMBER);
  l_date_s  VARCHAR2(20) := JSON_VALUE(l_clob, '$.header.AS_OF_DATE');
  l_date    DATE;
  l_cnt     NUMBER;
  l_dr      NUMBER := 0;
  l_cr      NUMBER := 0;
  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  IF :G_USER_ROLE NOT IN ('GM','ACCOUNTANT') THEN err('ليس لديك صلاحية'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM companies WHERE company_id = l_company AND is_parent = 'N';
  IF l_cnt = 0 THEN err('اختر الفرع'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN err('تاريخ الميزانية غير صحيح'); END;
  IF l_date IS NULL THEN err('أدخل تاريخ الميزانية'); END IF;

  FOR r IN (SELECT j.line_no, j.account_id, NVL(j.debit, 0) debit, NVL(j.credit, 0) credit
            FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                   line_no NUMBER PATH '$.LINE_NO', account_id NUMBER PATH '$.ACCOUNT_ID',
                   debit NUMBER PATH '$.DEBIT', credit NUMBER PATH '$.CREDIT')) j) LOOP
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = r.account_id AND is_postable = 'Y';
    IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الحساب يجب أن يكون تحليلياً'); END IF;
    IF r.debit < 0 OR r.credit < 0 OR (r.debit > 0 AND r.credit > 0) THEN
      err('السطر ' || r.line_no || ': أدخل مبلغاً في المدين أو الدائن فقط');
    END IF;
    l_dr := l_dr + r.debit; l_cr := l_cr + r.credit;
  END LOOP;

  SELECT COUNT(*) INTO l_cnt FROM (
    SELECT account_id FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (account_id NUMBER PATH '$.ACCOUNT_ID'))
    GROUP BY account_id HAVING COUNT(*) > 1);
  IF l_cnt > 0 THEN err('يوجد حساب مكرر'); END IF;

  IF ROUND(l_dr, 2) <> ROUND(l_cr, 2) THEN
    err('الميزانية غير متوازنة: المدين ' || TO_CHAR(l_dr, 'FM999G999G999G990D00')
        || ' والدائن ' || TO_CHAR(l_cr, 'FM999G999G999G990D00'));
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  DELETE FROM branch_balances WHERE company_id = l_company AND as_of_date = l_date;
  INSERT INTO branch_balances (company_id, as_of_date, account_id, debit, credit, notes, entered_by)
  SELECT l_company, l_date, account_id, NVL(debit, 0), NVL(credit, 0), notes, :APP_USER
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
         account_id NUMBER PATH '$.ACCOUNT_ID', debit NUMBER PATH '$.DEBIT',
         credit NUMBER PATH '$.CREDIT', notes VARCHAR2(300) PATH '$.NOTES'));

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('message', 'تم حفظ ميزانية الفرع بتاريخ ' || l_date_s);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
