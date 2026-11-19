# صفحة 120 - الموازنة التقديرية (JSON) + 121 الموازنة مقابل الفعلي + صفحة 1 لوحة المدير العام

## صفحة 120 - إدخال الموازنة

لكل شركة موازنة سنوية واحدة. تتكون من حسابات تحليلية، ولكل حساب 12 شهراً.
**الإجمالي السنوي** عمود مساعد: يكفي أن تكتب المبلغ السنوي ثم Enter، فيتوزع على الأشهر بالتساوي، ويمكن تعديل أي شهر بعدها.

```
┌ موازنة 2027 - الشركة الفرعية 1 ─────────────── الحالة: مسودة ──────────────────────────────┐
│ الحساب                 │ السنوي   │ 1   │ 2   │ 3   │ ... │ 12  │ الإجمالي                  │
│ 4101002 مبيعات POS     │ 1,200,000│100k │100k │100k │ ... │100k │ 1,200,000                 │
│ 5201001 الرواتب        │   600,000│ 50k │ 50k │ 50k │ ... │ 50k │   600,000                 │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
 [نسخ من موازنة السنة السابقة]  [نسخ من الفعلي للسنة السابقة]  [حفظ]  [اعتماد]
```

### Items

| Item | النوع |
|---|---|
| `P120_COMPANY_ID` | Select List (LOV_COMPANIES)، Submit on change |
| `P120_FY_YEAR` | Select List: `SELECT fy_year d, fy_year r FROM fiscal_years ORDER BY 1 DESC`، Submit on change |
| `P120_BUDGET_ID` | Hidden. Computation: `SELECT budget_id FROM budgets WHERE company_id = :P120_COMPANY_ID AND fy_year = :P120_FY_YEAR` |
| `P120_NAME` | Text. Default `'موازنة ' \|\| :P120_FY_YEAR` |
| `P120_STATUS` | Display Only |

### Region

```html
<div id="bud_lines" style="overflow-x:auto"></div>
```

### Ajax Callback: `INIT_DATA`

```sql
DECLARE l_acc CLOB; l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code, 'name' VALUE name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO l_acc FROM accounts
  WHERE is_postable = 'Y' AND is_active = 'Y'
  AND (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  -- x02 = الموازنة الحالية ، x03 = 'PREV_BUDGET' أو 'PREV_ACTUAL' للنسخ
  IF apex_application.g_x03 = 'PREV_ACTUAL' THEN
    SELECT JSON_ARRAYAGG(JSON_OBJECT('ACCOUNT_ID' VALUE account_id,
             'M01' VALUE m01,'M02' VALUE m02,'M03' VALUE m03,'M04' VALUE m04,'M05' VALUE m05,'M06' VALUE m06,
             'M07' VALUE m07,'M08' VALUE m08,'M09' VALUE m09,'M10' VALUE m10,'M11' VALUE m11,'M12' VALUE m12)
           RETURNING CLOB)
    INTO l_lines FROM (
      SELECT l.account_id,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 1  THEN x.amt END), 2) m01,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 2  THEN x.amt END), 2) m02,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 3  THEN x.amt END), 2) m03,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 4  THEN x.amt END), 2) m04,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 5  THEN x.amt END), 2) m05,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 6  THEN x.amt END), 2) m06,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 7  THEN x.amt END), 2) m07,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 8  THEN x.amt END), 2) m08,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 9  THEN x.amt END), 2) m09,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 10 THEN x.amt END), 2) m10,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 11 THEN x.amt END), 2) m11,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 12 THEN x.amt END), 2) m12
      FROM journals j JOIN journal_lines l ON l.journal_id = j.journal_id
      JOIN accounts a ON a.account_id = l.account_id AND a.acc_type IN ('REV','EXP')
      CROSS APPLY (SELECT CASE a.acc_type WHEN 'REV' THEN l.credit_base - l.debit_base
                                          ELSE l.debit_base - l.credit_base END amt FROM dual) x
      WHERE j.status IN ('POSTED','REVERSED') AND j.company_id = TO_NUMBER(apex_application.g_x01)
      AND EXTRACT(YEAR FROM j.journal_date) = TO_NUMBER(apex_application.g_x04) - 1
      GROUP BY l.account_id);
  ELSE
    SELECT JSON_ARRAYAGG(JSON_OBJECT('ACCOUNT_ID' VALUE bl.account_id,
             'M01' VALUE m01,'M02' VALUE m02,'M03' VALUE m03,'M04' VALUE m04,'M05' VALUE m05,'M06' VALUE m06,
             'M07' VALUE m07,'M08' VALUE m08,'M09' VALUE m09,'M10' VALUE m10,'M11' VALUE m11,'M12' VALUE m12)
           RETURNING CLOB)
    INTO l_lines FROM budget_lines bl
    WHERE bl.budget_id = CASE WHEN apex_application.g_x03 = 'PREV_BUDGET'
                              THEN (SELECT budget_id FROM budgets
                                    WHERE company_id = TO_NUMBER(apex_application.g_x01)
                                    AND fy_year = TO_NUMBER(apex_application.g_x04) - 1)
                              ELSE TO_NUMBER(apex_application.g_x02) END;
  END IF;

  apex_util.prn('{"accounts":' || COALESCE(l_acc, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
```

