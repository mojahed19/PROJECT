# صفحة 100 - مسير الرواتب + 101 قسيمة الراتب + 102 توزيع الرواتب على الشركات

**يدار المسير من الشركة الأم**، وتُحمَّل كل تكلفة على الشركة الفرعية التي ينتمي إليها الموظف.

**حساب راتب الموظف:**

```
الأساسي          = أساسي الموظف إن وُجد، وإلا أساسي الدرجة (محوّلاً للعملة الأساسية بسعر آخر الشهر)
+ العلاوات        = علاوة الموظف إن وُجدت، وإلا علاوة الدرجة   (ثابت أو نسبة من الأساسي)
+ الحوافز         = حوافز الدرجة/الموظف + مستندات "حافز" المعتمدة لهذا الشهر
± الفروقات        = مستندات "فرق مبلغ" المعتمدة
− الخصومات        = خصومات الدرجة/الموظف + مستندات "خصم" المعتمدة
= الصافي
```

**القيود عند الاعتماد (نوع `PAY`):**

| الشركة | مدين | دائن |
|---|---|---|
| **كل شركة** (للموظفين التابعين لها) | مصروف الرواتب `SALARY_EXP`، العلاوات (حساب البند أو `SALARY_EXP`)، الحوافز (`INCENTIVE_EXP`)، الفروقات الموجبة (`SALARY_DIFF`) | الخصومات `DEDUCTIONS`، الفروقات السالبة، **والصافي**: `SALARY_PAYABLE` في الأم، أو `INTERCO_AP` (مستحق للأم) في الفرعية |
| **الأم** (عن موظفي كل فرعية) | ذمة الفرعية (`company_accounts`) بالصافي | `SALARY_PAYABLE` بالصافي |

بهذا تتحمل كل فرعية مصروف موظفيها في ميزانيتها، بينما الأم هي التي تصرف الرواتب، وتبقى الأرصدة البينية متقابلة.

## الشكل

```
┌ مسير الرواتب ─────────────────────────────────────────────────────────────────┐
│ الشهر [2026-11 ▾]   الشركة [كل الشركات ▾]   الحالة: مسودة                    │
│ [احتساب / إعادة احتساب]  [اعتماد وإنشاء القيود]  [إلغاء المسير]  [طباعة]       │
├───────────────────────────────────────────────────────────────────────────────┤
│ الشركة    │ الموظف       │ الدرجة │ الأساسي │ علاوات │ حوافز │ فروقات │ خصم │ الصافي │
│ الفرعية 1 │ E0012 أحمد   │ G3     │ 150,000 │ 30,000 │ 25,000│   0    │5,000│200,000 │
│ ...                                                                            │
│ الإجمالي                                                                       │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Items

| Item | النوع | ملاحظات |
|---|---|---|
| `P100_PERIOD` | Select List (LOV_PAY_PERIODS) | Default `TO_CHAR(SYSDATE,'YYYYMM')`. Page Action on Selection = Submit |
| `P100_COMPANY_ID` | Select List (LOV_SUB_COMPANIES + الأم) | Null Display = "كل الشركات". Submit on change |
| `P100_RUN_ID` | Hidden | Computation (Before Header) أدناه |
| `P100_STATUS` | Display Only | |

**Computation (Before Header) لـ `P100_RUN_ID`:**
```sql
SELECT MAX(run_id) FROM payroll_runs
WHERE pay_period = :P100_PERIOD AND NVL(company_id, 0) = NVL(:P100_COMPANY_ID, 0)
AND   status <> 'CANCELLED'
```

**Computation لـ `P100_STATUS`:**
```sql
SELECT status FROM payroll_runs WHERE run_id = :P100_RUN_ID
```

**Authorization الصفحة:** `IS_HR`، و Condition: `:G_COMPANY_ID = :G_PARENT_ID` (المسير من الشركة الأم فقط).

## Region: كشف المسير (Interactive Report)

```sql
SELECT p.pline_id, c.name_ar "الشركة", e.emp_no "الرقم", e.name_ar "الموظف", g.grade_code "الدرجة",
       p.basic_salary "الأساسي", p.total_allowances "العلاوات", p.total_incentives "الحوافز",
       p.total_diff "الفروقات", p.total_deductions "الخصومات", p.net_salary "الصافي",
       e.bank_account "الحساب البنكي"
