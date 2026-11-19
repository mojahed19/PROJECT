DECLARE
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type VARCHAR2(5); l_date_s VARCHAR2(20); l_date DATE; l_period VARCHAR2(6);
  l_allow NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_reason VARCHAR2(500);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER;
  l_total NUMBER := 0; l_lines NUMBER := 0; l_parent NUMBER := :G_PARENT_ID;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT h.adj_id, h.adj_type, h.adj_date, h.pay_period, h.allowance_id,
         h.currency_code, h.exchange_rate, h.reason
  INTO   l_id, l_type, l_date_s, l_period, l_allow, l_cur, l_rate, l_reason
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           adj_id        NUMBER        PATH '$.ADJ_ID',
           adj_type      VARCHAR2(5)   PATH '$.ADJ_TYPE',
           adj_date      VARCHAR2(20)  PATH '$.ADJ_DATE',
           pay_period    VARCHAR2(6)   PATH '$.PAY_PERIOD',
           allowance_id  NUMBER        PATH '$.ALLOWANCE_ID',
           currency_code VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate NUMBER        PATH '$.EXCHANGE_RATE',
           reason        VARCHAR2(500) PATH '$.REASON')) h;

  IF l_type NOT IN ('DED','DIFF','INC') OR l_type IS NULL THEN err('نوع المستند غير معروف'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;
  IF l_period IS NULL OR NOT REGEXP_LIKE(l_period, '^[0-9]{4}(0[1-9]|1[0-2])$') THEN err('اختر شهر الراتب'); END IF;
  IF l_reason IS NULL THEN err('السبب مطلوب'); END IF;
  IF l_cur IS NULL THEN err('اختر العملة'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF :G_USER_ROLE NOT IN ('GM','HR') THEN err('ليس لديك صلاحية على شاشات الرواتب'); END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, adj_no INTO l_status, l_no FROM payroll_adj WHERE adj_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('المستند ' || l_no || ' معتمد أو مطبَّق ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('المستند غير موجود'); END;
  ELSIF l_action = 'CANCEL' THEN
    err('لا يوجد مستند محفوظ لإلغائه');
  END IF;

  -- لا يُقبل مستند لشهر رواتب سبق تشغيله
  -- (يُفعَّل بعد إنشاء جدول payroll_runs في مرحلة الرواتب)

  IF l_action <> 'CANCEL' THEN
    FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                 line_no NUMBER PATH '$.LINE_NO', employee_id NUMBER PATH '$.EMPLOYEE_ID',
                 direction VARCHAR2(1) PATH '$.DIRECTION', amount NUMBER PATH '$.AMOUNT'))) LOOP
      l_lines := l_lines + 1;
      SELECT COUNT(*) INTO l_cnt FROM employees WHERE employee_id = r.employee_id AND is_active = 'Y';
      IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الموظف غير موجود أو غير فعّال'); END IF;
      IF NVL(r.amount, 0) <= 0 THEN err('السطر ' || r.line_no || ': المبلغ يجب أن يكون أكبر من صفر'); END IF;
      IF l_type = 'DIFF' AND NVL(r.direction, 'x') NOT IN ('+','-') THEN
        err('السطر ' || r.line_no || ': اختر الإشارة (+ أو -)');
      END IF;
      l_total := l_total + NVL(r.amount, 0);
    END LOOP;
    IF l_lines = 0 THEN err('أدخل موظفاً واحداً على الأقل'); END IF;

    -- لا يتكرر الموظف في نفس المستند
    SELECT COUNT(*) INTO l_cnt FROM (
      SELECT employee_id FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (employee_id NUMBER PATH '$.EMPLOYEE_ID'))
      GROUP BY employee_id HAVING COUNT(*) > 1);
    IF l_cnt > 0 THEN err('يوجد موظف مكرر في المستند'); END IF;
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  IF l_action = 'CANCEL' THEN
    UPDATE payroll_adj SET status = 'CANCELLED' WHERE adj_id = l_id;
  ELSE
    IF l_id IS NULL THEN
      UPDATE doc_sequences SET last_no = last_no + 1
      WHERE company_id = l_parent AND doc_type = l_type AND fy_year = EXTRACT(YEAR FROM l_date)
      RETURNING last_no INTO l_seq;
      IF SQL%ROWCOUNT = 0 THEN
        INSERT INTO doc_sequences VALUES (l_parent, l_type, EXTRACT(YEAR FROM l_date), 1);
        l_seq := 1;
      END IF;
      l_no := l_type || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

      INSERT INTO payroll_adj (adj_type, adj_no, adj_date, pay_period, allowance_id,
                               currency_code, exchange_rate, reason, created_by)
      VALUES (l_type, l_no, l_date, l_period, l_allow, l_cur, l_rate, l_reason, :APP_USER)
      RETURNING adj_id INTO l_id;
    ELSE
      UPDATE payroll_adj
      SET adj_date = l_date, pay_period = l_period, allowance_id = l_allow,
          currency_code = l_cur, exchange_rate = l_rate, reason = l_reason
      WHERE adj_id = l_id;
      DELETE FROM payroll_adj_lines WHERE adj_id = l_id;
    END IF;

    -- الشركة تؤخذ من بيانات الموظف الحالية، والإشارة تُفرض حسب النوع
    INSERT INTO payroll_adj_lines (adj_id, line_no, employee_id, company_id, direction, amount, notes)
    SELECT l_id, ROWNUM, j.employee_id, e.company_id,
           CASE l_type WHEN 'DED' THEN '-' WHEN 'INC' THEN '+' ELSE j.direction END,
           j.amount, j.notes
    FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
             employee_id NUMBER PATH '$.EMPLOYEE_ID', direction VARCHAR2(1) PATH '$.DIRECTION',
             amount NUMBER PATH '$.AMOUNT', notes VARCHAR2(300) PATH '$.NOTES')) j
    JOIN   employees e ON e.employee_id = j.employee_id;

    UPDATE payroll_adj
    SET total_amount = l_total,
        status      = CASE WHEN l_action = 'APPROVE' THEN 'APPROVED' ELSE 'DRAFT' END,
        approved_by = CASE WHEN l_action = 'APPROVE' THEN :APP_USER END,
        approved_on = CASE WHEN l_action = 'APPROVE' THEN SYSDATE END
    WHERE adj_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE); apex_json.write('id', l_id); apex_json.write('no', l_no);
  apex_json.write('message', CASE l_action WHEN 'APPROVE' THEN 'تم اعتماد المستند '
                                           WHEN 'CANCEL'  THEN 'تم إلغاء المستند '
                                           ELSE 'تم حفظ المستند ' END || l_no);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
