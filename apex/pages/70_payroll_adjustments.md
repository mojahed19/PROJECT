# صفحة 70 - خصم / فرق مبلغ / حافز (JSON) + صفحة 71 القائمة والتقرير

شاشة واحدة لثلاثة أنواع، ويحددها `P70_ADJ_TYPE`. في مستند واحد يمكن إدخال عدة موظفين من شركات فرعية مختلفة.

| النوع | الرمز | الإشارة | أثره على الراتب |
|---|---|---|---|
| خصم | `DED` | دائماً `-` | يُطرح من الراتب |
| فرق مبلغ | `DIFF` | `+` أو `-` يختارها المستخدم | فرق راتب سابق: زيادة أو استرداد |
| حافز | `INC` | دائماً `+` | يُضاف للراتب |

**دورة المستند:**
مسودة (DRAFT) ← معتمد (APPROVED، يعتمده HR أو المدير العام) ← مطبَّق (APPLIED، عند تشغيل مسير رواتب الشهر).
ويمكن إلغاء المستند (CANCELLED) قبل التطبيق.
كل سطر يُحمَّل على **شركة الموظف**، فتظهر التكلفة في ميزانية تلك الشركة الفرعية.

## الشكل

```
┌ حافز ─────────────────────────────────────────────────────────────────────────┐
│ رقم: INC-2026-00004   التاريخ [19/11/2026]   شهر الراتب [2026-11 ▾]          │
│ البند [حافز أداء ▾]   العملة [YER ▾]  السعر [1]                               │
│ السبب [تحقيق المستهدف الشهري_______________________]      الحالة: مسودة       │
├───────────────────────────────────────────────────────────────────────────────┤
│ # │ الموظف              │ الشركة       │ الدرجة │ (+/-) │ المبلغ   │ ملاحظات │
│ 1 │ E0012 أحمد علي      │ الفرعية 1    │ G3     │  +    │ 25,000   │         │
│ 2 │ E0040 سالم محمد     │ الفرعية 2    │ G2     │  +    │ 15,000   │         │
│   │                     │              │        │       │ 40,000   │         │
└───────────────────────────────────────────────────────────────────────────────┘
 [حفظ مسودة]  [اعتماد]  [إلغاء]  [جديد]  [طباعة]
```

**تسلسل Enter:** رقم الموظف (يظهر الاسم والشركة والدرجة تلقائياً) ← الإشارة (في "فرق مبلغ" فقط) ← المبلغ ← الملاحظات ← سطر جديد.

## Region: الرأس (Static ID = `R_HEADER`)

| Item | النوع | ملاحظات |
|---|---|---|
| `P70_ADJ_ID` | Hidden | Value Protected = No |
| `P70_ADJ_TYPE` | Hidden | من الرابط: DED / DIFF / INC |
| `P70_ADJ_NO` | Display Only | |
| `P70_ADJ_DATE` | Date Picker `DD/MM/YYYY` | Default SYSDATE |
| `P70_PAY_PERIOD` | Select List (LOV_PAY_PERIODS) | Default `TO_CHAR(SYSDATE,'YYYYMM')` |
| `P70_ALLOWANCE_ID` | Select List | انظر الاستعلام أدناه |
| `P70_CURRENCY_CODE` | Select List | Default العملة الأساسية |
| `P70_EXCHANGE_RATE` | Number | |
| `P70_REASON` | Text | Required |
| `P70_STATUS` | Display Only | |

**LOV البند** (حسب النوع):
```sql
SELECT name_ar d, allowance_id r
FROM   allowance_types
WHERE  kind = CASE :P70_ADJ_TYPE WHEN 'DED' THEN 'DEDUCTION'
                                 WHEN 'INC' THEN 'INCENTIVE'
                                 ELSE kind END
ORDER  BY name_ar
```

**عنوان الصفحة** `&P70_TITLE.` (Computation):
```sql
CASE :P70_ADJ_TYPE WHEN 'DED' THEN 'خصم' WHEN 'DIFF' THEN 'فرق مبلغ' ELSE 'حافز' END
```

