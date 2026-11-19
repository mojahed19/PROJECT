# صفحة 40 - سند القبض / سند الصرف (JSON) + صفحة 41 قائمة السندات

صفحة واحدة للنوعين، ويحدد النوع `P40_VOUCHER_TYPE`: `R` قبض، `P` صرف. الرابط في القائمة يمرّر النوع.

## الشكل

```
┌ سند قبض ───────────────────────────────────────────────────────────────────────┐
│ الشركة [__▾]  رقم السند: RV-2026-00031   التاريخ [19/11/2026]                 │
│ الصندوق/البنك [1101001 الصندوق الرئيسي ▾]  العملة [USD▾]  السعر [530]         │
│ طريقة الدفع (•) نقدي ( ) شيك ( ) تحويل    رقم الشيك [__] تاريخه [__] البنك [__]│
│ استلمنا من [__________________]  البيان [_______________________]             │
├────────────────────────────────────────────────────────────────────────────────┤
│ # │ الحساب المقابل            │ المبلغ     │ شركة مقابلة │ البيان             │
│ 1 │ 1103001 ذمة الفرعية 1     │ 1,200.00   │ الفرعية 1   │ سداد فاتورة 15     │
│   │                           │ 1,200.00   │                                  │
└────────────────────────────────────────────────────────────────────────────────┘
 إجمالي السند: 1,200.00 USD
 [حفظ مسودة]  [حفظ وترحيل]  [طباعة]  [جديد]
```

**القيد الناتج عند الترحيل:**

| | سند قبض | سند صرف |
|---|---|---|
| الصندوق / البنك | **مدين** بالإجمالي | **دائن** بالإجمالي |
| كل سطر (الحساب المقابل) | **دائن** بمبلغه | **مدين** بمبلغه |

نوع القيد `RV` أو `PV`، ورقم القيد هو نفسه رقم السند.

## Region: رأس السند (Static ID = `R_HEADER`)

| Item | النوع | ملاحظات |
|---|---|---|
| `P40_VOUCHER_ID` | Hidden | Value Protected = No |
| `P40_VOUCHER_TYPE` | Hidden | `R` أو `P`، من الرابط |
| `P40_COMPANY_ID` | Select List (LOV_COMPANIES) | Default `&G_COMPANY_ID.` |
| `P40_VOUCHER_NO` | Display Only | |
| `P40_VOUCHER_DATE` | Date Picker `DD/MM/YYYY` | Default SYSDATE |
| `P40_CASH_ACCOUNT_ID` | Select List (LOV_CASH_ACCOUNTS)، **Cascading Parent** = `P40_COMPANY_ID` | استبدل `:G_COMPANY_ID` في الـ LOV بـ `:P40_COMPANY_ID` |
| `P40_CURRENCY_CODE` | Select List | |
| `P40_EXCHANGE_RATE` | Number | |
| `P40_PAY_METHOD` | Radio Group: CASH / CHEQUE / TRANSFER | Default CASH |
| `P40_CHEQUE_NO` ، `P40_CHEQUE_DATE` ، `P40_BANK_NAME` | Text / Date | تظهر بـ DA عندما `P40_PAY_METHOD` ≠ CASH |
| `P40_PARTY_NAME` | Text | Label ديناميكي: "استلمنا من" أو "صرفنا إلى" |
| `P40_DESCRIPTION` | Text | |
| `P40_STATUS` | Display Only | |
| `P40_JOURNAL_ID` | Hidden | لرابط "عرض القيد" |

**عنوان الصفحة:** `&P40_TITLE.`، و `P40_TITLE` Computation:
```sql
CASE :P40_VOUCHER_TYPE WHEN 'R' THEN 'سند قبض' ELSE 'سند صرف' END
```

## Region: السطور

```html
<div id="v_lines"></div>
<div style="margin-top:8px"><b>إجمالي السند:</b> <span id="v_words"></span></div>
```

## Pre-Rendering: `LOAD_HEADER` (Condition: `P40_VOUCHER_ID` Is Not Null)

