# صفحة 30 - قيد اليومية (JSON) + صفحة 31 قائمة القيود

## الشكل

```
┌ قيد يومية ─────────────────────────────────────────────────────────────────────┐
│ الشركة [الشركة الأم ▾]  نوع القيد [قيد يومية عام ▾]  رقم القيد: JV-2026-00012 │
│ التاريخ [19/11/2026]  العملة [USD ▾]  سعر الصرف [530]  المرجع [____]          │
│ البيان [____________________________________________]   الحالة: مسودة        │
├────────────────────────────────────────────────────────────────────────────────┤
│ # │ الحساب                   │ مدين     │ دائن     │ البيان       │ شركة مقابلة│
│ 1 │ 1101001  الصندوق الرئيسي │ 500.00   │          │ ...          │            │
│ 2 │ 1103001  ذمة الفرعية 1   │          │ 500.00   │ ...          │ الفرعية 1  │
│   │                          │ 500.00   │ 500.00   │ الفرق: 0.00 ✔             │
└────────────────────────────────────────────────────────────────────────────────┘
 [حفظ مسودة Ctrl+S]  [حفظ وترحيل]  [جديد]  [عكس القيد]
```

**تسلسل Enter:** الشركة ← النوع ← التاريخ ← العملة ← السعر ← المرجع ← البيان ← رقم الحساب (يظهر الاسم بجانبه) ← مدين ← دائن ← البيان ← الشركة المقابلة ← سطر جديد تلقائياً.
Enter في خانة الحساب لسطر فارغ يخرج من الجدول إلى زر "حفظ مسودة".

## Page Properties

- **CSS Inline:** لا شيء (التنسيق في `app.css`)
- **Function and Global Variable Declaration:** الكود في قسم JavaScript بالأسفل
- **Execute when Page Loads:** `jv.init();`

## Region 1: رأس القيد (Static Content)

| Item | النوع | Default / Source | ملاحظات |
|---|---|---|---|
| `P30_JOURNAL_ID` | Hidden | | Value Protected = **No** |
| `P30_COMPANY_ID` | Select List (LOV_COMPANIES) | `&G_COMPANY_ID.` | Read Only إذا لم يكن المستخدم GM |
| `P30_JT_CODE` | Select List (LOV_JT_MANUAL) | `JV` | |
| `P30_JOURNAL_NO` | Display Only | | يُعطى عند أول حفظ |
| `P30_JOURNAL_DATE` | Date Picker، Format `DD/MM/YYYY` | `SYSDATE` | |
| `P30_CURRENCY_CODE` | Select List (LOV_CURRENCIES) | العملة الأساسية | |
| `P30_EXCHANGE_RATE` | Number Field | 1 | |
| `P30_REF_NO` | Text Field | | |
| `P30_DESCRIPTION` | Text Field (Width 100%) | | |
| `P30_STATUS` | Display Only | `DRAFT` | Format: `<span class="doc-status doc-status--#P30_STATUS#">...</span>` أو LOV للعرض |
| `P30_SOURCE_TYPE` | Hidden | `MANUAL` | |

**Read Only Condition** على كل الحقول عدا `P30_JOURNAL_ID`: Item `P30_STATUS` Not Equal To `DRAFT`.

Default العملة الأساسية (PL/SQL Expression):
```sql
(SELECT currency_code FROM currencies WHERE is_base = 'Y')
```

## Region 2: السطور (Static Content)

**Source → HTML Code:**

```html
<div id="jv_lines"></div>
<div style="margin-top:8px">الفرق: <span id="jv_diff" class="jv-diff ok">0.00</span></div>
```

## Pre-Rendering Process: تحميل رأس القيد (`LOAD_HEADER`)

- **Server-side Condition:** `P30_JOURNAL_ID` Is Not Null

```sql
DECLARE
  j     journals%ROWTYPE;
  l_cnt NUMBER;
BEGIN
  SELECT * INTO j FROM journals WHERE journal_id = :P30_JOURNAL_ID;

  -- صلاحية الشركة
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE  :G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
     OR  EXISTS (SELECT 1 FROM user_companies
                 WHERE user_name = UPPER(:APP_USER) AND company_id = j.company_id);
  IF l_cnt = 0 THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الشركة');
  END IF;

  :P30_COMPANY_ID    := j.company_id;
  :P30_JT_CODE       := j.jt_code;
  :P30_JOURNAL_NO    := j.journal_no;
  :P30_JOURNAL_DATE  := TO_CHAR(j.journal_date, 'DD/MM/YYYY');
  :P30_CURRENCY_CODE := j.currency_code;
  :P30_EXCHANGE_RATE := j.exchange_rate;
  :P30_REF_NO        := j.ref_no;
  :P30_DESCRIPTION   := j.description;
  :P30_STATUS        := j.status;
  :P30_SOURCE_TYPE   := j.source_type;
END;
```