## Region: السطور

```html
<div id="adj_lines"></div>
```

## Ajax Callback: `INIT_DATA`

```sql
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
```

## Ajax Callback: `SAVE_DOC`

`x01` = `DRAFT` (حفظ) أو `APPROVE` (حفظ واعتماد) أو `CANCEL` (إلغاء).

```sql
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
```

## JavaScript: Function and Global Variable Declaration

```javascript
var adj = {
  grid: null,

  init: function () {
    var type   = apex.item('P70_ADJ_TYPE').getValue(),
        status = apex.item('P70_STATUS').getValue() || 'DRAFT',
        fixedSign = type === 'DED' ? '-' : (type === 'INC' ? '+' : null);

    adj.grid = new JsonLines({
      container: '#adj_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'EMPLOYEE_ID', label: 'الموظف', type: 'lov', lov: 'employees', required: true, width: '22em'},
        {name: 'COMPANY',     label: 'الشركة', type: 'display', noSubmit: true, width: '10em'},
        {name: 'GRADE',       label: 'الدرجة', type: 'display', noSubmit: true, width: '5em'},
        {name: 'DIRECTION',   label: '+/-',    type: 'select', nullText: false, width: '5em',
         defaultValue: fixedSign || '+', readonly: !!fixedSign,
         options: [{v: '+', t: '+ إضافة'}, {v: '-', t: '- خصم'}]},
        {name: 'AMOUNT',      label: 'المبلغ', type: 'number', decimals: 2, required: true, total: true, width: '10em'},
        {name: 'NOTES',       label: 'ملاحظات', type: 'text', maxLength: 300}
      ],
      onChange: function (row, col, g) {
        if (col === 'EMPLOYEE_ID') adj.fillEmp(row, g);
      }
    });

    apex.server.process('INIT_DATA', {x01: apex.item('P70_ADJ_ID').getValue()}, {dataType: 'json'})
      .done(function (d) {
        adj.grid.setLov('employees', d.employees);
        d.lines.forEach(function (r) { adj.fillEmp(r, adj.grid); });
        adj.grid.setData(d.lines);
      });

    apex.jQuery('#P70_CURRENCY_CODE, #P70_ADJ_DATE').on('change', function () {
      DocUtil.loadRate('P70_CURRENCY_CODE', 'P70_ADJ_DATE', 'P70_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); adj.save('DRAFT'); }
    });
    EnterNav.first('#R_HEADER');
  },

  // يعرض شركة الموظف ودرجته بجانب اسمه
  fillEmp: function (row, g) {
    var e = g.lovRecord('employees', row.EMPLOYEE_ID);
    row.COMPANY = e ? e.company : null;
    row.GRADE   = e ? e.grade   : null;
  },

  save: function (action) {
    var errs = [];
    if (action !== 'CANCEL') {
      if (!apex.item('P70_PAY_PERIOD').getValue()) errs.push('اختر شهر الراتب');
      if (!apex.item('P70_REASON').getValue())     errs.push('السبب مطلوب');
      errs = errs.concat(adj.grid.validate());
    }
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P70_' + n).getValue(); };
    var doc = {
      header: {
        ADJ_ID: g('ADJ_ID'), ADJ_TYPE: g('ADJ_TYPE'), ADJ_DATE: g('ADJ_DATE'),
        PAY_PERIOD: g('PAY_PERIOD'), ALLOWANCE_ID: g('ALLOWANCE_ID'),
        CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'), REASON: g('REASON')
      },
      lines: adj.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P70_ADJ_ID: d.id}, showWait: true});
      });
    };
    var msg = {APPROVE: 'اعتماد المستند؟ لن يمكن تعديله بعد ذلك', CANCEL: 'إلغاء المستند؟'}[action];
    if (msg) apex.message.confirm(msg, function (ok) { if (ok) go(); });
    else go();
  }
};
```