### Ajax Callback: `SAVE_DOC` (x01 = `DRAFT` أو `APPROVE`)

```sql
DECLARE
  l_clob CLOB := apex_application.g_clob_01;
  l_errs apex_t_varchar2 := apex_t_varchar2();
  l_company NUMBER := JSON_VALUE(l_clob, '$.header.COMPANY_ID' RETURNING NUMBER);
  l_year    NUMBER := JSON_VALUE(l_clob, '$.header.FY_YEAR'    RETURNING NUMBER);
  l_name    VARCHAR2(150) := JSON_VALUE(l_clob, '$.header.NAME');
  l_id      NUMBER;
  l_status  VARCHAR2(10);
  l_cnt     NUMBER;
  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR (:G_USER_ROLE = 'ACCOUNTANT' AND l_company = :G_COMPANY_ID);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على موازنة هذه الشركة'); END IF;
  IF apex_application.g_x01 = 'APPROVE' AND :G_USER_ROLE <> 'GM' THEN err('الاعتماد للمدير العام فقط'); END IF;

  BEGIN
    SELECT budget_id, status INTO l_id, l_status FROM budgets
    WHERE company_id = l_company AND fy_year = l_year FOR UPDATE;
    IF l_status = 'APPROVED' THEN err('الموازنة معتمدة ولا يمكن تعديلها'); END IF;
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;

  SELECT COUNT(*) INTO l_cnt FROM (
    SELECT account_id FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (account_id NUMBER PATH '$.ACCOUNT_ID'))
    GROUP BY account_id HAVING COUNT(*) > 1);
  IF l_cnt > 0 THEN err('يوجد حساب مكرر في الموازنة'); END IF;

  SELECT COUNT(*) INTO l_cnt
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (account_id NUMBER PATH '$.ACCOUNT_ID')) j
  WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.account_id = j.account_id AND a.is_postable = 'Y');
  IF l_cnt > 0 THEN err('كل الحسابات يجب أن تكون تحليلية'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  IF l_id IS NULL THEN
    INSERT INTO budgets (company_id, fy_year, name_ar, created_by)
    VALUES (l_company, l_year, NVL(l_name, 'موازنة ' || l_year), :APP_USER)
    RETURNING budget_id INTO l_id;
  ELSE
    UPDATE budgets SET name_ar = NVL(l_name, name_ar) WHERE budget_id = l_id;
    DELETE FROM budget_lines WHERE budget_id = l_id;
  END IF;

  INSERT INTO budget_lines (budget_id, account_id, m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11, m12)
  SELECT l_id, account_id, NVL(m01,0), NVL(m02,0), NVL(m03,0), NVL(m04,0), NVL(m05,0), NVL(m06,0),
         NVL(m07,0), NVL(m08,0), NVL(m09,0), NVL(m10,0), NVL(m11,0), NVL(m12,0)
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
         account_id NUMBER PATH '$.ACCOUNT_ID',
         m01 NUMBER PATH '$.M01', m02 NUMBER PATH '$.M02', m03 NUMBER PATH '$.M03', m04 NUMBER PATH '$.M04',
         m05 NUMBER PATH '$.M05', m06 NUMBER PATH '$.M06', m07 NUMBER PATH '$.M07', m08 NUMBER PATH '$.M08',
         m09 NUMBER PATH '$.M09', m10 NUMBER PATH '$.M10', m11 NUMBER PATH '$.M11', m12 NUMBER PATH '$.M12'));

  IF apex_application.g_x01 = 'APPROVE' THEN
    UPDATE budgets SET status = 'APPROVED', approved_by = :APP_USER WHERE budget_id = l_id;
  END IF;

  apex_json.open_object; apex_json.write('ok', TRUE); apex_json.write('id', l_id);
  apex_json.write('message', CASE apex_application.g_x01 WHEN 'APPROVE' THEN 'تم اعتماد الموازنة' ELSE 'تم حفظ الموازنة' END);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
```