```sql
DECLARE
  v vouchers%ROWTYPE; l_cnt NUMBER;
BEGIN
  SELECT * INTO v FROM vouchers WHERE voucher_id = :P40_VOUCHER_ID;
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR v.company_id = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = v.company_id);
  IF l_cnt = 0 THEN raise_application_error(-20001, 'ليس لديك صلاحية على هذه الشركة'); END IF;

  :P40_VOUCHER_TYPE    := v.voucher_type;
  :P40_COMPANY_ID      := v.company_id;
  :P40_VOUCHER_NO      := v.voucher_no;
  :P40_VOUCHER_DATE    := TO_CHAR(v.voucher_date, 'DD/MM/YYYY');
  :P40_CASH_ACCOUNT_ID := v.cash_account_id;
  :P40_CURRENCY_CODE   := v.currency_code;
  :P40_EXCHANGE_RATE   := v.exchange_rate;
  :P40_PAY_METHOD      := v.pay_method;
  :P40_CHEQUE_NO       := v.cheque_no;
  :P40_CHEQUE_DATE     := TO_CHAR(v.cheque_date, 'DD/MM/YYYY');
  :P40_BANK_NAME       := v.bank_name;
  :P40_PARTY_NAME      := v.party_name;
  :P40_DESCRIPTION     := v.description;
  :P40_STATUS          := v.status;
  :P40_JOURNAL_ID      := v.journal_id;
END;
```

## Ajax Callback: `INIT_DATA`

نفس كود صفحة 30، مع اختلاف استعلام السطور:

```sql
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
             'ACCOUNT_ID' VALUE account_id, 'AMOUNT' VALUE amount,
             'PARTNER_COMPANY_ID' VALUE partner_company_id, 'DESCRIPTION' VALUE description)
           ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   voucher_lines WHERE voucher_id = TO_NUMBER(apex_application.g_x02);
```

> يُستبعد حساب الصندوق نفسه من قائمة الحسابات المقابلة بإضافة `AND cash_bank = 'N'` إلى استعلام الحسابات. احذف هذا الشرط إذا أردت السماح بالتحويل بين الصناديق بسند.

## Ajax Callback: `SAVE_DOC`

