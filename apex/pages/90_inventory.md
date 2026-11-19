# صفحة 90 - حركات المخزون (JSON) + 91 القائمة + 92 الأرصدة + 93 كارت الصنف

**نظام الجرد:** جرد مستمر بمتوسط التكلفة. الكميات تُحفظ بالوحدة الأساسية، والتكلفة بالعملة الأساسية.

| النوع | `P90_TRANS_TYPE` | أثره على الكمية | القيد عند الترحيل |
|---|---|---|---|
| استلام من مورد | `RECEIPT` | + المخزن | مدين `INVENTORY` / دائن الحساب المقابل (المورد) بالتكلفة |
| صرف داخلي | `ISSUE` | − المخزن | مدين الحساب المقابل (مصروف) / دائن `INVENTORY` بمتوسط التكلفة |
| تحويل بين مخازن | `TRANSFER` | − المصدر، + الوجهة | لا قيد (نفس الشركة ونفس الحساب) |
| تسوية جرد | `COUNT` | الفعلي − الدفتري | الفرق بين `INVENTORY` و `INVENTORY_ADJ` |

حركات `INV_OUT` و `INV_IN` و `POS` تُنشأ آلياً من الفواتير ونقاط البيع، ولا تُدخل من هذه الشاشة.

## الشكل

```
┌ استلام بضاعة ────────────────────────────────────────────────────────────────┐
│ الشركة [الأم▾]  رقم: RECEIPT-2026-00009   التاريخ [19/11/2026]              │
│ المخزن [الرئيسي▾]  إلى مخزن [—] (للتحويل)  الحساب المقابل [2101001 موردون▾] │
│ العملة [USD▾]  السعر [530]  البيان [_______________________]                │
├──────────────────────────────────────────────────────────────────────────────┤
│ # │ الصنف            │ الوحدة  │ الرصيد الحالي │ الكمية │ تكلفة الوحدة │ القيمة │
│ 1 │ A001 أرز 5 كجم   │ كرتون▾  │ 120 حبة       │ 50     │ 8.00         │ 400.00 │
└──────────────────────────────────────────────────────────────────────────────┘
```

في **تسوية الجرد** يصبح عنوان العمود "الكمية الفعلية"، ويُحسب الفرق في الخادم.

## Region: الرأس (Static ID = `R_HEADER`)

| Item | النوع | ملاحظات |
|---|---|---|
| `P90_TRANS_ID` | Hidden | Value Protected = No |
| `P90_TRANS_TYPE` | Hidden | من الرابط |
| `P90_COMPANY_ID` | Select List (LOV_COMPANIES) | Default `&G_COMPANY_ID.` |
| `P90_TRANS_NO` | Display Only | |
| `P90_TRANS_DATE` | Date Picker `DD/MM/YYYY` | |
| `P90_WAREHOUSE_ID` | Select List، Cascading Parent = `P90_COMPANY_ID` | `SELECT name_ar d, warehouse_id r FROM warehouses WHERE company_id = :P90_COMPANY_ID AND is_active='Y'` |
| `P90_TO_WAREHOUSE_ID` | Select List | نفس الاستعلام. يظهر في TRANSFER فقط |
| `P90_COUNTER_ACCOUNT_ID` | Popup LOV للحسابات التحليلية | يظهر في RECEIPT و ISSUE |
| `P90_CURRENCY_CODE` ، `P90_EXCHANGE_RATE` | | يظهران في RECEIPT فقط. في غيره القيمة الأساسية و 1 |
| `P90_DESCRIPTION` | Text | |
| `P90_STATUS` | Display Only | |

## Region: السطور

```html
<div id="st_lines"></div>
```

## Ajax Callback: `INIT_DATA`

`x01` = المخزن ، `x02` = رقم الحركة