### JavaScript

```javascript
var bud = {
  grid: null,
  months: ['M01','M02','M03','M04','M05','M06','M07','M08','M09','M10','M11','M12'],

  init: function () {
    var cols = [
      {name: 'ACCOUNT_ID', label: 'الحساب', type: 'lov', lov: 'accounts', required: true, width: '20em'},
      {name: 'ANNUAL', label: 'السنوي (توزيع)', type: 'number', decimals: 0, noSubmit: true, ignoreEmpty: true, width: '9em'}
    ];
    bud.months.forEach(function (m, i) {
      cols.push({name: m, label: String(i + 1), type: 'number', decimals: 0, total: true, width: '6.5em'});
    });
    cols.push({name: 'TOTAL', label: 'الإجمالي', type: 'display', decimals: 0, total: true, noSubmit: true});

    bud.grid = new JsonLines({
      container: '#bud_lines',
      readOnly: apex.item('P120_STATUS').getValue() === 'APPROVED',
      columns: cols,
      onChange: function (row, col) {
        if (col === 'ANNUAL' && row.ANNUAL) {                // توزيع بالتساوي والباقي على ديسمبر
          var each = Math.floor(row.ANNUAL / 12);
          bud.months.forEach(function (m) { row[m] = each; });
          row.M12 = row.ANNUAL - each * 11;
        }
        row.TOTAL = bud.months.reduce(function (s, m) { return s + (row[m] || 0); }, 0);
      }
    });
    bud.load('');
    EnterNav.first('#bud_lines');
  },

  load: function (copyFrom) {
    apex.server.process('INIT_DATA', {
      x01: apex.item('P120_COMPANY_ID').getValue(), x02: apex.item('P120_BUDGET_ID').getValue(),
      x03: copyFrom, x04: apex.item('P120_FY_YEAR').getValue()
    }, {dataType: 'json'}).done(function (d) {
      bud.grid.setLov('accounts', d.accounts);
      d.lines.forEach(function (r) { bud.grid.opts.onChange(r, 'M01', bud.grid); });
      bud.grid.setData(d.lines);
    });
  },

  save: function (action) {
    var errs = bud.grid.validate();
    if (errs.length) { DocUtil.showErrors(errs); return; }
    DocUtil.save({
      header: {COMPANY_ID: apex.item('P120_COMPANY_ID').getValue(), FY_YEAR: apex.item('P120_FY_YEAR').getValue(),
               NAME: apex.item('P120_NAME').getValue()},
      lines: bud.grid.getData()
    }, action, function () { apex.page.submit('RELOAD'); });
  }
};
```

> **تنبيه:** في `onChange`، `row.TOTAL` يُحسب من الأشهر فقط. القيمة المحمّلة من الخادم تمر بنفس الدالة، فيظهر الإجمالي مباشرة.

**Execute when Page Loads:** `bud.init();`

**الأزرار:**
- حفظ: `bud.save('DRAFT')`
- اعتماد: `bud.save('APPROVE')`، Authorization `IS_GM`
- نسخ من موازنة السنة السابقة: `bud.load('PREV_BUDGET')`
- نسخ من الفعلي للسنة السابقة: `bud.load('PREV_ACTUAL')`

---

## صفحة 121 - الموازنة مقابل الفعلي

**Items:** `P121_COMPANY_ID` (فارغ = كل الشركات مجمّعة)، `P121_FY_YEAR`، `P121_TO_MONTH` (1 إلى 12، Default الشهر الحالي)، `P121_LEVEL` (2 أو 3 أو 4).

