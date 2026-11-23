DECLARE
  -- حساب الحافز السنوي: النسبة × المرتبات المصروفة للموظف خلال السنة (من المسيرات المعتمدة)
  l_id    NUMBER       := :P105_INC_ID;
  l_year  NUMBER;
  l_pct   NUMBER;
  l_basis VARCHAR2(10) := NVL(:P105_BASIS, 'BASIC');
  l_type  VARCHAR2(10) := :P105_EMP_TYPE;
  l_co    NUMBER       := NVL(:G_COMPANY_ID, :G_PARENT_ID);
  l_st    VARCHAR2(10);
  l_seq   NUMBER;
  l_no    VARCHAR2(20);
  l_cnt   NUMBER;
  l_tot   NUMBER;
  PROCEDURE err (p VARCHAR2) IS
  BEGIN apex_error.add_error(p_message => p, p_display_location => apex_error.c_inline_in_notification); END;
BEGIN
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('إعداد الحافز من صلاحية المدخل'); RETURN; END IF;
  BEGIN l_year := TO_NUMBER(:P105_FY_YEAR); l_pct := TO_NUMBER(REPLACE(:P105_PERCENT, ',', ''));
  EXCEPTION WHEN OTHERS THEN err('السنة أو النسبة غير صحيحة'); RETURN; END;
  IF l_year IS NULL THEN err('اختر السنة'); END IF;
  IF NVL(l_pct, 0) <= 0 OR l_pct > 100 THEN err('النسبة يجب أن تكون بين 0 و 100'); END IF;
  IF l_id IS NOT NULL THEN
    SELECT status, inc_no INTO l_st, l_no FROM annual_incentives WHERE inc_id = l_id FOR UPDATE;
    IF l_st NOT IN ('DRAFT','RETURNED') THEN err('الحافز ' || l_no || ' تمت مراجعته أو اعتماده ولا يمكن تعديله'); END IF;
  END IF;
  IF apex_error.have_errors_occurred THEN RETURN; END IF;

  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1 WHERE company_id = l_co AND doc_type = '18' AND fy_year = l_year
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (l_co, '18', l_year, 1); l_seq := 1;
    END IF;
    l_no := '18' || l_year || LPAD(l_seq, 5, '0');
    INSERT INTO annual_incentives (company_id, inc_no, fy_year, percent, basis, emp_type, description, created_by)
    VALUES (l_co, l_no, l_year, l_pct, l_basis, l_type, :P105_DESCRIPTION, :APP_USER)
    RETURNING inc_id INTO l_id;
    :P105_INC_ID := l_id;
  ELSE
    UPDATE annual_incentives
    SET    fy_year = l_year, percent = l_pct, basis = l_basis, emp_type = l_type, description = :P105_DESCRIPTION,
           status = 'DRAFT', return_note = NULL
    WHERE  inc_id = l_id;
    DELETE FROM annual_incentive_lines WHERE inc_id = l_id;
  END IF;

  INSERT INTO annual_incentive_lines (inc_id, employee_id, months_paid, salaries_paid, amount)
  SELECT l_id, pl.employee_id, COUNT(DISTINCT r.pay_period),
         SUM(CASE l_basis WHEN 'BASIC' THEN pl.basic_salary
                          ELSE pl.basic_salary + pl.total_allowances + pl.total_incentives + pl.total_diff END),
         ROUND(l_pct / 100 * SUM(CASE l_basis WHEN 'BASIC' THEN pl.basic_salary
                          ELSE pl.basic_salary + pl.total_allowances + pl.total_incentives + pl.total_diff END), 2)
  FROM   payroll_lines pl
  JOIN   payroll_runs r ON r.run_id = pl.run_id AND r.status = 'APPROVED' AND SUBSTR(r.pay_period, 1, 4) = TO_CHAR(l_year)
  JOIN   employees e ON e.employee_id = pl.employee_id
  WHERE  l_type IS NULL OR e.emp_type = l_type
  GROUP  BY pl.employee_id;
  l_cnt := SQL%ROWCOUNT;

  SELECT NVL(SUM(amount), 0) INTO l_tot FROM annual_incentive_lines WHERE inc_id = l_id;
  UPDATE annual_incentives SET total_amount = l_tot WHERE inc_id = l_id;
  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('ANNUAL_INC', l_id, 'SAVE', l_st, 'DRAFT', :APP_USER);

  apex_application.g_print_success_message := 'تم حساب الحافز ' || l_no || ' لعدد ' || l_cnt || ' موظف بإجمالي '
      || TO_CHAR(l_tot, 'FM999G999G999G990D00') || ' - بانتظار المراجعة';
END;