```sql
DECLARE
  l_clob    CLOB := apex_application.g_clob_01;
  l_action  VARCHAR2(10) := apex_application.g_x01;
  l_errs    apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type CHAR(1); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_cash NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_method VARCHAR2(10);
  l_chq_no VARCHAR2(30); l_chq_date_s VARCHAR2(20); l_bank VARCHAR2(100);
  l_party VARCHAR2(150); l_desc VARCHAR2(500);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER;
  l_total  NUMBER := 0; l_lines NUMBER := 0; l_jid NUMBER; l_jt VARCHAR2(10);
  l_drb NUMBER; l_crb NUMBER; l_last NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT h.voucher_id, h.voucher_type, h.company_id, h.voucher_date, h.cash_account_id,
         h.currency_code, h.exchange_rate, h.pay_method, h.cheque_no, h.cheque_date,
         h.bank_name, h.party_name, h.description
  INTO   l_id, l_type, l_company, l_date_s, l_cash, l_cur, l_rate, l_method,
         l_chq_no, l_chq_date_s, l_bank, l_party, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           voucher_id      NUMBER        PATH '$.VOUCHER_ID',
           voucher_type    VARCHAR2(1)   PATH '$.VOUCHER_TYPE',
           company_id      NUMBER        PATH '$.COMPANY_ID',
           voucher_date    VARCHAR2(20)  PATH '$.VOUCHER_DATE',
           cash_account_id NUMBER        PATH '$.CASH_ACCOUNT_ID',
           currency_code   VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate   NUMBER        PATH '$.EXCHANGE_RATE',
           pay_method      VARCHAR2(10)  PATH '$.PAY_METHOD',
           cheque_no       VARCHAR2(30)  PATH '$.CHEQUE_NO',
           cheque_date     VARCHAR2(20)  PATH '$.CHEQUE_DATE',
           bank_name       VARCHAR2(100) PATH '$.BANK_NAME',
           party_name      VARCHAR2(150) PATH '$.PARTY_NAME',
           description     VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  l_jt := CASE l_type WHEN 'R' THEN 'RV' WHEN 'P' THEN 'PV' END;
  IF l_jt IS NULL THEN err('نوع السند غير معروف'); END IF;

  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ السند غير صحيح'); END;

  IF l_company IS NULL THEN err('اختر الشركة'); END IF;
  IF l_cash    IS NULL THEN err('اختر الصندوق أو البنك'); END IF;
  IF l_cur     IS NULL THEN err('اختر العملة'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;
  IF l_method IN ('CHEQUE') AND l_chq_no IS NULL THEN err('أدخل رقم الشيك'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR l_company = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM accounts
  WHERE account_id = l_cash AND cash_bank IN ('C','B') AND is_active = 'Y'
  AND (company_id IS NULL OR company_id = l_company);
  IF l_cnt = 0 THEN err('حساب الصندوق/البنك غير صحيح'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years
    WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, voucher_no INTO l_status, l_no FROM vouchers WHERE voucher_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('السند مرحّل ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('السند غير موجود'); END;
  END IF;

  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
               line_no NUMBER PATH '$.LINE_NO', account_id NUMBER PATH '$.ACCOUNT_ID',
               amount  NUMBER PATH '$.AMOUNT'))) LOOP
    l_lines := l_lines + 1;
    SELECT COUNT(*) INTO l_cnt FROM accounts
    WHERE account_id = r.account_id AND is_postable = 'Y' AND is_active = 'Y'
    AND (company_id IS NULL OR company_id = l_company);
    IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الحساب غير صحيح'); END IF;
    IF r.account_id = l_cash THEN err('السطر ' || r.line_no || ': لا يكون الحساب المقابل هو الصندوق نفسه'); END IF;
    IF NVL(r.amount, 0) <= 0 THEN err('السطر ' || r.line_no || ': المبلغ يجب أن يكون أكبر من صفر'); END IF;
    l_total := l_total + NVL(r.amount, 0);
  END LOOP;
  IF l_lines = 0 THEN err('أدخل سطراً واحداً على الأقل'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ------------------------------------------------------------------ حفظ السند
  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_company AND doc_type = l_jt AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_company, l_jt, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_jt || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO vouchers (company_id, voucher_type, voucher_no, voucher_date, cash_account_id,
                          currency_code, exchange_rate, pay_method, cheque_no, cheque_date,
                          bank_name, party_name, description, created_by)
    VALUES (l_company, l_type, l_no, l_date, l_cash, l_cur, l_rate, l_method, l_chq_no,
            TO_DATE(l_chq_date_s, 'DD/MM/YYYY'), l_bank, l_party, l_desc, :APP_USER)
    RETURNING voucher_id INTO l_id;
  ELSE
    UPDATE vouchers
    SET company_id = l_company, voucher_date = l_date, cash_account_id = l_cash,
        currency_code = l_cur, exchange_rate = l_rate, pay_method = l_method,
        cheque_no = l_chq_no, cheque_date = TO_DATE(l_chq_date_s, 'DD/MM/YYYY'),
        bank_name = l_bank, party_name = l_party, description = l_desc
    WHERE voucher_id = l_id;
    DELETE FROM voucher_lines WHERE voucher_id = l_id;
  END IF;

  INSERT INTO voucher_lines (voucher_id, line_no, account_id, amount, partner_company_id, description)
  SELECT l_id, ROWNUM, account_id, amount, partner_company_id, description
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
         account_id NUMBER PATH '$.ACCOUNT_ID', amount NUMBER PATH '$.AMOUNT',
         partner_company_id NUMBER PATH '$.PARTNER_COMPANY_ID',
         description VARCHAR2(500) PATH '$.DESCRIPTION'));

  UPDATE vouchers SET total_amount = l_total WHERE voucher_id = l_id;

  ------------------------------------------------------------------ الترحيل = إنشاء القيد
  IF l_action = 'POST' THEN
    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, source_id,
                          total_debit, total_credit, created_by, posted_by, posted_on)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate,
            NVL(l_desc, CASE l_type WHEN 'R' THEN 'سند قبض ' ELSE 'سند صرف ' END || l_no),
            l_chq_no, 'POSTED', 'VOUCHER', l_id, l_total, l_total, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_jid;

    -- سطر الصندوق
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 1, l_cash,
            CASE l_type WHEN 'R' THEN l_total ELSE 0 END,
            CASE l_type WHEN 'P' THEN l_total ELSE 0 END,
            CASE l_type WHEN 'R' THEN ROUND(l_total * l_rate, 2) ELSE 0 END,
            CASE l_type WHEN 'P' THEN ROUND(l_total * l_rate, 2) ELSE 0 END,
            l_party);

    -- السطور المقابلة
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, description)
    SELECT l_jid, line_no + 1, account_id,
           CASE l_type WHEN 'P' THEN amount ELSE 0 END,
           CASE l_type WHEN 'R' THEN amount ELSE 0 END,
           CASE l_type WHEN 'P' THEN ROUND(amount * l_rate, 2) ELSE 0 END,
           CASE l_type WHEN 'R' THEN ROUND(amount * l_rate, 2) ELSE 0 END,
           partner_company_id, NVL(description, l_desc)
    FROM voucher_lines WHERE voucher_id = l_id;

    -- فرق التقريب
    SELECT SUM(debit_base), SUM(credit_base) INTO l_drb, l_crb FROM journal_lines WHERE journal_id = l_jid;
    IF l_drb <> l_crb THEN
      SELECT MAX(line_id) INTO l_last FROM journal_lines WHERE journal_id = l_jid AND line_no > 1;
      UPDATE journal_lines
      SET debit_base  = debit_base  + CASE WHEN debit  > 0 THEN l_crb - l_drb ELSE 0 END,
          credit_base = credit_base + CASE WHEN credit > 0 THEN l_drb - l_crb ELSE 0 END
      WHERE line_id = l_last;
    END IF;

    UPDATE vouchers SET status = 'POSTED', journal_id = l_jid WHERE voucher_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل السند ' ELSE 'تم حفظ السند ' END || l_no);
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
var vch = {
  grid: null, companies: [],

  init: function () {
    var status = apex.item('P40_STATUS').getValue() || 'DRAFT';
    vch.grid = new JsonLines({
      container: '#v_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ACCOUNT_ID',  label: 'الحساب المقابل', type: 'lov', lov: 'accounts', required: true, width: '24em'},
        {name: 'AMOUNT',      label: 'المبلغ', type: 'number', decimals: 2, total: true, required: true, width: '10em'},
        {name: 'PARTNER_COMPANY_ID', label: 'شركة مقابلة', type: 'select', width: '12em',
         options: function () { return vch.companies; }},
        {name: 'DESCRIPTION', label: 'البيان', type: 'text', maxLength: 500, ignoreEmpty: true}
      ],
      newRow: function (r) { r.DESCRIPTION = apex.item('P40_DESCRIPTION').getValue() || null; },
      onTotals: function (t) {
        document.getElementById('v_words').textContent =
          JsonLines.fmt(t.AMOUNT || 0, 2) + ' ' + (apex.item('P40_CURRENCY_CODE').getValue() || '');
      }
    });
    vch.load();

    apex.jQuery('#P40_COMPANY_ID').on('change', vch.load);
    apex.jQuery('#P40_CURRENCY_CODE, #P40_VOUCHER_DATE').on('change', function () {
      DocUtil.loadRate('P40_CURRENCY_CODE', 'P40_VOUCHER_DATE', 'P40_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); vch.save('DRAFT'); }
    });
    EnterNav.first('#R_HEADER');
  },

  load: function () {
    var keep = vch.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P40_COMPANY_ID').getValue(),
      x02: apex.item('P40_VOUCHER_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      vch.companies = d.companies;
      vch.grid.setLov('accounts', d.accounts);
      vch.grid.setData(keep.length ? keep : d.lines);
    });
  },

  save: function (action) {
    var errs = [];
    if (!apex.item('P40_CASH_ACCOUNT_ID').getValue()) errs.push('اختر الصندوق أو البنك');
    if (!apex.item('P40_VOUCHER_DATE').getValue())    errs.push('أدخل التاريخ');
    errs = errs.concat(vch.grid.validate());
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P40_' + n).getValue(); };
    var doc = {
      header: {
        VOUCHER_ID: g('VOUCHER_ID'), VOUCHER_TYPE: g('VOUCHER_TYPE'), COMPANY_ID: g('COMPANY_ID'),
        VOUCHER_DATE: g('VOUCHER_DATE'), CASH_ACCOUNT_ID: g('CASH_ACCOUNT_ID'),
        CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'),
        PAY_METHOD: g('PAY_METHOD'), CHEQUE_NO: g('CHEQUE_NO'), CHEQUE_DATE: g('CHEQUE_DATE'),
        BANK_NAME: g('BANK_NAME'), PARTY_NAME: g('PARTY_NAME'), DESCRIPTION: g('DESCRIPTION')
      },
      lines: vch.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P40_VOUCHER_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل السند وإنشاء القيد؟', function (ok) { if (ok) go(); });
    else go();
  }
};
```