```sql
WITH bud AS (
  SELECT b.company_id, bl.account_id,
         NVL(bl.m01,0) * CASE WHEN 1  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m02,0) * CASE WHEN 2  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m03,0) * CASE WHEN 3  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m04,0) * CASE WHEN 4  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m05,0) * CASE WHEN 5  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m06,0) * CASE WHEN 6  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m07,0) * CASE WHEN 7  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m08,0) * CASE WHEN 8  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m09,0) * CASE WHEN 9  <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m10,0) * CASE WHEN 10 <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m11,0) * CASE WHEN 11 <= :P121_TO_MONTH THEN 1 ELSE 0 END
       + NVL(bl.m12,0) * CASE WHEN 12 <= :P121_TO_MONTH THEN 1 ELSE 0 END AS budget,
         bl.total AS annual
  FROM budgets b JOIN budget_lines bl ON bl.budget_id = b.budget_id
  WHERE b.fy_year = :P121_FY_YEAR AND b.status = 'APPROVED'
  AND (:P121_COMPANY_ID IS NULL OR b.company_id = :P121_COMPANY_ID)
),
act AS (
  SELECT j.company_id, l.account_id,
         SUM(CASE a.acc_type WHEN 'REV' THEN l.credit_base - l.debit_base
                             WHEN 'EXP' THEN l.debit_base - l.credit_base
                             ELSE l.debit_base - l.credit_base END) AS actual
  FROM journals j JOIN journal_lines l ON l.journal_id = j.journal_id
  JOIN accounts a ON a.account_id = l.account_id
  WHERE j.status IN ('POSTED','REVERSED')
  AND EXTRACT(YEAR FROM j.journal_date) = :P121_FY_YEAR
  AND EXTRACT(MONTH FROM j.journal_date) <= :P121_TO_MONTH
  AND (:P121_COMPANY_ID IS NULL OR j.company_id = :P121_COMPANY_ID)
  AND (:P121_COMPANY_ID IS NOT NULL OR l.partner_company_id IS NULL)    -- المجمّع: استبعاد البيني
  GROUP BY j.company_id, l.account_id
),
leaf AS (
  SELECT a.account_code, SUM(budget) budget, SUM(annual) annual, SUM(actual) actual
  FROM (SELECT account_id, budget, annual, 0 actual FROM bud
        UNION ALL
        SELECT account_id, 0, 0, actual FROM act) x
  JOIN accounts a ON a.account_id = x.account_id
  GROUP BY a.account_code
)
SELECT p.account_code "الحساب", p.name_ar "الاسم",
       DECODE(p.acc_type,'REV','إيراد','EXP','مصروف','أخرى') "النوع",
       SUM(leaf.annual) "الموازنة السنوية",
       SUM(leaf.budget) "الموازنة حتى الشهر",
       SUM(leaf.actual) "الفعلي",
       SUM(leaf.actual) - SUM(leaf.budget) "الانحراف",
       ROUND(100 * SUM(leaf.actual) / NULLIF(SUM(leaf.budget), 0), 1) "نسبة التنفيذ %",
       CASE WHEN p.acc_type = 'EXP' AND SUM(leaf.actual) > SUM(leaf.budget) THEN 'تجاوز'
            WHEN p.acc_type = 'REV' AND SUM(leaf.actual) < SUM(leaf.budget) THEN 'أقل من المستهدف' END "تنبيه"
FROM accounts p
JOIN leaf ON leaf.account_code LIKE p.account_code || '%'
WHERE p.acc_level = :P121_LEVEL AND p.acc_type IN ('REV','EXP')
GROUP BY p.account_code, p.name_ar, p.acc_type
ORDER BY p.account_code
```

Highlight أحمر على "تنبيه"، و Chart (Bar) على "الموازنة حتى الشهر" مقابل "الفعلي".

---

## صفحة 1 - لوحة المدير العام (Home)

**Authorization:** `IS_GM` (والمستخدم العادي يرى نسخة مقيدة بشركته بنفس الاستعلامات، لأنها تحترم `:G_COMPANY_ID`).

