# صفحة 50 - فاتورة صرف لشركة فرعية / مرتجع (JSON) + صفحة 51 قائمة الفواتير

الشركة الأم تبيع للشركة الفرعية بسعر قائمة الأسعار الخاصة بها، وبوحدات متعددة. صفحة واحدة للنوعين، ويحدد النوع `P50_INVOICE_TYPE`: `SALE` بيع، `RETURN` مرتجع.

## الشكل

```
┌ فاتورة صرف لشركة ──────────────────────────────────────────────────────────────────────┐
│ الشركة الفرعية [الفرعية 1 ▾]  رقم: INV-2026-00007  التاريخ [19/11/2026]               │
│ المخزن [المخزن الرئيسي ▾]  قائمة الأسعار [أسعار الفرعية 1 ▾]  العملة USD  السعر [530] │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ # │ الصنف                 │ الوحدة   │ الكمية │ السعر   │ الخصم  │ الإجمالي          │
│ 1 │ A001 أرز 5 كجم        │ [كرتون▾] │ 10     │ 42.00   │ 0.00   │ 420.00            │
│ 2 │ A002 سكر 1 كجم        │ [حبة ▾]  │ 50     │ 1.10    │ 5.00   │ 50.00             │
│   │                       │          │        │         │ 5.00   │ 470.00            │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ الإجمالي 475.00     خصم إضافي [0.00]     الصافي 470.00                                 │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

**تسلسل Enter:** كود الصنف ← الوحدة (تُختار أصغر وحدة ويُجلب سعرها) ← الكمية ← السعر ← الخصم ← سطر جديد.

## القيود الناتجة عند الترحيل

| | دفاتر الشركة الأم | دفاتر الشركة الفرعية |
|---|---|---|
| **بيع** | مدين: ذمة الفرعية (`company_accounts`) ـــ دائن: `SALES` | مدين: `PURCHASES` ـــ دائن: `INTERCO_AP` |
| **مرتجع** | مدين: `SALES_RETURN` ـــ دائن: ذمة الفرعية | مدين: `INTERCO_AP` ـــ دائن: `PURCHASES` |

كل سطر يحمل `partner_company_id` للطرف الآخر. هذا يسمح باستبعاد المعاملات البينية في الميزانية المجمّعة للمجموعة.

## Region: رأس الفاتورة (Static ID = `R_HEADER`)

| Item | النوع | ملاحظات |
|---|---|---|
| `P50_INVOICE_ID` | Hidden | Value Protected = No |
| `P50_INVOICE_TYPE` | Hidden | SALE / RETURN |
| `P50_CUSTOMER_COMPANY_ID` | Select List (LOV_SUB_COMPANIES) | Required |
| `P50_INVOICE_NO` | Display Only | |
| `P50_INVOICE_DATE` | Date Picker `DD/MM/YYYY` | |
| `P50_WAREHOUSE_ID` | Select List | `SELECT name_ar d, warehouse_id r FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active='Y'` |
| `P50_PRICE_LIST_ID` | Select List | `SELECT name_ar d, price_list_id r FROM price_lists WHERE is_active='Y'` |
| `P50_CURRENCY_CODE` | Display Only | من قائمة الأسعار |
| `P50_EXCHANGE_RATE` | Number | |
| `P50_DISCOUNT_AMOUNT` | Number | خصم إضافي على الفاتورة |
| `P50_DESCRIPTION` | Text | |
| `P50_STATUS` | Display Only | |
| `P50_JOURNAL_ID` | Hidden | |

**Dynamic Action** عند تغيير `P50_CUSTOMER_COMPANY_ID`، من نوع **Set Value** (SQL Statement) إلى `P50_PRICE_LIST_ID`:
```sql
SELECT price_list_id FROM companies WHERE company_id = :P50_CUSTOMER_COMPANY_ID
```

**Dynamic Action** عند تغيير `P50_PRICE_LIST_ID`:

1. Set Value إلى `P50_CURRENCY_CODE`:
   ```sql
   SELECT currency_code FROM price_lists WHERE price_list_id = :P50_PRICE_LIST_ID
   ```
2. Execute JavaScript:
   ```javascript
   inv.loadItems(true);
   DocUtil.loadRate('P50_CURRENCY_CODE','P50_INVOICE_DATE','P50_EXCHANGE_RATE');
   ```

## Region: السطور

```html
<div id="inv_lines"></div>
<div style="margin-top:10px;font-weight:600">
  الإجمالي: <span id="inv_gross">0.00</span> &nbsp;&nbsp;
  الصافي بعد الخصم الإضافي: <span id="inv_net">0.00</span>