```sql
DECLARE
  l_items CLOB; l_lines CLOB;
  l_wh NUMBER := TO_NUMBER(apex_application.g_x01);
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'id' VALUE i.item_id, 'code' VALUE i.item_code, 'name' VALUE i.name_ar,
           'bal'  VALUE NVL(b.qty_base, 0),
           'cost' VALUE NVL(b.avg_cost, 0),
           'units' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('v' VALUE u.unit_id, 't' VALUE un.name_ar,
                                                           'factor' VALUE u.factor) ORDER BY u.factor)
                          FROM item_units u JOIN units un ON un.unit_id = u.unit_id
                          WHERE u.item_id = i.item_id) FORMAT JSON
         ) ORDER BY i.item_code RETURNING CLOB)
  INTO   l_items
  FROM   items i
  LEFT JOIN v_stock_balance b ON b.item_id = i.item_id AND b.warehouse_id = l_wh
  WHERE  i.is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT('ITEM_ID' VALUE item_id, 'UNIT_ID' VALUE unit_id,
                                   'QTY' VALUE qty, 'UNIT_COST' VALUE NULLIF(unit_cost, 0))
                       ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   stock_trans_lines
  WHERE  trans_id = TO_NUMBER(apex_application.g_x02)
  AND    (warehouse_id = l_wh OR l_wh IS NULL)          -- في التحويل: سطور المصدر فقط
  AND    (qty_base < 0 OR (SELECT trans_type FROM stock_trans WHERE trans_id = TO_NUMBER(apex_application.g_x02)) <> 'TRANSFER');

  apex_util.prn('{"items":' || COALESCE(l_items, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
```

> في تسوية الجرد، `QTY` المحفوظة هي الكمية الفعلية التي أدخلها المستخدم.

## Ajax Callback: `SAVE_DOC`