> القيود الآلية (سند، فاتورة، عكس) تُفتح هنا للعرض فقط. حقل `LOV_JT_MANUAL` لا يحتوي أنواعها، لذلك أضف في Select List خيار **Display Extra Values = Yes**.

## Ajax Callback: `INIT_DATA` (الحسابات + الشركات + سطور القيد)

```sql
DECLARE
  l_acc   CLOB;
  l_comp  CLOB;
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code, 'name' VALUE name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO   l_acc
  FROM   accounts
  WHERE  is_postable = 'Y' AND is_active = 'Y'
  AND    (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  SELECT JSON_ARRAYAGG(JSON_OBJECT('v' VALUE company_id, 't' VALUE name_ar)
                       ORDER BY company_code RETURNING CLOB)
  INTO   l_comp
  FROM   companies WHERE is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
             'ACCOUNT_ID'         VALUE account_id,
             'DEBIT'              VALUE NULLIF(debit, 0),
             'CREDIT'             VALUE NULLIF(credit, 0),
             'DESCRIPTION'        VALUE description,
             'PARTNER_COMPANY_ID' VALUE partner_company_id
           ) ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   journal_lines
  WHERE  journal_id = TO_NUMBER(apex_application.g_x02);

  apex_util.prn('{"accounts":'  || COALESCE(l_acc,   TO_CLOB('[]')) ||
                ',"companies":' || COALESCE(l_comp,  TO_CLOB('[]')) ||
                ',"lines":'     || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
```

## Ajax Callback: `SAVE_DOC` (الحفظ والترحيل من JSON)

`x01` تحمل `DRAFT` (حفظ مسودة) أو `POST` (حفظ وترحيل). و `p_clob_01` تحمل المستند كاملاً.