</div>
```

## Ajax Callback: `INIT_DATA` (الأصناف بوحداتها وأسعارها + سطور الفاتورة)

`x01` = قائمة الأسعار ، `x02` = رقم الفاتورة

```sql
DECLARE
  l_items CLOB;
  l_lines CLOB;
  l_pl    NUMBER := TO_NUMBER(apex_application.g_x01);
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'id'    VALUE i.item_id,
           'code'  VALUE i.item_code,
           'name'  VALUE i.name_ar,
           'units' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                                   'v'      VALUE u.unit_id,
                                   't'      VALUE un.name_ar,
                                   'factor' VALUE u.factor,
                                   'price'  VALUE p.price) ORDER BY u.factor)
                          FROM   item_units u
                          JOIN   units un ON un.unit_id = u.unit_id
                          LEFT JOIN price_list_items p
                                 ON p.price_list_id = l_pl AND p.item_id = u.item_id AND p.unit_id = u.unit_id
                          WHERE  u.item_id = i.item_id) FORMAT JSON
         ) ORDER BY i.item_code RETURNING CLOB)
  INTO   l_items
  FROM   items i
  WHERE  i.is_active = 'Y'
  AND    EXISTS (SELECT 1 FROM price_list_items p WHERE p.price_list_id = l_pl AND p.item_id = i.item_id);

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'ITEM_ID' VALUE item_id, 'UNIT_ID' VALUE unit_id, 'QTY' VALUE qty,
           'PRICE' VALUE price, 'DISCOUNT' VALUE NULLIF(discount, 0), 'LINE_TOTAL' VALUE line_total)
         ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   invoice_lines WHERE invoice_id = TO_NUMBER(apex_application.g_x02);

  apex_util.prn('{"items":' || COALESCE(l_items, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
```

> الأصناف التي ليس لها سعر في قائمة أسعار الشركة لا تظهر. هذا يمنع صرف صنف بلا سعر.

## Ajax Callback: `SAVE_DOC`

```sql
DECLARE
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type VARCHAR2(10); l_cust NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_wh NUMBER; l_pl NUMBER; l_rate NUMBER; l_disc NUMBER; l_desc VARCHAR2(500);
  l_cur VARCHAR2(3); l_parent NUMBER := :G_PARENT_ID;

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER;
  l_gross NUMBER := 0; l_net NUMBER; l_lines NUMBER := 0; l_factor NUMBER;
  l_jt VARCHAR2(10); l_j1 NUMBER; l_j2 NUMBER; l_ar NUMBER; l_acc NUMBER; l_acc2 NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;

  FUNCTION setting (p_company NUMBER, p_code VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT account_id INTO l FROM account_settings WHERE company_id = p_company AND setting_code = p_code;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20010, 'لم يُعرَّف الحساب الافتراضي ' || p_code || ' للشركة رقم ' || p_company);
  END;

  -- قيد من سطرين (مدين / دائن)
  FUNCTION make_journal (p_company NUMBER, p_dr NUMBER, p_cr NUMBER, p_partner NUMBER) RETURN NUMBER IS
    l_j NUMBER; l_base NUMBER := ROUND(l_net * l_rate, 2);
  BEGIN
    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, status, source_type, source_id, total_debit, total_credit,
                          created_by, posted_by, posted_on)
    VALUES (p_company, l_jt, l_no, l_date, l_cur, l_rate,
            NVL(l_desc, CASE l_type WHEN 'SALE' THEN 'فاتورة صرف ' ELSE 'مرتجع ' END || l_no),
            'POSTED', 'INVOICE', l_id, l_net, l_net, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_j;

    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, partner_company_id)
    VALUES (l_j, 1, p_dr, l_net, 0, l_base, 0, p_partner);
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, partner_company_id)
    VALUES (l_j, 2, p_cr, 0, l_net, 0, l_base, p_partner);
    RETURN l_j;
  END;