```sql
DECLARE
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type VARCHAR2(10); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_wh NUMBER; l_to_wh NUMBER; l_counter NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_desc VARCHAR2(500);
  l_base_cur VARCHAR2(3);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER; l_lines NUMBER := 0;
  l_jid NUMBER; l_val NUMBER; l_inv NUMBER; l_adj NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;

  FUNCTION setting (p_code VARCHAR2) RETURN NUMBER IS l NUMBER;
  BEGIN
    SELECT account_id INTO l FROM account_settings WHERE company_id = l_company AND setting_code = p_code;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20010, 'لم يُعرَّف الحساب الافتراضي ' || p_code);
  END;

  PROCEDURE jline (p_no NUMBER, p_acc NUMBER, p_amount NUMBER) IS   -- موجب = مدين ، سالب = دائن
  BEGIN
    IF ROUND(p_amount, 2) = 0 THEN RETURN; END IF;
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, p_no, p_acc,
            GREATEST(ROUND(p_amount, 2), 0), GREATEST(-ROUND(p_amount, 2), 0),
            GREATEST(ROUND(p_amount, 2), 0), GREATEST(-ROUND(p_amount, 2), 0), l_desc);
  END;
BEGIN
  SELECT h.trans_id, h.trans_type, h.company_id, h.trans_date, h.warehouse_id, h.to_warehouse_id,
         h.counter_account_id, h.currency_code, h.exchange_rate, h.description
  INTO   l_id, l_type, l_company, l_date_s, l_wh, l_to_wh, l_counter, l_cur, l_rate, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           trans_id NUMBER PATH '$.TRANS_ID', trans_type VARCHAR2(10) PATH '$.TRANS_TYPE',
           company_id NUMBER PATH '$.COMPANY_ID', trans_date VARCHAR2(20) PATH '$.TRANS_DATE',
           warehouse_id NUMBER PATH '$.WAREHOUSE_ID', to_warehouse_id NUMBER PATH '$.TO_WAREHOUSE_ID',
           counter_account_id NUMBER PATH '$.COUNTER_ACCOUNT_ID',
           currency_code VARCHAR2(3) PATH '$.CURRENCY_CODE', exchange_rate NUMBER PATH '$.EXCHANGE_RATE',
           description VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  SELECT currency_code INTO l_base_cur FROM currencies WHERE is_base = 'Y';
  IF l_type <> 'RECEIPT' OR l_cur IS NULL THEN l_cur := l_base_cur; l_rate := 1; END IF;
  IF l_cur = l_base_cur THEN l_rate := 1; END IF;

  IF l_type NOT IN ('RECEIPT','ISSUE','TRANSFER','COUNT') OR l_type IS NULL THEN err('نوع الحركة غير صحيح'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR l_company = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_wh AND company_id = l_company;
  IF l_cnt = 0 THEN err('اختر مخزناً تابعاً للشركة'); END IF;
  IF l_type = 'TRANSFER' THEN
    SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_to_wh AND company_id = l_company;
    IF l_cnt = 0 OR l_to_wh = l_wh THEN err('اختر مخزن الوجهة (مختلف عن المصدر)'); END IF;
  END IF;
  IF l_type IN ('RECEIPT','ISSUE') AND l_counter IS NULL THEN err('اختر الحساب المقابل'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, trans_no INTO l_status, l_no FROM stock_trans WHERE trans_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('الحركة مرحّلة ولا يمكن تعديلها'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الحركة غير موجودة'); END;
  END IF;

  -- التحقق من السطور + كفاية الرصيد للصادر (مجمّع حسب الصنف)
  FOR r IN (SELECT j.line_no, j.item_id, j.unit_id, j.qty, j.unit_cost, u.factor
            FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                   line_no NUMBER PATH '$.LINE_NO', item_id NUMBER PATH '$.ITEM_ID',
                   unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY',
                   unit_cost NUMBER PATH '$.UNIT_COST')) j
            LEFT JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id) LOOP
    l_lines := l_lines + 1;
    IF r.factor IS NULL THEN err('السطر ' || r.line_no || ': الصنف أو الوحدة غير صحيحة'); END IF;
    IF r.qty IS NULL OR r.qty < 0 OR (r.qty = 0 AND l_type <> 'COUNT') THEN
      err('السطر ' || r.line_no || ': الكمية غير صحيحة');
    END IF;
    IF l_type = 'RECEIPT' AND NVL(r.unit_cost, 0) <= 0 THEN err('السطر ' || r.line_no || ': أدخل تكلفة الوحدة'); END IF;
  END LOOP;
  IF l_lines = 0 THEN err('أدخل صنفاً واحداً على الأقل'); END IF;

  IF l_type IN ('ISSUE','TRANSFER') AND l_action = 'POST' THEN
    FOR r IN (SELECT j.item_id, i.item_code, SUM(j.qty * u.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                     item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY')) j
              JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
              JOIN items i ON i.item_id = j.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
              GROUP BY j.item_id, i.item_code) LOOP
      IF r.need > r.bal THEN
        err('الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي للكمية ' || r.need);
      END IF;
    END LOOP;
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ---------------------------------------------------------------- الحفظ
  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_company AND doc_type = SUBSTR(l_type, 1, 10) AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_company, l_type, EXTRACT(YEAR FROM l_date), 1); l_seq := 1;
    END IF;
    l_no := l_type || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, to_warehouse_id,
                             counter_account_id, currency_code, exchange_rate, description, created_by)
    VALUES (l_company, l_type, l_no, l_date, l_wh, l_to_wh, l_counter, l_cur, l_rate, l_desc, :APP_USER)
    RETURNING trans_id INTO l_id;
  ELSE
    UPDATE stock_trans SET company_id = l_company, trans_date = l_date, warehouse_id = l_wh,
           to_warehouse_id = l_to_wh, counter_account_id = l_counter, currency_code = l_cur,
           exchange_rate = l_rate, description = l_desc
    WHERE trans_id = l_id;
    DELETE FROM stock_trans_lines WHERE trans_id = l_id;
  END IF;

  -- سطور المصدر (أو الوجهة في الاستلام)
  --  RECEIPT : + بالتكلفة المدخلة  |  ISSUE/TRANSFER : − بمتوسط التكلفة  |  COUNT : الفعلي − الرصيد
  INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                 qty_base, unit_cost, cost_base, value_base)
  SELECT l_id, ROWNUM, l_wh, j.item_id, j.unit_id, u.factor, j.qty,
         x.qty_base, NVL(j.unit_cost, 0), x.cost_base, ROUND(x.qty_base * x.cost_base, 4)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
           qty NUMBER PATH '$.QTY', unit_cost NUMBER PATH '$.UNIT_COST')) j
  JOIN   item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
  LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
  CROSS APPLY (SELECT
         CASE l_type WHEN 'RECEIPT' THEN j.qty * u.factor
                     WHEN 'COUNT'   THEN j.qty * u.factor - NVL(b.qty_base, 0)
                     ELSE -(j.qty * u.factor) END AS qty_base,
         CASE l_type WHEN 'RECEIPT' THEN NVL(j.unit_cost, 0) * l_rate / u.factor
                     ELSE NVL(b.avg_cost, 0) END AS cost_base
         FROM dual) x;

  -- التحويل: سطور الوجهة بنفس التكلفة
  IF l_type = 'TRANSFER' THEN
    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT trans_id, line_no + 1000, l_to_wh, item_id, unit_id, factor, qty,
           -qty_base, unit_cost, cost_base, -value_base
    FROM   stock_trans_lines WHERE trans_id = l_id AND warehouse_id = l_wh;
  END IF;

  ---------------------------------------------------------------- الترحيل
  IF l_action = 'POST' THEN
    SELECT SUM(value_base) INTO l_val FROM stock_trans_lines WHERE trans_id = l_id AND warehouse_id = l_wh;

    IF l_type <> 'TRANSFER' AND ROUND(NVL(l_val, 0), 2) <> 0 THEN
      INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                            description, status, source_type, source_id, created_by, posted_by, posted_on)
      VALUES (l_company, 'ADJ', l_no, l_date, l_base_cur, 1, NVL(l_desc, l_no), 'POSTED', 'MANUAL', l_id,
              :APP_USER, :APP_USER, SYSDATE)
      RETURNING journal_id INTO l_jid;

      l_inv := setting('INVENTORY');
      jline(1, l_inv, l_val);                                       -- المخزون: + وارد / − صادر
      IF l_type = 'COUNT' THEN
        jline(2, setting('INVENTORY_ADJ'), -l_val);                 -- فروقات الجرد
      ELSE
        jline(2, l_counter, -l_val);                                -- المورد أو المصروف
      END IF;

      UPDATE journals SET total_debit  = (SELECT SUM(debit)  FROM journal_lines WHERE journal_id = l_jid),
                          total_credit = (SELECT SUM(credit) FROM journal_lines WHERE journal_id = l_jid)
      WHERE journal_id = l_jid;
    END IF;

    UPDATE stock_trans SET status = 'POSTED', journal_id = l_jid WHERE trans_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE); apex_json.write('id', l_id); apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل الحركة ' ELSE 'تم حفظ الحركة ' END || l_no);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
```

