DECLARE
  l_run    NUMBER;
  l_pl     NUMBER;
  l_basic  NUMBER;
  l_rate   NUMBER;
  l_base   VARCHAR2(3);
  l_start  DATE := TO_DATE(:P100_PERIOD || '01', 'YYYYMMDD');
  l_end    DATE := LAST_DAY(TO_DATE(:P100_PERIOD || '01', 'YYYYMMDD'));
BEGIN
  SELECT currency_code INTO l_base FROM currencies WHERE is_base = 'Y';

  -- مسودة موجودة: تُمسح سطورها ويُعاد الاحتساب
  BEGIN
    SELECT run_id INTO l_run FROM payroll_runs
    WHERE pay_period = :P100_PERIOD AND NVL(company_id, 0) = NVL(:P100_COMPANY_ID, 0) AND status = 'DRAFT'
    FOR UPDATE;
    DELETE FROM payroll_lines WHERE run_id = l_run;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    INSERT INTO payroll_runs (pay_period, company_id, currency_code, created_by)
    VALUES (:P100_PERIOD, :P100_COMPANY_ID, l_base, :APP_USER)
    RETURNING run_id INTO l_run;
  END;

  FOR e IN (SELECT e.employee_id, e.company_id, e.grade_id,
                   NVL(e.basic_salary, g.basic_salary) basic, g.currency_code cur
            FROM   employees e JOIN job_grades g ON g.grade_id = e.grade_id
            WHERE  e.is_active = 'Y'
            AND    (e.hire_date IS NULL OR e.hire_date <= l_end)
            AND    (:P100_COMPANY_ID IS NULL OR e.company_id = :P100_COMPANY_ID)) LOOP

    -- تحويل الأساسي للعملة الأساسية
    SELECT NVL(MAX(CASE WHEN c.is_base = 'Y' THEN 1 ELSE
              (SELECT r.rate FROM exchange_rates r WHERE r.currency_code = c.currency_code
               AND r.rate_date <= l_end ORDER BY r.rate_date DESC FETCH FIRST 1 ROW ONLY) END), 1)
    INTO l_rate FROM currencies c WHERE c.currency_code = e.cur;
    l_basic := ROUND(e.basic * l_rate, 2);

    INSERT INTO payroll_lines (run_id, employee_id, company_id, grade_id, basic_salary)
    VALUES (l_run, e.employee_id, e.company_id, e.grade_id, l_basic)
    RETURNING pline_id INTO l_pl;

    INSERT INTO payroll_line_details (pline_id, item_kind, description, amount)
    VALUES (l_pl, 'BASIC', 'الراتب الأساسي', l_basic);

    -- العلاوات / الحوافز / الخصومات الثابتة: الموظف يغلب الدرجة
    INSERT INTO payroll_line_details (pline_id, item_kind, allowance_id, description, amount)
    SELECT l_pl, t.kind, t.allowance_id, t.name_ar,
           ROUND(CASE t.calc_method WHEN 'PERCENT' THEN l_basic * v.value / 100 ELSE v.value * l_rate END, 2)
           * CASE t.kind WHEN 'DEDUCTION' THEN -1 ELSE 1 END
    FROM   allowance_types t
    JOIN  (SELECT ea.allowance_id, ea.value
           FROM   emp_allowances ea
           WHERE  ea.employee_id = e.employee_id
           AND    (ea.from_date IS NULL OR ea.from_date <= l_end)
           AND    (ea.to_date   IS NULL OR ea.to_date   >= l_start)
           UNION ALL
           SELECT ga.allowance_id, ga.value
           FROM   grade_allowances ga
           WHERE  ga.grade_id = e.grade_id
           AND    NOT EXISTS (SELECT 1 FROM emp_allowances ea
                              WHERE ea.employee_id = e.employee_id AND ea.allowance_id = ga.allowance_id
                              AND (ea.from_date IS NULL OR ea.from_date <= l_end)
                              AND (ea.to_date   IS NULL OR ea.to_date   >= l_start))) v
           ON v.allowance_id = t.allowance_id
    WHERE  v.value <> 0;

    -- مستندات الخصم / الفرق / الحافز المعتمدة لهذا الشهر
    INSERT INTO payroll_line_details (pline_id, item_kind, allowance_id, adj_id, description, amount)
    SELECT l_pl, DECODE(a.adj_type, 'DED', 'DEDUCTION', 'INC', 'INCENTIVE', 'DIFF'),
           a.allowance_id, a.adj_id, SUBSTR(a.adj_no || ' - ' || a.reason, 1, 200),
           ROUND(DECODE(l.direction, '+', 1, -1) * l.amount * a.exchange_rate, 2)
    FROM   payroll_adj a JOIN payroll_adj_lines l ON l.adj_id = a.adj_id
    WHERE  a.status = 'APPROVED' AND a.pay_period = :P100_PERIOD
    AND    l.employee_id = e.employee_id;
  END LOOP;

  -- الإجماليات
  UPDATE payroll_lines p SET
    total_allowances = (SELECT NVL(SUM(amount), 0) FROM payroll_line_details d WHERE d.pline_id = p.pline_id AND item_kind = 'ALLOWANCE'),
    total_incentives = (SELECT NVL(SUM(amount), 0) FROM payroll_line_details d WHERE d.pline_id = p.pline_id AND item_kind = 'INCENTIVE'),
    total_diff       = (SELECT NVL(SUM(amount), 0) FROM payroll_line_details d WHERE d.pline_id = p.pline_id AND item_kind = 'DIFF'),
    total_deductions = (SELECT NVL(-SUM(amount), 0) FROM payroll_line_details d WHERE d.pline_id = p.pline_id AND item_kind = 'DEDUCTION'),
    net_salary       = (SELECT NVL(SUM(amount), 0) FROM payroll_line_details d WHERE d.pline_id = p.pline_id)
  WHERE run_id = l_run;

  UPDATE payroll_runs SET total_net = (SELECT NVL(SUM(net_salary), 0) FROM payroll_lines WHERE run_id = l_run)
  WHERE run_id = l_run;

  :P100_RUN_ID := l_run;
  apex_application.g_print_success_message := 'تم احتساب المسير';
END;