### Items (شريط الفلاتر أعلى الصفحة)

| Item | النوع |
|---|---|
| `P1_COMPANY_ID` | Select List (LOV_COMPANIES)، Null = "كل الشركات". Submit on change |
| `P1_YEAR` | Select List للسنوات. Default السنة الحالية |
| `P1_MODE` | Radio: `SEP` كل شركة منفصلة / `CONS` مجمّع (يستبعد المعاملات البينية) |

### View مساعد داخل الصفحة: كل الحركات مع التصنيف

اكتب هذا الـ `WITH` في كل Region (APEX لا يشارك الاستعلامات بين الـ Regions):

```sql
WITH mv AS (
  SELECT j.company_id, c.name_ar company, j.journal_date, a.acc_type, a.account_code, a.cash_bank,
         l.debit_base - l.credit_base AS bal, l.partner_company_id
  FROM journals j
  JOIN journal_lines l ON l.journal_id = j.journal_id
  JOIN accounts a ON a.account_id = l.account_id
  JOIN companies c ON c.company_id = j.company_id
  WHERE j.status IN ('POSTED','REVERSED')
  AND (:P1_COMPANY_ID IS NULL OR j.company_id = :P1_COMPANY_ID)
  AND (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID)
  AND (NVL(:P1_MODE,'SEP') = 'SEP' OR l.partner_company_id IS NULL)
)
```

### Region 1: المؤشرات (Cards أو Classic Report بقالب Badge List)

```sql
WITH mv AS ( ... كما أعلاه ... )
SELECT 'المبيعات' label,
       TO_CHAR(-SUM(CASE WHEN account_code LIKE '41%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990') value
FROM mv
UNION ALL
SELECT 'تكلفة المبيعات',
       TO_CHAR(SUM(CASE WHEN account_code LIKE '51%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'المصروفات',
       TO_CHAR(SUM(CASE WHEN account_code LIKE '52%' AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'صافي الربح',
       TO_CHAR(-SUM(CASE WHEN acc_type IN ('REV','EXP') AND EXTRACT(YEAR FROM journal_date) = :P1_YEAR THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'النقدية والبنوك', TO_CHAR(SUM(CASE WHEN cash_bank IN ('C','B') THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'ذمم الشركات الفرعية', TO_CHAR(SUM(CASE WHEN account_code LIKE '1103%' THEN bal END), 'FM999G999G999G990')
FROM mv
UNION ALL
SELECT 'قيمة المخزون', TO_CHAR((SELECT ROUND(SUM(qty_base * avg_cost)) FROM v_stock_balance
                                WHERE :P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID), 'FM999G999G999G990')
FROM dual
```

> أرقام الحسابات (`41%` و `51%` و `52%` و `1103%`) مأخوذة من شجرة الحسابات النموذجية في `02_seed.sql`. عدّلها إذا غيّرت ترقيم الشجرة.

### Region 2: الإيرادات والمصروفات شهرياً (Chart: Line أو Bar)

```sql
WITH mv AS ( ... )
SELECT TO_CHAR(journal_date, 'MM') "الشهر",
       -SUM(CASE WHEN acc_type = 'REV' THEN bal END) "الإيرادات",
        SUM(CASE WHEN acc_type = 'EXP' THEN bal END) "المصروفات"
FROM mv WHERE EXTRACT(YEAR FROM journal_date) = :P1_YEAR
GROUP BY TO_CHAR(journal_date, 'MM') ORDER BY 1
```

سلسلتان: الإيرادات والمصروفات، والمحور X هو الشهر.

### Region 3: مقارنة الشركات (Chart: Bar، تجميع حسب الشركة)

```sql
WITH mv AS ( ... )
SELECT company "الشركة",
       -SUM(CASE WHEN acc_type = 'REV' THEN bal END) "الإيرادات",
        SUM(CASE WHEN acc_type = 'EXP' THEN bal END) "المصروفات",
       -SUM(CASE WHEN acc_type IN ('REV','EXP') THEN bal END) "صافي الربح"
FROM mv WHERE EXTRACT(YEAR FROM journal_date) = :P1_YEAR
GROUP BY company ORDER BY 4 DESC
```