> **ملاحظة:** قيد المخزون يُسجَّل بنوع `ADJ` وبرقم الحركة. إذا أردت نوعاً مستقلاً، أضف نوع قيد `STK` في شاشة أنواع القيود، واستبدل `'ADJ'` به.
> **ملاحظة:** في تسوية الجرد يُقرأ الرصيد الدفتري لحظة الحفظ. لذلك احفظ ورحّل في نفس الوقت، أو أعد الحفظ قبل الترحيل.

## JavaScript: Function and Global Variable Declaration

```javascript
var stk = {
  grid: null,

  unitsOf: function (row, g) { var it = (g || stk.grid).lovRecord('items', row.ITEM_ID); return it ? it.units : []; },
  factorOf: function (row) {
    var u = stk.unitsOf(row).filter(function (x) { return String(x.v) === String(row.UNIT_ID); })[0];
    return u ? u.factor : 1;
  },

  init: function () {
    var type = apex.item('P90_TRANS_TYPE').getValue(),
        status = apex.item('P90_STATUS').getValue() || 'DRAFT';

    stk.grid = new JsonLines({
      container: '#st_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ITEM_ID',   label: 'الصنف',  type: 'lov', lov: 'items', required: true, width: '24em'},
        {name: 'UNIT_ID',   label: 'الوحدة', type: 'select', nullText: false, required: true, options: stk.unitsOf, width: '8em'},
        {name: 'BAL',       label: 'الرصيد الحالي', type: 'display', decimals: 2, noSubmit: true, width: '8em'},
        {name: 'QTY',       label: type === 'COUNT' ? 'الكمية الفعلية' : 'الكمية',
         type: 'number', decimals: 2, required: true, width: '8em'},
        {name: 'UNIT_COST', label: 'تكلفة الوحدة', type: 'number', decimals: 4, width: '9em',
         hidden: type !== 'RECEIPT'},
        {name: 'VALUE',     label: 'القيمة', type: 'display', decimals: 2, total: true, noSubmit: true,
         hidden: type !== 'RECEIPT'}
      ],
      onChange: function (row, col) {
        if (col === 'ITEM_ID') { var u = stk.unitsOf(row); row.UNIT_ID = u.length ? u[0].v : null; }
        var it = stk.grid.lovRecord('items', row.ITEM_ID);
        row.BAL = it ? it.bal / stk.factorOf(row) : null;           // الرصيد بالوحدة المختارة
        row.VALUE = (row.QTY || 0) * (row.UNIT_COST || 0);
      }
    });
    stk.load();
    apex.jQuery('#P90_WAREHOUSE_ID').on('change', stk.load);
    apex.jQuery('#P90_CURRENCY_CODE, #P90_TRANS_DATE').on('change', function () {
      DocUtil.loadRate('P90_CURRENCY_CODE', 'P90_TRANS_DATE', 'P90_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); stk.save('DRAFT'); }
    });
    EnterNav.first('#R_HEADER');
  },

  load: function () {
    var keep = stk.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P90_WAREHOUSE_ID').getValue(), x02: apex.item('P90_TRANS_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      stk.grid.setLov('items', d.items);
      var rows = keep.length ? keep : d.lines;
      rows.forEach(function (r) { stk.grid.opts.onChange(r, 'QTY', stk.grid); });
      stk.grid.setData(rows);
    });
  },

  save: function (action) {
    var errs = stk.grid.validate();
    if (!apex.item('P90_WAREHOUSE_ID').getValue()) errs.unshift('اختر المخزن');
    if (errs.length) { DocUtil.showErrors(errs); return; }
    var g = function (n) { return apex.item('P90_' + n).getValue(); };
    var doc = {
      header: {TRANS_ID: g('TRANS_ID'), TRANS_TYPE: g('TRANS_TYPE'), COMPANY_ID: g('COMPANY_ID'),
               TRANS_DATE: g('TRANS_DATE'), WAREHOUSE_ID: g('WAREHOUSE_ID'), TO_WAREHOUSE_ID: g('TO_WAREHOUSE_ID'),
               COUNTER_ACCOUNT_ID: g('COUNTER_ACCOUNT_ID'), CURRENCY_CODE: g('CURRENCY_CODE'),
               EXCHANGE_RATE: g('EXCHANGE_RATE'), DESCRIPTION: g('DESCRIPTION')},
      lines: stk.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P90_TRANS_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الحركة؟', function (ok) { if (ok) go(); }); else go();
  }
};
```