**Execute when Page Loads:** `vch.init();`

## الأزرار

| الزر | الإجراء | الشرط |
|---|---|---|
| حفظ مسودة (`js-enter`) | `vch.save('DRAFT')` | DRAFT |
| حفظ وترحيل | `vch.save('POST')` | DRAFT |
| عرض القيد | صفحة 30 مع `P30_JOURNAL_ID = &P40_JOURNAL_ID.` | POSTED |
| عكس | صفحة 60 مع `P60_JOURNAL_ID = &P40_JOURNAL_ID.` | POSTED |
| طباعة | صفحة 42 (Printer Friendly) | `P40_VOUCHER_ID` موجود |
| جديد | صفحة 40، Clear Cache، مع `P40_VOUCHER_TYPE = &P40_VOUCHER_TYPE.` | |

## صفحة 42 - طباعة السند (Page Template = Printer Friendly)

**Classic Report بقالب Value Attribute Pairs (رأس السند):**

```sql
SELECT DECODE(v.voucher_type,'R','سند قبض','سند صرف') AS "النوع",
       v.voucher_no AS "الرقم", TO_CHAR(v.voucher_date,'DD/MM/YYYY') AS "التاريخ",
       c.name_ar AS "الشركة", a.name_ar AS "الصندوق/البنك",
       v.party_name AS "الاسم",
       TO_CHAR(v.total_amount,'FM999G999G999G990D00') || ' ' || v.currency_code AS "المبلغ",
       DECODE(v.pay_method,'CASH','نقداً','CHEQUE','شيك رقم '||v.cheque_no,'TRANSFER','تحويل بنكي') AS "طريقة الدفع",
       v.description AS "البيان"
FROM vouchers v JOIN companies c ON c.company_id = v.company_id
JOIN accounts a ON a.account_id = v.cash_account_id
WHERE v.voucher_id = :P42_VOUCHER_ID
```

