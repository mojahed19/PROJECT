DECLARE
      -- اعتماد الحافز السنوي: من ح/ مصروف الحوافز إلى ح/ رواتب مستحقة
      a annual_incentives%ROWTYPE; l_exp NUMBER; l_pay NUMBER; l_jid NUMBER; l_cur VARCHAR2(3);
    BEGIN
      SELECT * INTO a FROM annual_incentives WHERE inc_id = l_id;
      IF a.total_amount <= 0 THEN raise_application_error(-20041, 'لا توجد مبالغ في الحافز'); END IF;
      BEGIN
        SELECT account_id INTO l_exp FROM account_settings WHERE company_id = a.company_id AND setting_code = 'INCENTIVE_EXP';
        SELECT account_id INTO l_pay FROM account_settings WHERE company_id = a.company_id AND setting_code = 'SALARY_PAYABLE';
      EXCEPTION WHEN NO_DATA_FOUND THEN
        raise_application_error(-20042, 'حدد حسابي مصروف الحوافز والرواتب المستحقة في الحسابات الافتراضية');
      END;
      SELECT currency_code INTO l_cur FROM currencies WHERE is_base = 'Y';
      INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate, description,
                            status, source_type, source_id, total_debit, total_credit, created_by,
                            reviewed_by, reviewed_on, approved_by, approved_on, posted_by, posted_on)
      VALUES (a.company_id, 'AINC', a.inc_no, TRUNC(SYSDATE), l_cur, 1,
              NVL(a.description, 'الحافز السنوي لعام ' || a.fy_year), 'POSTED', 'PAYROLL', a.inc_id,
              a.total_amount, a.total_amount, a.created_by, a.reviewed_by, a.reviewed_on, :APP_USER, SYSDATE, :APP_USER, SYSDATE)
      RETURNING journal_id INTO l_jid;
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
      VALUES (l_jid, 1, l_exp, a.total_amount, 0, a.total_amount, 0, 'الحافز السنوي ' || a.fy_year);
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
      VALUES (l_jid, 2, l_pay, 0, a.total_amount, 0, a.total_amount, 'الحافز السنوي ' || a.fy_year);
      UPDATE annual_incentives SET journal_id = l_jid WHERE inc_id = l_id;
    END;