**Execute when Page Loads:** `stk.init();`
**الأزرار:** حفظ مسودة (`js-enter`)، حفظ وترحيل، جديد. نفس شروط الشاشات السابقة.

---

## صفحة 91 - قائمة حركات المخزون (Interactive Report)

```sql
SELECT t.trans_id, c.name_ar "الشركة",
       DECODE(t.trans_type,'RECEIPT','استلام','ISSUE','صرف','TRANSFER','تحويل','COUNT','تسوية جرد',
                           'INV_OUT','صرف لشركة','INV_IN','وارد من الأم','POS','نقاط بيع') "النوع",
       t.trans_no "الرقم", t.trans_date "التاريخ", w.name_ar "المخزن", w2.name_ar "إلى مخزن",
       (SELECT SUM(ABS(value_base)) FROM stock_trans_lines l
        WHERE l.trans_id = t.trans_id AND l.warehouse_id = t.warehouse_id) "القيمة",
       DECODE(t.status,'DRAFT','مسودة','POSTED','مرحّلة','REVERSED','معكوسة') "الحالة"
FROM stock_trans t
JOIN companies c ON c.company_id = t.company_id
JOIN warehouses w ON w.warehouse_id = t.warehouse_id
LEFT JOIN warehouses w2 ON w2.warehouse_id = t.to_warehouse_id
WHERE (:G_USER_ROLE = 'GM' OR t.company_id = :G_COMPANY_ID)
```

## صفحة 92 - أرصدة المخزون (Interactive Report)