```sql
DECLARE
  l_clob     CLOB := apex_application.g_clob_01;
  l_action   VARCHAR2(10) := apex_application.g_x01;
  l_errs     apex_t_varchar2 := apex_t_varchar2();

  l_id       NUMBER;
  l_company  NUMBER;
  l_jt       VARCHAR2(10);
  l_date_s   VARCHAR2(20);
  l_date     DATE;
  l_cur      VARCHAR2(3);
  l_rate     NUMBER;
  l_ref      VARCHAR2(50);
  l_desc     VARCHAR2(500);

  l_status   VARCHAR2(10);
  l_no       VARCHAR2(30);
  l_prefix   VARCHAR2(10);
  l_seq      NUMBER;
  l_cnt      NUMBER;
  l_dr       NUMBER := 0;
  l_cr       NUMBER := 0;
  l_drb      NUMBER := 0;
  l_crb      NUMBER := 0;
  l_lines    NUMBER := 0;
  l_last     NUMBER;

  PROCEDURE err (p VARCHAR2) IS
  BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  ---------------------------------------------------------------- قراءة الرأس
  SELECT h.journal_id, h.company_id, h.jt_code, h.journal_date,
         h.currency_code, h.exchange_rate, h.ref_no, h.description
  INTO   l_id, l_company, l_jt, l_date_s, l_cur, l_rate, l_ref, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           journal_id    NUMBER        PATH '$.JOURNAL_ID',
           company_id    NUMBER        PATH '$.COMPANY_ID',
           jt_code       VARCHAR2(10)  PATH '$.JT_CODE',
           journal_date  VARCHAR2(20)  PATH '$.JOURNAL_DATE',
           currency_code VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate NUMBER        PATH '$.EXCHANGE_RATE',
           ref_no        VARCHAR2(50)  PATH '$.REF_NO',
           description   VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  BEGIN
    l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ القيد غير صحيح');
  END;

  ---------------------------------------------------------------- التحقق من الرأس
  IF l_company IS NULL THEN err('اختر الشركة'); END IF;
  IF l_jt      IS NULL THEN err('اختر نوع القيد'); END IF;
  IF l_cur     IS NULL THEN err('اختر العملة'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE  :G_USER_ROLE = 'GM' OR l_company = :G_COMPANY_ID
     OR  EXISTS (SELECT 1 FROM user_companies
                 WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM journal_types
  WHERE  jt_code = l_jt AND manual_allowed = 'Y' AND is_active = 'Y';
  IF l_cnt = 0 THEN err('نوع القيد لا يُدخل يدوياً'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years
    WHERE  l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  -- العملة الأساسية سعرها 1 دائماً
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, journal_no INTO l_status, l_no
      FROM   journals WHERE journal_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('القيد مرحّل ولا يمكن تعديله. استخدم شاشة عكس القيود'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('القيد غير موجود');
    END;
  END IF;

  ---------------------------------------------------------------- التحقق من السطور
  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                 line_no    NUMBER       PATH '$.LINE_NO',
                 account_id NUMBER       PATH '$.ACCOUNT_ID',
                 debit      NUMBER       PATH '$.DEBIT',
                 credit     NUMBER       PATH '$.CREDIT'))) LOOP
    l_lines := l_lines + 1;
    IF r.account_id IS NULL THEN
      err('السطر ' || r.line_no || ': الحساب مطلوب');
    ELSE
      SELECT COUNT(*) INTO l_cnt FROM accounts
      WHERE  account_id = r.account_id AND is_postable = 'Y' AND is_active = 'Y'
      AND    (company_id IS NULL OR company_id = l_company);
      IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الحساب غير تحليلي أو موقوف أو لا يتبع الشركة'); END IF;
    END IF;
    IF NVL(r.debit, 0) < 0 OR NVL(r.credit, 0) < 0 THEN
      err('السطر ' || r.line_no || ': لا تُقبل مبالغ سالبة');
    ELSIF (NVL(r.debit, 0) > 0 AND NVL(r.credit, 0) > 0) OR (NVL(r.debit, 0) = 0 AND NVL(r.credit, 0) = 0) THEN
      err('السطر ' || r.line_no || ': أدخل مبلغاً في المدين أو الدائن فقط');
    END IF;
    l_dr := l_dr + NVL(r.debit, 0);
    l_cr := l_cr + NVL(r.credit, 0);
  END LOOP;

  IF l_lines < 2 THEN err('القيد يحتاج سطرين على الأقل'); END IF;
  IF ROUND(l_dr, 4) <> ROUND(l_cr, 4) THEN
    err('القيد غير متوازن: المدين ' || TO_CHAR(l_dr, 'FM999G999G999G990D00') ||
        ' والدائن ' || TO_CHAR(l_cr, 'FM999G999G999G990D00'));
  END IF;

  ---------------------------------------------------------------- عند وجود أخطاء
  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.write('errors', l_errs);
    apex_json.close_object;
    RETURN;
  END IF;

  ---------------------------------------------------------------- الحفظ
  IF l_id IS NULL THEN
    -- رقم جديد: البادئة-السنة-مسلسل
    SELECT prefix INTO l_prefix FROM journal_types WHERE jt_code = l_jt;
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE  company_id = l_company AND doc_type = l_jt AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no)
      VALUES (l_company, l_jt, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_prefix || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, created_by)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate, l_desc, l_ref, 'DRAFT', 'MANUAL', :APP_USER)
    RETURNING journal_id INTO l_id;
  ELSE
    UPDATE journals
    SET    company_id = l_company, jt_code = l_jt, journal_date = l_date,
           currency_code = l_cur, exchange_rate = l_rate,
           description = l_desc, ref_no = l_ref
    WHERE  journal_id = l_id;
    DELETE FROM journal_lines WHERE journal_id = l_id;
  END IF;

  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit,
                             debit_base, credit_base, partner_company_id, description)
  SELECT l_id, ROWNUM, account_id, NVL(debit, 0), NVL(credit, 0),
         ROUND(NVL(debit, 0) * l_rate, 2), ROUND(NVL(credit, 0) * l_rate, 2),
         partner_company_id, description
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           account_id         NUMBER        PATH '$.ACCOUNT_ID',
           debit              NUMBER        PATH '$.DEBIT',
           credit             NUMBER        PATH '$.CREDIT',
           partner_company_id NUMBER        PATH '$.PARTNER_COMPANY_ID',
           description        VARCHAR2(500) PATH '$.DESCRIPTION'));

  -- فرق التقريب بالعملة الأساسية يُضاف على آخر سطر دائن
  SELECT SUM(debit_base), SUM(credit_base) INTO l_drb, l_crb
  FROM   journal_lines WHERE journal_id = l_id;
  IF l_drb <> l_crb THEN
    SELECT MAX(line_id) INTO l_last FROM journal_lines WHERE journal_id = l_id AND credit > 0;
    UPDATE journal_lines SET credit_base = credit_base + (l_drb - l_crb) WHERE line_id = l_last;
  END IF;

  UPDATE journals
  SET    total_debit = l_dr, total_credit = l_cr,
         status    = CASE WHEN l_action = 'POST' THEN 'POSTED' ELSE 'DRAFT' END,
         posted_by = CASE WHEN l_action = 'POST' THEN :APP_USER END,
         posted_on = CASE WHEN l_action = 'POST' THEN SYSDATE END
  WHERE  journal_id = l_id;

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم حفظ وترحيل القيد ' ELSE 'تم حفظ القيد ' END || l_no);
  apex_json.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.open_array('errors');
    apex_json.write(SQLERRM);
    apex_json.close_array;
    apex_json.close_object;
END;
```