**Execute when Page Loads:** `adj.init();`

## الأزرار

| الزر | الإجراء | الشرط |
|---|---|---|
| حفظ مسودة (`js-enter`) | `adj.save('DRAFT')` | DRAFT |
| اعتماد | `adj.save('APPROVE')` | DRAFT، Authorization `IS_HR` |
| إلغاء | `adj.save('CANCEL')` | DRAFT و `P70_ADJ_ID` موجود |
| جديد | صفحة 70، Clear Cache، `P70_ADJ_TYPE = &P70_ADJ_TYPE.` | |

## Pre-Rendering: `LOAD_HEADER`

قراءة سجل `payroll_adj` وتعبئة الحقول (نفس نمط صفحة 40).

---

# صفحة 71 - الخصومات والفروقات والحوافز

## Region 1: المستندات (Interactive Report)

```sql
SELECT a.adj_id,
       DECODE(a.adj_type,'DED','خصم','DIFF','فرق مبلغ','INC','حافز') AS "النوع",
       a.adj_no AS "الرقم", a.adj_date AS "التاريخ",
       SUBSTR(a.pay_period,1,4) || '-' || SUBSTR(a.pay_period,5,2) AS "شهر الراتب",
       t.name_ar AS "البند", a.total_amount AS "الإجمالي", a.currency_code AS "العملة",
       a.reason AS "السبب",
       DECODE(a.status,'DRAFT','مسودة','APPROVED','معتمد','APPLIED','مطبَّق','CANCELLED','ملغى') AS "الحالة",
       a.created_by AS "أنشأه", a.approved_by AS "اعتمده"
FROM   payroll_adj a
LEFT JOIN allowance_types t ON t.allowance_id = a.allowance_id
```

Link: صفحة 70 مع `P70_ADJ_ID = #ADJ_ID#` و `P70_ADJ_TYPE = #ADJ_TYPE#` (أضف `a.adj_type` للاستعلام كعمود مخفي).

## Region 2: تقرير صافي التعديلات لكل موظف حسب الشهر (Interactive Report)

يوضح ما سيُضاف أو يُخصم من راتب كل موظف في الشهر، وعلى أي شركة يُحمَّل.

```sql
SELECT c.name_ar  AS "الشركة",
       e.emp_no   AS "رقم الموظف",
       e.name_ar  AS "الموظف",
       g.name_ar  AS "الدرجة",
       a.pay_period AS "الشهر",
       SUM(CASE WHEN a.adj_type = 'INC'  THEN l.amount * a.exchange_rate ELSE 0 END) AS "الحوافز",
       SUM(CASE WHEN a.adj_type = 'DED'  THEN l.amount * a.exchange_rate ELSE 0 END) AS "الخصومات",
       SUM(CASE WHEN a.adj_type = 'DIFF' THEN DECODE(l.direction,'+',1,-1) * l.amount * a.exchange_rate ELSE 0 END) AS "الفروقات",
       SUM(DECODE(l.direction,'+',1,-1) * l.amount * a.exchange_rate) AS "الصافي (بالعملة الأساسية)"
FROM   payroll_adj a
JOIN   payroll_adj_lines l ON l.adj_id = a.adj_id
JOIN   employees  e ON e.employee_id = l.employee_id
JOIN   job_grades g ON g.grade_id    = e.grade_id
JOIN   companies  c ON c.company_id  = l.company_id
WHERE  a.status IN ('APPROVED','APPLIED')
AND    (:P71_PERIOD  IS NULL OR a.pay_period = :P71_PERIOD)
AND    (:P71_COMPANY IS NULL OR l.company_id = :P71_COMPANY)
GROUP  BY c.name_ar, e.emp_no, e.name_ar, g.name_ar, a.pay_period
ORDER  BY c.name_ar, e.emp_no
```

Control Break على "الشركة" مع Sum لكل عمود. هكذا يرى المدير العام كل شركة منفصلة، ثم الإجمالي العام للمجموعة.