```sql
SELECT c.name_ar "الشركة", w.name_ar "المخزن", i.item_code "الكود", i.name_ar "الصنف",
       ub.name_ar "الوحدة الأساسية",
       b.qty_base "الرصيد",
       (SELECT LISTAGG(TRUNC(b.qty_base / u.factor) || ' ' || un.name_ar, ' + ') WITHIN GROUP (ORDER BY u.factor DESC)
        FROM item_units u JOIN units un ON un.unit_id = u.unit_id
        WHERE u.item_id = i.item_id AND u.factor > 1) "بالوحدات الكبرى",
       ROUND(b.avg_cost, 4) "متوسط التكلفة",
       ROUND(b.qty_base * b.avg_cost, 2) "قيمة المخزون",
       CASE WHEN b.qty_base <= i.reorder_level THEN 'تحت حد الطلب' END "تنبيه"
FROM v_stock_balance b
JOIN items i ON i.item_id = b.item_id
JOIN units ub ON ub.unit_id = i.base_unit_id
JOIN warehouses w ON w.warehouse_id = b.warehouse_id
JOIN companies c ON c.company_id = b.company_id
WHERE (:G_USER_ROLE = 'GM' OR b.company_id = :G_COMPANY_ID)
AND   b.qty_base <> 0
```

Highlight أحمر عندما يكون "تنبيه" غير فارغ، و Sum على "قيمة المخزون" مع Control Break على الشركة.

## صفحة 93 - كارت الصنف (حركة صنف)

**Items:** `P93_ITEM_ID` (Popup LOV)، `P93_WAREHOUSE_ID`، `P93_FROM`، `P93_TO`.

```sql
SELECT t.trans_date "التاريخ", t.trans_no "رقم الحركة",
       DECODE(t.trans_type,'RECEIPT','استلام','ISSUE','صرف','TRANSFER','تحويل','COUNT','جرد',
                           'INV_OUT','صرف لشركة','INV_IN','وارد من الأم','POS','مبيعات') "النوع",
       CASE WHEN l.qty_base > 0 THEN l.qty_base END "وارد",
       CASE WHEN l.qty_base < 0 THEN -l.qty_base END "صادر",
       SUM(l.qty_base) OVER (ORDER BY t.trans_date, t.trans_id, l.line_id ROWS UNBOUNDED PRECEDING) "الرصيد",
       ROUND(l.cost_base, 4) "التكلفة"
FROM stock_trans_lines l
JOIN stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED'
WHERE l.item_id = :P93_ITEM_ID
AND   l.warehouse_id = :P93_WAREHOUSE_ID
ORDER BY t.trans_date, t.trans_id, l.line_id
```

---

## ربط فواتير الصرف (صفحة 50) بالمخزون

### 1. إضافة حقل في رأس الفاتورة

`P50_TO_WAREHOUSE_ID`: مخزن الشركة الفرعية المستلِم (Select List، Cascading Parent = `P50_CUSTOMER_COMPANY_ID`):

```sql
SELECT name_ar d, warehouse_id r FROM warehouses
WHERE company_id = :P50_CUSTOMER_COMPANY_ID AND is_active = 'Y'
```

أضف `TO_WAREHOUSE_ID: g('TO_WAREHOUSE_ID')` إلى `doc.header` في JavaScript.

### 2. تعديلات `SAVE_DOC` في صفحة 50

**(أ) في قسم DECLARE أضف:**

```sql
  l_to_wh NUMBER; l_so NUMBER; l_si NUMBER; l_cogs NUMBER; l_cogs_acc NUMBER; l_inv_acc NUMBER;
```

**(ب) أضف إلى JSON_TABLE الرأس:**

```sql
           to_warehouse_id     NUMBER        PATH '$.TO_WAREHOUSE_ID',
```

ثم أضف `h.to_warehouse_id` إلى قائمة SELECT، و `l_to_wh` إلى قائمة INTO.

**(ج) أضف التحققات قبل `IF l_errs.COUNT > 0`:**

```sql
  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_to_wh AND company_id = l_cust;
  IF l_cnt = 0 THEN err('اختر مخزن الشركة الفرعية المستلِم'); END IF;

  -- كفاية الرصيد في مخزن المصدر (مخزن الأم في البيع، ومخزن الفرعية في المرتجع)
  IF l_action = 'POST' THEN
    FOR r IN (SELECT i.item_code, SUM(j.qty * u.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                     item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY')) j
              JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
              JOIN items i ON i.item_id = j.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = j.item_id
                    AND b.warehouse_id = CASE l_type WHEN 'SALE' THEN l_wh ELSE l_to_wh END
              GROUP BY i.item_code) LOOP
      IF r.need > r.bal THEN err('الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي'); END IF;
    END LOOP;
  END IF;
```

**(د) احفظ `to_warehouse_id` في INSERT و UPDATE الخاصين بجدول `invoices`.**

