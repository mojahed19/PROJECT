DECLARE
  l_run     NUMBER := :P100_RUN_ID;
  l_parent  NUMBER := :G_PARENT_ID;
  l_date    DATE   := LAST_DAY(TO_DATE(:P100_PERIOD || '01', 'YYYYMMDD'));
  l_base    VARCHAR2(3);
  l_jid     NUMBER;
  l_line    NUMBER;
  l_ar      NUMBER;
  l_sal     NUMBER; l_ded NUMBER; l_diff NUMBER; l_inc NUMBER;

  FUNCTION setting (p_company NUMBER, p_code VARCHAR2) RETURN NUMBER IS l NUMBER;
  BEGIN
    SELECT account_id INTO l FROM account_settings WHERE company_id = p_company AND setting_code = p_code;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20030, 'لم يُعرَّف الحساب ' || p_code || ' للشركة رقم ' || p_company);
  END;

  FUNCTION new_journal (p_company NUMBER, p_desc VARCHAR2) RETURN NUMBER IS
    l_seq NUMBER; l_id NUMBER;
  BEGIN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = p_company AND doc_type = 'PAY' AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (p_company, 'PAY', EXTRACT(YEAR FROM l_date), 1); l_seq := 1;
    END IF;
    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, status, source_type, source_id, created_by, posted_by, posted_on)
    VALUES (p_company, 'PAY', 'PAY-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0'),
            l_date, l_base, 1, p_desc, 'POSTED', 'PAYROLL', l_run, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_id;
    INSERT INTO payroll_run_journals VALUES (l_run, l_id);
    l_line := 0;
    RETURN l_id;
  END;

  PROCEDURE jline (p_acc NUMBER, p_amt NUMBER, p_partner NUMBER DEFAULT NULL) IS  -- موجب مدين / سالب دائن
  BEGIN
    IF ROUND(p_amt, 2) = 0 THEN RETURN; END IF;
    l_line := l_line + 1;
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, description)
    VALUES (l_jid, l_line, p_acc, GREATEST(p_amt, 0), GREATEST(-p_amt, 0), GREATEST(p_amt, 0), GREATEST(-p_amt, 0),
            p_partner, 'رواتب ' || :P100_PERIOD);
  END;

  PROCEDURE close_journal IS
  BEGIN
    UPDATE journals SET total_debit  = (SELECT SUM(debit)  FROM journal_lines WHERE journal_id = l_jid),
                        total_credit = (SELECT SUM(credit) FROM journal_lines WHERE journal_id = l_jid)
    WHERE journal_id = l_jid;
  END;
BEGIN
  SELECT currency_code INTO l_base FROM currencies WHERE is_base = 'Y';

  UPDATE payroll_runs SET status = 'APPROVED', approved_by = :APP_USER, approved_on = SYSDATE
  WHERE run_id = l_run AND status = 'DRAFT';
  IF SQL%ROWCOUNT = 0 THEN raise_application_error(-20031, 'المسير غير موجود أو معتمد مسبقاً'); END IF;

  FOR c IN (SELECT p.company_id, co.name_ar, co.is_parent, SUM(p.net_salary) net
            FROM payroll_lines p JOIN companies co ON co.company_id = p.company_id
            WHERE p.run_id = l_run GROUP BY p.company_id, co.name_ar, co.is_parent) LOOP

    -- حسابات الشركة (الدوال المحلية لا تُستدعى داخل SQL، فتُقرأ في متغيرات أولاً)
    l_sal  := setting(c.company_id, 'SALARY_EXP');
    l_ded  := setting(c.company_id, 'DEDUCTIONS');
    l_diff := setting(c.company_id, 'SALARY_DIFF');
    l_inc  := setting(c.company_id, 'INCENTIVE_EXP');

    -- 1) قيد الشركة: المصروفات والاستقطاعات والصافي
    l_jid := new_journal(c.company_id, 'رواتب شهر ' || :P100_PERIOD || ' - ' || c.name_ar);

    FOR a IN (SELECT acc, SUM(amt) amt FROM (
                SELECT CASE d.item_kind
                         WHEN 'BASIC'     THEN l_sal
                         WHEN 'DEDUCTION' THEN l_ded
                         WHEN 'DIFF'      THEN l_diff
                         WHEN 'INCENTIVE' THEN NVL(t.account_id, l_inc)
                         ELSE NVL(t.account_id, l_sal) END acc,
                       d.amount amt
                FROM payroll_line_details d
                JOIN payroll_lines p ON p.pline_id = d.pline_id
                LEFT JOIN allowance_types t ON t.allowance_id = d.allowance_id
                WHERE p.run_id = l_run AND p.company_id = c.company_id)
              GROUP BY acc HAVING SUM(amt) <> 0) LOOP
      jline(a.acc, a.amt);
    END LOOP;

    IF c.is_parent = 'Y' THEN
      jline(setting(c.company_id, 'SALARY_PAYABLE'), -c.net);
    ELSE
      jline(setting(c.company_id, 'INTERCO_AP'), -c.net, l_parent);
    END IF;
    close_journal;

    -- 2) قيد الأم عن رواتب موظفي الشركة الفرعية (الأم تصرف وتطالب الفرعية)
    IF c.is_parent = 'N' THEN
      l_jid := new_journal(l_parent, 'رواتب ' || c.name_ar || ' لشهر ' || :P100_PERIOD || ' (تحميل على الشركة)');
      SELECT ar_account_id INTO l_ar FROM company_accounts WHERE company_id = c.company_id;
      jline(l_ar, c.net, c.company_id);
      jline(setting(l_parent, 'SALARY_PAYABLE'), -c.net);
      close_journal;
    END IF;
  END LOOP;

  -- تعليم مستندات الخصم/الفرق/الحافز بأنها طُبّقت
  UPDATE payroll_adj SET status = 'APPLIED', applied_run_id = l_run
  WHERE  adj_id IN (SELECT d.adj_id FROM payroll_line_details d JOIN payroll_lines p ON p.pline_id = d.pline_id
                    WHERE p.run_id = l_run AND d.adj_id IS NOT NULL);

  apex_application.g_print_success_message := 'تم اعتماد المسير وإنشاء القيود';
END;