BEGIN
  SELECT h.invoice_id, h.invoice_type, h.customer_company_id, h.invoice_date, h.warehouse_id,
         h.price_list_id, h.exchange_rate, NVL(h.discount_amount, 0), h.description
  INTO   l_id, l_type, l_cust, l_date_s, l_wh, l_pl, l_rate, l_disc, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           invoice_id          NUMBER        PATH '$.INVOICE_ID',
           invoice_type        VARCHAR2(10)  PATH '$.INVOICE_TYPE',
           customer_company_id NUMBER        PATH '$.CUSTOMER_COMPANY_ID',
           invoice_date        VARCHAR2(20)  PATH '$.INVOICE_DATE',
           warehouse_id        NUMBER        PATH '$.WAREHOUSE_ID',
           price_list_id       NUMBER        PATH '$.PRICE_LIST_ID',
           exchange_rate       NUMBER        PATH '$.EXCHANGE_RATE',
           discount_amount     NUMBER        PATH '$.DISCOUNT_AMOUNT',
           description         VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  l_jt := CASE l_type WHEN 'SALE' THEN 'INV' WHEN 'RETURN' THEN 'RET' END;
  IF l_jt IS NULL THEN err('نوع الفاتورة غير معروف'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;

  -- الصلاحية: المدير العام أو محاسب الشركة الأم فقط
  IF NOT (:G_USER_ROLE IN ('GM','ACCOUNTANT','STORE') AND :G_COMPANY_ID = l_parent) THEN
    err('فواتير الصرف للشركات تُصدر من الشركة الأم فقط');
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM companies WHERE company_id = l_cust AND is_parent = 'N' AND is_active = 'Y';
  IF l_cnt = 0 THEN err('اختر الشركة الفرعية'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_wh AND company_id = l_parent;
  IF l_cnt = 0 THEN err('اختر مخزناً من مخازن الشركة الأم'); END IF;
  BEGIN
    SELECT currency_code INTO l_cur FROM price_lists WHERE price_list_id = l_pl;
  EXCEPTION WHEN NO_DATA_FOUND THEN err('اختر قائمة الأسعار'); END;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, invoice_no INTO l_status, l_no FROM invoices WHERE invoice_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('الفاتورة مرحّلة ولا يمكن تعديلها'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الفاتورة غير موجودة'); END;
  END IF;

  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
               line_no NUMBER PATH '$.LINE_NO', item_id NUMBER PATH '$.ITEM_ID',
               unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY',
               price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT'))) LOOP
    l_lines := l_lines + 1;
    SELECT COUNT(*) INTO l_cnt FROM item_units WHERE item_id = r.item_id AND unit_id = r.unit_id;
    IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الصنف أو الوحدة غير صحيحة'); END IF;
    IF NVL(r.qty, 0) <= 0 THEN err('السطر ' || r.line_no || ': الكمية يجب أن تكون أكبر من صفر'); END IF;
    IF NVL(r.price, 0) < 0 THEN err('السطر ' || r.line_no || ': السعر غير صحيح'); END IF;
    IF NVL(r.discount, 0) > NVL(r.qty, 0) * NVL(r.price, 0) THEN
      err('السطر ' || r.line_no || ': الخصم أكبر من قيمة السطر');
    END IF;
    l_gross := l_gross + NVL(r.qty, 0) * NVL(r.price, 0) - NVL(r.discount, 0);
  END LOOP;
  IF l_lines = 0 THEN err('أدخل صنفاً واحداً على الأقل'); END IF;
  l_net := l_gross - l_disc;
  IF l_net <= 0 THEN err('صافي الفاتورة يجب أن يكون أكبر من صفر'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ------------------------------------------------------------------ الحفظ
  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_parent AND doc_type = l_jt AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_parent, l_jt, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_jt || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO invoices (company_id, customer_company_id, invoice_type, invoice_no, invoice_date,
                          warehouse_id, price_list_id, currency_code, exchange_rate, description, created_by)
    VALUES (l_parent, l_cust, l_type, l_no, l_date, l_wh, l_pl, l_cur, l_rate, l_desc, :APP_USER)
    RETURNING invoice_id INTO l_id;
  ELSE
    UPDATE invoices SET customer_company_id = l_cust, invoice_date = l_date, warehouse_id = l_wh,
           price_list_id = l_pl, currency_code = l_cur, exchange_rate = l_rate, description = l_desc
    WHERE invoice_id = l_id;
    DELETE FROM invoice_lines WHERE invoice_id = l_id;
  END IF;

  -- الإجمالي يُحسب في الخادم ولا يُعتمد على قيمة المتصفح
  INSERT INTO invoice_lines (invoice_id, line_no, item_id, unit_id, factor, qty, price, discount, line_total)
  SELECT l_id, ROWNUM, j.item_id, j.unit_id, u.factor, j.qty, j.price, NVL(j.discount, 0),
         ROUND(j.qty * j.price - NVL(j.discount, 0), 4)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
           qty NUMBER PATH '$.QTY', price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT')) j
  JOIN   item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id;

  UPDATE invoices SET gross_amount = l_gross, discount_amount = l_disc, net_amount = l_net
  WHERE invoice_id = l_id;

  ------------------------------------------------------------------ الترحيل: قيد الأم + قيد الفرعية
  IF l_action = 'POST' THEN
    BEGIN
      SELECT ar_account_id INTO l_ar FROM company_accounts WHERE company_id = l_cust;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      raise_application_error(-20011, 'لم يُعرَّف حساب ذمة لهذه الشركة الفرعية');
    END;

    IF l_type = 'SALE' THEN
      l_j1 := make_journal(l_parent, l_ar, setting(l_parent, 'SALES'), l_cust);
      l_j2 := make_journal(l_cust, setting(l_cust, 'PURCHASES'), setting(l_cust, 'INTERCO_AP'), l_parent);
    ELSE
      l_j1 := make_journal(l_parent, setting(l_parent, 'SALES_RETURN'), l_ar, l_cust);
      l_j2 := make_journal(l_cust, setting(l_cust, 'INTERCO_AP'), setting(l_cust, 'PURCHASES'), l_parent);
    END IF;

    UPDATE invoices SET status = 'POSTED', journal_id = l_j1, sub_journal_id = l_j2 WHERE invoice_id = l_id;
    -- حركة المخزون (صرف من مخزن الأم) تُضاف في مرحلة المخزون
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE); apex_json.write('id', l_id); apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل الفاتورة ' ELSE 'تم حفظ الفاتورة ' END || l_no);
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
var inv = {
  grid: null,

  units: function (row) {
    var it = inv.grid.lovRecord('items', row.ITEM_ID);
    return it ? it.units : [];
  },

  init: function () {
    var status = apex.item('P50_STATUS').getValue() || 'DRAFT';
    inv.grid = new JsonLines({
      container: '#inv_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ITEM_ID',    label: 'الصنف',    type: 'lov', lov: 'items', required: true, width: '24em'},
        {name: 'UNIT_ID',    label: 'الوحدة',   type: 'select', required: true, nullText: false,
         options: inv.units, width: '8em'},
        {name: 'QTY',        label: 'الكمية',   type: 'number', decimals: 2, required: true, width: '7em'},
        {name: 'PRICE',      label: 'السعر',    type: 'number', decimals: 2, required: true, width: '8em',
         readonlyIf: function () { return apex.item('P50_PRICE_EDIT').getValue() !== 'Y'; }},
        {name: 'DISCOUNT',   label: 'الخصم',    type: 'number', decimals: 2, total: true, width: '7em'},
        {name: 'LINE_TOTAL', label: 'الإجمالي', type: 'display', decimals: 2, total: true, noSubmit: true}
      ],
      onChange: function (row, col) {
        if (col === 'ITEM_ID') {               // أول وحدة (الأصغر) وسعرها
          var u = inv.units(row);
          row.UNIT_ID = u.length ? u[0].v : null;
          col = 'UNIT_ID';
        }
        if (col === 'UNIT_ID') {
          var unit = inv.units(row).filter(function (x) { return String(x.v) === String(row.UNIT_ID); })[0];
          row.PRICE = unit ? unit.price : null;
          if (!row.QTY && row.ITEM_ID) row.QTY = 1;
        }
        row.LINE_TOTAL = (row.QTY || 0) * (row.PRICE || 0) - (row.DISCOUNT || 0);
      },
      onTotals: function (t) {
        var disc = JsonLines.toNum(apex.item('P50_DISCOUNT_AMOUNT').getValue()) || 0;
        document.getElementById('inv_gross').textContent = JsonLines.fmt(t.LINE_TOTAL || 0, 2);
        document.getElementById('inv_net').textContent   = JsonLines.fmt((t.LINE_TOTAL || 0) - disc, 2);
      }
    });
    inv.loadItems(false);

    apex.jQuery('#P50_DISCOUNT_AMOUNT').on('change', function () { inv.grid._totals(); });
    apex.jQuery('#P50_INVOICE_DATE').on('change', function () {
      DocUtil.loadRate('P50_CURRENCY_CODE', 'P50_INVOICE_DATE', 'P50_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); inv.save('DRAFT'); }
    });
    EnterNav.first('#R_HEADER');
  },

  // repriceAll = true عند تغيير قائمة الأسعار: تُعاد أسعار كل السطور
  loadItems: function (repriceAll) {
    var keep = inv.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P50_PRICE_LIST_ID').getValue(),
      x02: apex.item('P50_INVOICE_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      inv.grid.setLov('items', d.items);
      inv.grid.setData(keep.length ? keep : d.lines);
      if (repriceAll) {
        inv.grid.rows.forEach(function (r) { if (r.ITEM_ID) inv.grid.opts.onChange(r, 'UNIT_ID', inv.grid); });
        inv.grid.render();
      }
    });
  },

  save: function (action) {
    var errs = [];
    if (!apex.item('P50_CUSTOMER_COMPANY_ID').getValue()) errs.push('اختر الشركة الفرعية');
    if (!apex.item('P50_WAREHOUSE_ID').getValue())        errs.push('اختر المخزن');
    if (!apex.item('P50_PRICE_LIST_ID').getValue())       errs.push('اختر قائمة الأسعار');
    errs = errs.concat(inv.grid.validate());
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P50_' + n).getValue(); };
    var doc = {
      header: {
        INVOICE_ID: g('INVOICE_ID'), INVOICE_TYPE: g('INVOICE_TYPE'),
        CUSTOMER_COMPANY_ID: g('CUSTOMER_COMPANY_ID'), INVOICE_DATE: g('INVOICE_DATE'),
        WAREHOUSE_ID: g('WAREHOUSE_ID'), PRICE_LIST_ID: g('PRICE_LIST_ID'),
        EXCHANGE_RATE: g('EXCHANGE_RATE'), DISCOUNT_AMOUNT: JsonLines.toNum(g('DISCOUNT_AMOUNT')),
        DESCRIPTION: g('DESCRIPTION')
      },
      lines: inv.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P50_INVOICE_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الفاتورة وإنشاء قيد الأم وقيد الشركة الفرعية؟', function (ok) { if (ok) go(); });
    else go();
  }
};
```

**Execute when Page Loads:** `inv.init();`

**`P50_PRICE_EDIT`** (Hidden، Computation): القيمة `Y` إذا كان للمستخدم صلاحية تعديل السعر، وإلا يُثبَّت سعر القائمة.

```sql
CASE WHEN :G_USER_ROLE = 'GM' THEN 'Y' ELSE 'N' END
```

> **ملاحظة:** في الصفحة يكون السعر للقراءة فقط لغير المدير العام، لكن الخادم يقبل السعر المرسل كما هو. لفرض سعر القائمة في الخادم، أضف هذا التحقق داخل حلقة السطور في `SAVE_DOC`:
>
> ```sql
> IF :G_USER_ROLE <> 'GM' THEN
>   SELECT COUNT(*) INTO l_cnt FROM price_list_items
>   WHERE price_list_id = l_pl AND item_id = r.item_id AND unit_id = r.unit_id AND price = r.price;
>   IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': السعر يختلف عن قائمة الأسعار'); END IF;
> END IF;
> ```

## Pre-Rendering: `LOAD_HEADER`

نفس نمط صفحة 40: قراءة سجل `invoices` وتعبئة الحقول، مع تحويل التاريخ بـ `TO_CHAR(..., 'DD/MM/YYYY')`.

---

# صفحة 51 - قائمة الفواتير (Interactive Report)

```sql
SELECT i.invoice_id,
       DECODE(i.invoice_type,'SALE','صرف','مرتجع') AS "النوع",
       i.invoice_no AS "الرقم", i.invoice_date AS "التاريخ",
       c.name_ar AS "الشركة الفرعية", w.name_ar AS "المخزن",
       i.gross_amount AS "الإجمالي", i.discount_amount AS "الخصم",
       i.net_amount * DECODE(i.invoice_type,'SALE',1,-1) AS "الصافي",
       i.currency_code AS "العملة",
       ROUND(i.net_amount * i.exchange_rate, 2) * DECODE(i.invoice_type,'SALE',1,-1) AS "بالعملة الأساسية",
       DECODE(i.status,'DRAFT','مسودة','POSTED','مرحّلة','REVERSED','معكوسة') AS "الحالة"
FROM invoices i
JOIN companies  c ON c.company_id = i.customer_company_id
JOIN warehouses w ON w.warehouse_id = i.warehouse_id
WHERE (:G_USER_ROLE = 'GM' OR :G_COMPANY_ID IN (i.company_id, i.customer_company_id))
```

تستطيع الشركة الفرعية رؤية الفواتير الصادرة لها فقط، والشركة الأم ترى الكل.