**(هـ) داخل `IF l_action = 'POST'` بعد إنشاء القيدين:**

```sql
    -- حركة الأم: صادر في البيع ، وارد في المرتجع (بمتوسط تكلفة الأم)
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, currency_code,
                             exchange_rate, description, source_type, source_id, status, created_by)
    VALUES (l_parent, 'INV_OUT', l_no, l_date, l_wh, l_cur, 1, l_no, 'INVOICE', l_id, 'POSTED', :APP_USER)
    RETURNING trans_id INTO l_so;

    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT l_so, il.line_no, l_wh, il.item_id, il.unit_id, il.factor, il.qty,
           il.qty * il.factor * DECODE(l_type, 'SALE', -1, 1),
           0, NVL(b.avg_cost, 0),
           ROUND(il.qty * il.factor * DECODE(l_type, 'SALE', -1, 1) * NVL(b.avg_cost, 0), 4)
    FROM invoice_lines il
    LEFT JOIN v_stock_balance b ON b.item_id = il.item_id AND b.warehouse_id = l_wh
    WHERE il.invoice_id = l_id;

    -- حركة الفرعية: وارد في البيع ، صادر في المرتجع (بسعر الفاتورة بالعملة الأساسية)
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, currency_code,
                             exchange_rate, description, source_type, source_id, status, created_by)
    VALUES (l_cust, 'INV_IN', l_no, l_date, l_to_wh, l_cur, l_rate, l_no, 'INVOICE', l_id, 'POSTED', :APP_USER)
    RETURNING trans_id INTO l_si;

    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT l_si, il.line_no, l_to_wh, il.item_id, il.unit_id, il.factor, il.qty,
           il.qty * il.factor * DECODE(l_type, 'SALE', 1, -1),
           il.price, il.line_total / il.qty * l_rate / il.factor,
           ROUND(il.line_total * l_rate * (l_net / l_gross) * DECODE(l_type, 'SALE', 1, -1), 4)
    FROM invoice_lines il WHERE il.invoice_id = l_id;

    -- تكلفة البضاعة في دفاتر الأم: مدين COGS / دائن INVENTORY (والعكس في المرتجع)
    SELECT -SUM(value_base) INTO l_cogs FROM stock_trans_lines WHERE trans_id = l_so;
    l_cogs_acc := setting(l_parent, 'COGS');
    l_inv_acc  := setting(l_parent, 'INVENTORY');
    IF ROUND(ABS(l_cogs), 2) > 0 THEN
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base)
      VALUES (l_j1, 3, l_cogs_acc,
              GREATEST(ROUND(l_cogs, 2), 0) / l_rate, GREATEST(-ROUND(l_cogs, 2), 0) / l_rate,
              GREATEST(ROUND(l_cogs, 2), 0), GREATEST(-ROUND(l_cogs, 2), 0));
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base)
      VALUES (l_j1, 4, l_inv_acc,
              GREATEST(-ROUND(l_cogs, 2), 0) / l_rate, GREATEST(ROUND(l_cogs, 2), 0) / l_rate,
              GREATEST(-ROUND(l_cogs, 2), 0), GREATEST(ROUND(l_cogs, 2), 0));
      UPDATE journals SET total_debit = total_debit + ABS(ROUND(l_cogs, 2)) / l_rate,
                          total_credit = total_credit + ABS(ROUND(l_cogs, 2)) / l_rate
      WHERE journal_id = l_j1;
    END IF;

    UPDATE invoices SET stock_out_id = l_so, stock_in_id = l_si WHERE invoice_id = l_id;
```

> قيد الشركة الفرعية لا يحتاج تعديلاً. `PURCHASES` للفرعيات صار يشير إلى حساب المخزون (في `03_phase2_tables.sql`)، فتدخل البضاعة مخزونها بسعر الفاتورة.

### 3. عكس الفاتورة (صفحة 60)

داخل فرع `source_type = 'INVOICE'` في عملية العكس أضف:

```sql
      UPDATE stock_trans SET status = 'REVERSED'
      WHERE  source_type = 'INVOICE' AND source_id = i.invoice_id;
```

الحركة المعكوسة تخرج من حساب الأرصدة، لأن `v_stock_balance` يقرأ الحركات المرحّلة فقط.