FROM payroll_lines p
JOIN employees e  ON e.employee_id = p.employee_id
JOIN companies c  ON c.company_id  = p.company_id
JOIN job_grades g ON g.grade_id    = p.grade_id
WHERE p.run_id = :P100_RUN_ID
ORDER BY c.company_code, e.emp_no
```

Sum على كل أعمدة المبالغ، و Control Break على "الشركة"، ورابط على الموظف يفتح صفحة 101.

## الأزرار

| الزر | Request | الشرط |
|---|---|---|
| احتساب / إعادة احتساب | `CALC` | `P100_STATUS` فارغ أو DRAFT |
| اعتماد وإنشاء القيود | `APPROVE` | DRAFT. رسالة تأكيد |
| إلغاء المسير | `CANCEL_RUN` | DRAFT |
| طباعة | صفحة 102 | |

## Validations

**عند CALC: لا يتداخل مع مسير آخر لنفس الشهر**

```sql
DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM payroll_runs
  WHERE pay_period = :P100_PERIOD AND status <> 'CANCELLED'
  AND   NVL(company_id, 0) <> NVL(:P100_COMPANY_ID, 0)
  AND   (company_id IS NULL OR :P100_COMPANY_ID IS NULL OR company_id = :P100_COMPANY_ID);
  RETURN CASE WHEN l_cnt > 0 THEN 'يوجد مسير آخر لهذا الشهر يشمل نفس الشركات' END;
END;
```

**عند CALC و APPROVE: الشهر في سنة مالية مفتوحة**

```sql
DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years
  WHERE LAST_DAY(TO_DATE(:P100_PERIOD || '01', 'YYYYMMDD')) BETWEEN start_date AND end_date AND is_closed = 'N';
  RETURN CASE WHEN l_cnt = 0 THEN 'الشهر خارج سنة مالية مفتوحة' END;
END;
```

## Process 1: `CALC_PAYROLL` (When Button Pressed = CALC)

```sql
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
```

## Process 2: `APPROVE_PAYROLL` (When Button Pressed = APPROVE)

```sql
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
```

## Process 3: `CANCEL_RUN` (When Button Pressed = CANCEL_RUN)

```sql
UPDATE payroll_runs SET status = 'CANCELLED' WHERE run_id = :P100_RUN_ID AND status = 'DRAFT';
```

> لإلغاء مسير **معتمد**: اعكس قيوده من صفحة 60 (مصدرها `PAYROLL`)، ثم أعد مستندات الخصم/الحافز إلى APPROVED يدوياً.

---

## صفحة 101 - قسيمة الراتب (Printer Friendly)

**Item:** `P101_PLINE_ID`.

**Region 1، رأس القسيمة (Value Attribute Pairs):**
```sql
SELECT e.emp_no "رقم الموظف", e.name_ar "الاسم", c.name_ar "الشركة", g.name_ar "الدرجة",
       SUBSTR(r.pay_period,1,4) || '-' || SUBSTR(r.pay_period,5,2) "الشهر",
       TO_CHAR(p.net_salary, 'FM999G999G999G990D00') || ' ' || r.currency_code "الصافي"
FROM payroll_lines p JOIN payroll_runs r ON r.run_id = p.run_id
JOIN employees e ON e.employee_id = p.employee_id
JOIN companies c ON c.company_id = p.company_id
JOIN job_grades g ON g.grade_id = p.grade_id
WHERE p.pline_id = :P101_PLINE_ID
```

**Region 2، البنود (Classic Report):**
```sql
SELECT DECODE(item_kind,'BASIC','الأساسي','ALLOWANCE','علاوة','INCENTIVE','حافز','DIFF','فرق','DEDUCTION','خصم') "النوع",
       description "البند",
       CASE WHEN amount > 0 THEN amount END "استحقاق",
       CASE WHEN amount < 0 THEN -amount END "استقطاع"
FROM payroll_line_details WHERE pline_id = :P101_PLINE_ID
ORDER BY DECODE(item_kind,'BASIC',1,'ALLOWANCE',2,'INCENTIVE',3,'DIFF',4,5)
```

Sum على العمودين.

## صفحة 102 - توزيع الرواتب على الشركات (للمدير العام)

```sql
SELECT c.name_ar "الشركة", COUNT(*) "عدد الموظفين",
       SUM(p.basic_salary) "الأساسي", SUM(p.total_allowances) "العلاوات",
       SUM(p.total_incentives) "الحوافز", SUM(p.total_diff) "الفروقات",
       SUM(p.total_deductions) "الخصومات", SUM(p.net_salary) "الصافي",
       ROUND(100 * RATIO_TO_REPORT(SUM(p.net_salary)) OVER (), 1) "النسبة %"
FROM payroll_lines p
JOIN payroll_runs r ON r.run_id = p.run_id AND r.status = 'APPROVED'
JOIN companies c ON c.company_id = p.company_id
WHERE r.pay_period BETWEEN :P102_FROM AND :P102_TO
GROUP BY c.name_ar
ORDER BY 8 DESC
```

أضف Chart (Pie) على نفس الاستعلام بعمودَي "الشركة" و "الصافي".