## Ajax Callback: `DELETE_DOC` (حذف مسودة)

```sql
BEGIN
  DELETE FROM journals
  WHERE  journal_id = TO_NUMBER(apex_application.g_x01)
  AND    status = 'DRAFT' AND source_type = 'MANUAL'
  AND    (:G_USER_ROLE = 'GM' OR company_id = :G_COMPANY_ID);
  apex_json.open_object;
  apex_json.write('ok', SQL%ROWCOUNT = 1);
  apex_json.close_object;
END;
```

## JavaScript: Function and Global Variable Declaration

```javascript
var jv = {
  grid: null,
  companies: [],

  init: function () {
    var status = apex.item('P30_STATUS').getValue() || 'DRAFT';

    jv.grid = new JsonLines({
      container: '#jv_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ACCOUNT_ID',  label: 'الحساب', type: 'lov', lov: 'accounts', required: true, width: '24em'},
        {name: 'DEBIT',       label: 'مدين',   type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'CREDIT',      label: 'دائن',   type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'DESCRIPTION', label: 'البيان', type: 'text', maxLength: 500, ignoreEmpty: true},
        {name: 'PARTNER_COMPANY_ID', label: 'شركة مقابلة', type: 'select', width: '12em',
         options: function () { return jv.companies; }}
      ],
      // مدين أو دائن فقط في السطر
      onChange: function (row, col) {
        if (col === 'DEBIT'  && row.DEBIT)  row.CREDIT = null;
        if (col === 'CREDIT' && row.CREDIT) row.DEBIT  = null;
      },
      // السطر الجديد يأخذ بيان السطر السابق أو بيان القيد
      newRow: function (r, g) {
        var prev = g.rows.length ? g.rows[g.rows.length - 1] : null;
        r.DESCRIPTION = (prev && prev.DESCRIPTION) || apex.item('P30_DESCRIPTION').getValue() || null;
      },
      onTotals: function (t) {
        var d = (t.DEBIT || 0) - (t.CREDIT || 0), el = document.getElementById('jv_diff');
        el.textContent = JsonLines.fmt(Math.abs(d), 2) + (Math.abs(d) < 0.005 ? ' ✔' : (d > 0 ? ' (مدين)' : ' (دائن)'));
        el.className = 'jv-diff ' + (Math.abs(d) < 0.005 ? 'ok' : 'bad');
      }
    });

    jv.load();

    // تغيير الشركة يعيد تحميل الحسابات (لكل شركة حساباتها الخاصة + المشتركة)
    apex.jQuery('#P30_COMPANY_ID').on('change', jv.load);
    // تغيير العملة أو التاريخ يجلب سعر الصرف
    apex.jQuery('#P30_CURRENCY_CODE, #P30_JOURNAL_DATE').on('change', function () {
      DocUtil.loadRate('P30_CURRENCY_CODE', 'P30_JOURNAL_DATE', 'P30_EXCHANGE_RATE');
    });
    // Ctrl+S = حفظ مسودة
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); jv.save('DRAFT'); }
    });

    EnterNav.first('#R_HEADER');   // Static ID لمنطقة الرأس
  },

  load: function () {
    var keep = jv.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P30_COMPANY_ID').getValue(),
      x02: apex.item('P30_JOURNAL_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      jv.companies = d.companies;
      jv.grid.setLov('accounts', d.accounts);
      jv.grid.setData(keep.length ? keep : d.lines);
    });
  },

  save: function (action) {
    var errs = [], t = jv.grid.totals();
    if (!apex.item('P30_JT_CODE').getValue())       errs.push('اختر نوع القيد');
    if (!apex.item('P30_JOURNAL_DATE').getValue())  errs.push('أدخل التاريخ');
    if (!apex.item('P30_CURRENCY_CODE').getValue()) errs.push('اختر العملة');
    errs = errs.concat(jv.grid.validate());
    if (Math.abs((t.DEBIT || 0) - (t.CREDIT || 0)) >= 0.005) errs.push('القيد غير متوازن');
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var doc = {
      header: {
        JOURNAL_ID   : apex.item('P30_JOURNAL_ID').getValue(),
        COMPANY_ID   : apex.item('P30_COMPANY_ID').getValue(),
        JT_CODE      : apex.item('P30_JT_CODE').getValue(),
        JOURNAL_DATE : apex.item('P30_JOURNAL_DATE').getValue(),
        CURRENCY_CODE: apex.item('P30_CURRENCY_CODE').getValue(),
        EXCHANGE_RATE: apex.item('P30_EXCHANGE_RATE').getValue(),
        REF_NO       : apex.item('P30_REF_NO').getValue(),
        DESCRIPTION  : apex.item('P30_DESCRIPTION').getValue()
      },
      lines: jv.grid.getData()
    };

    var go = function () {
      DocUtil.save(doc, action, function (d) {
        // إعادة فتح القيد المحفوظ
        apex.page.submit({request: 'RELOAD', set: {P30_JOURNAL_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('بعد الترحيل لا يمكن تعديل القيد. متابعة؟', function (ok) { if (ok) go(); });
    else go();
  },

  remove: function () {
    apex.message.confirm('حذف هذه المسودة نهائياً؟', function (ok) {
      if (!ok) return;
      apex.server.process('DELETE_DOC', {x01: apex.item('P30_JOURNAL_ID').getValue()}, {dataType: 'json'})
        .done(function (d) {
          if (d.ok) apex.navigation.redirect('f?p=&APP_ID.:31:&SESSION.::NO:30');
          else DocUtil.showErrors(['لا يمكن حذف هذا القيد']);
        });
    });
  }
};
```