**Classic Report (سطور السند):**

```sql
SELECT l.line_no "#", a.account_code "رقم الحساب", a.name_ar "الحساب",
       l.amount "المبلغ", l.description "البيان"
FROM voucher_lines l JOIN accounts a ON a.account_id = l.account_id
WHERE l.voucher_id = :P42_VOUCHER_ID ORDER BY l.line_no
```

أضف Static Content في الأسفل للتوقيعات: المحاسب، أمين الصندوق، المستلم.
**Execute when Page Loads:** `window.print();`

---

# صفحة 41 - قائمة السندات (Interactive Report)

```sql
SELECT v.voucher_id,
       DECODE(v.voucher_type,'R','قبض','صرف') AS "النوع",
       c.name_ar AS "الشركة", v.voucher_no AS "الرقم", v.voucher_date AS "التاريخ",
       a.name_ar AS "الصندوق/البنك", v.party_name AS "الاسم",
       v.total_amount AS "المبلغ", v.currency_code AS "العملة",
       ROUND(v.total_amount * v.exchange_rate, 2) AS "بالعملة الأساسية",
       DECODE(v.pay_method,'CASH','نقدي','CHEQUE','شيك','TRANSFER','تحويل') AS "الطريقة",
       DECODE(v.status,'DRAFT','مسودة','POSTED','مرحّل','REVERSED','معكوس') AS "الحالة",
       v.created_by AS "المستخدم"
FROM vouchers v
JOIN companies c ON c.company_id = v.company_id
JOIN accounts  a ON a.account_id = v.cash_account_id
WHERE (:G_USER_ROLE = 'GM' OR v.company_id = :G_COMPANY_ID
       OR v.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
AND   (:P41_TYPE IS NULL OR v.voucher_type = :P41_TYPE)
```

Link: صفحة 40 مع `P40_VOUCHER_ID = #VOUCHER_ID#`. Aggregate: Sum على "بالعملة الأساسية" مع Control Break على النوع والشركة.