في وضع **المجمّع** يُضاف سطر إجمالي المجموعة: أضف Region Classic Report بنفس الاستعلام مع `GROUP BY ROLLUP(company)`، و `NVL(company, 'إجمالي المجموعة')`.

### Region 4: الميزانية العمومية المختصرة لكل شركة (Classic Report)

```sql
WITH mv AS ( ... )
SELECT NVL(company, 'إجمالي المجموعة') "الشركة",
       SUM(CASE WHEN acc_type = 'ASSET'  THEN bal END)  "الأصول",
      -SUM(CASE WHEN acc_type = 'LIAB'   THEN bal END)  "الخصوم",
      -SUM(CASE WHEN acc_type = 'EQUITY' THEN bal END)  "حقوق الملكية",
      -SUM(CASE WHEN acc_type IN ('REV','EXP') THEN bal END) "أرباح الفترة"
FROM mv
WHERE journal_date <= LAST_DAY(TO_DATE(:P1_YEAR || '12', 'YYYYMM'))
GROUP BY ROLLUP(company)
```

يجب أن تتحقق المعادلة: **الأصول = الخصوم + حقوق الملكية + أرباح الفترة** لكل شركة وللمجموع.
في الوضع المجمّع تُستبعد الذمم البينية (ذمة الفرعية لدى الأم، ومستحق الأم لدى الفرعية) لأنها تحمل `partner_company_id`، فيبقى المجموع متوازناً.

### Region 5: أعلى 10 أصناف مبيعاً (Chart: Pie أو Bar)

```sql
SELECT i.name_ar "الصنف", SUM(l.line_total) "المبيعات"
FROM pos_sale_lines l
JOIN pos_sales s ON s.sale_id = l.sale_id AND s.sale_type = 'SALE'
JOIN items i ON i.item_id = l.item_id
WHERE EXTRACT(YEAR FROM s.sale_date) = :P1_YEAR
AND (:P1_COMPANY_ID IS NULL OR s.company_id = :P1_COMPANY_ID)
AND (:G_USER_ROLE = 'GM' OR s.company_id = :G_COMPANY_ID)
GROUP BY i.name_ar ORDER BY 2 DESC FETCH FIRST 10 ROWS ONLY
```

### Region 6: تكلفة الرواتب لكل شركة (Chart: Bar)

```sql
SELECT c.name_ar "الشركة", SUM(p.net_salary) "صافي الرواتب"
FROM payroll_lines p
JOIN payroll_runs r ON r.run_id = p.run_id AND r.status = 'APPROVED'
JOIN companies c ON c.company_id = p.company_id
WHERE SUBSTR(r.pay_period, 1, 4) = TO_CHAR(:P1_YEAR)
AND (:P1_COMPANY_ID IS NULL OR p.company_id = :P1_COMPANY_ID)
GROUP BY c.name_ar ORDER BY 2 DESC
```

### Region 7: تنبيهات

- أصناف تحت حد الطلب (من `v_stock_balance` و `items.reorder_level`).
- مستندات مسودة لم تُرحَّل منذ أكثر من 3 أيام (قيود، سندات، فواتير).
- بنود تجاوزت الموازنة (من استعلام صفحة 121 مع شرط "تجاوز").
- ورديات مفتوحة منذ أكثر من 12 ساعة.

```sql
SELECT 'قيود مسودة' "التنبيه", COUNT(*) "العدد" FROM journals
WHERE status = 'DRAFT' AND created_on < SYSDATE - 3 AND (:P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'سندات مسودة', COUNT(*) FROM vouchers
WHERE status = 'DRAFT' AND created_on < SYSDATE - 3 AND (:P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'أصناف تحت حد الطلب', COUNT(*) FROM v_stock_balance b JOIN items i ON i.item_id = b.item_id
WHERE b.qty_base <= i.reorder_level AND (:P1_COMPANY_ID IS NULL OR b.company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'ورديات مفتوحة أكثر من 12 ساعة', COUNT(*) FROM pos_shifts s JOIN pos_terminals t ON t.terminal_id = s.terminal_id
WHERE s.status = 'OPEN' AND s.opened_on < SYSDATE - 0.5 AND (:P1_COMPANY_ID IS NULL OR t.company_id = :P1_COMPANY_ID)
```