> أعطِ منطقة الرأس **Static ID** = `R_HEADER`.

## الأزرار

| الزر | Action | Class | الشرط |
|---|---|---|---|
| حفظ مسودة | Defined by DA → `jv.save('DRAFT')` | `js-enter` | `P30_STATUS` = DRAFT أو فارغ |
| حفظ وترحيل | DA → `jv.save('POST')` | Hot | نفس الشرط |
| حذف | DA → `jv.remove()` | | `P30_JOURNAL_ID` موجود و DRAFT |
| جديد | Redirect صفحة 30، Clear Cache 30 | | |
| عكس القيد | Redirect صفحة 60 مع `P60_JOURNAL_ID = &P30_JOURNAL_ID.` | | `P30_STATUS` = POSTED |

**Branch بعد الإرسال (RELOAD):** إلى صفحة 30 بدون Clear Cache. القيمة `P30_JOURNAL_ID` محفوظة في الـ Session.

---

# صفحة 31 - قائمة القيود (Interactive Report)

```sql
SELECT j.journal_id,
       c.name_ar                  AS "الشركة",
       t.name_ar                  AS "النوع",
       j.journal_no               AS "رقم القيد",
       j.journal_date             AS "التاريخ",
       j.currency_code            AS "العملة",
       j.exchange_rate            AS "السعر",
       j.total_debit              AS "الإجمالي",
       j.total_debit * j.exchange_rate AS "الإجمالي بالأساسية",
       j.description              AS "البيان",
       DECODE(j.status,'DRAFT','مسودة','POSTED','مرحّل','REVERSED','معكوس') AS "الحالة",
       DECODE(j.source_type,'MANUAL','يدوي','VOUCHER','سند','INVOICE','فاتورة',
              'PAYROLL','رواتب','REVERSAL','عكس','OPENING','افتتاحي') AS "المصدر",
       j.created_by               AS "المستخدم"
FROM   journals j
JOIN   companies c     ON c.company_id = j.company_id
JOIN   journal_types t ON t.jt_code    = j.jt_code
WHERE  (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
        OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
AND    (:P31_COMPANY_ID IS NULL OR j.company_id = :P31_COMPANY_ID)
AND    j.journal_date BETWEEN NVL(TO_DATE(:P31_FROM,'DD/MM/YYYY'), DATE '1900-01-01')
                          AND NVL(TO_DATE(:P31_TO,'DD/MM/YYYY'),   DATE '2999-12-31')
```

- **Link Column:** صفحة 30، `P30_JOURNAL_ID = #JOURNAL_ID#`، Clear Cache 30.
- **Items:** `P31_COMPANY_ID` (LOV_COMPANIES، فارغ = الكل) و `P31_FROM` و `P31_TO`.
- **Control Break** اختياري على "الشركة" ليرى المدير العام كل شركة منفصلة.
