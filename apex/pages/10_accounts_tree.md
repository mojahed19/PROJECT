# صفحة 10 - شجرة الحسابات (أربع مستويات)

| المستوى | الاسم | طول الرقم | مثال | يقبل قيود؟ |
|---|---|---|---|---|
| 1 | رئيسي | 1 | `1` الأصول | لا |
| 2 | عام | 2 | `11` الأصول المتداولة | لا |
| 3 | مساعد | 4 | `1101` النقدية بالصناديق | لا |
| 4 | تحليلي | 7 | `1101001` الصندوق الرئيسي | **نعم** |

**الشكل:** الشجرة على اليمين، ونموذج الحساب على اليسار في نفس الصفحة. الضغط على أي حساب في الشجرة يفتح بياناته.

```
┌──── شجرة الحسابات ─────────┐ ┌──── بيانات الحساب ───────────────────────────┐
│ ▾ 1 الأصول                  │ │ الحساب الأب   [1101 النقدية بالصناديق    ▾] │
│   ▾ 11 الأصول المتداولة     │ │ المستوى       4 - تحليلي                    │
│     ▾ 1101 النقدية          │ │ رقم الحساب    [1101003]  (مقترح تلقائياً)   │
│        • 1101001 الصندوق    │ │ الاسم عربي    [______________]              │
│        • 1101002 صندوق POS  │ │ الاسم إنجليزي [______________]              │
│   ▸ 12 الأصول الثابتة       │ │ صندوق/بنك     ( ) لا  ( ) صندوق  ( ) بنك    │
│ ▸ 2 الخصوم                  │ │ العملة        [__ ▾]   الشركة [الكل ▾]      │
│ ▸ 3 حقوق الملكية            │ │ فعّال         [✔]                           │
│ ▸ 4 الإيرادات               │ │ [جديد] [حساب فرعي] [حفظ] [حذف]              │
│ ▸ 5 المصروفات               │ └─────────────────────────────────────────────┘
└─────────────────────────────┘
```

## Region 1: شجرة الحسابات (نوع Tree)

**SQL Query:**

```sql
SELECT CASE WHEN CONNECT_BY_ISLEAF = 1 THEN 0
            WHEN LEVEL = 1 THEN 1 ELSE -1 END        AS status,
       LEVEL                                          AS lvl,
       a.account_code || ' - ' || a.name_ar          AS title,
       CASE a.acc_level WHEN 4 THEN 'fa fa-file-text-o' ELSE 'fa fa-folder' END AS icon,
       a.account_id                                   AS value,
       a.account_code || ' - ' || a.name_ar          AS tooltip,
       apex_page.get_url(p_page => 10, p_items => 'P10_ACCOUNT_ID',
                         p_values => a.account_id)    AS link
FROM   accounts a
START  WITH a.parent_id IS NULL
CONNECT BY PRIOR a.account_id = a.parent_id
ORDER  SIBLINGS BY a.account_code
```

Attributes: **Selected Node Page Item** = `P10_ACCOUNT_ID`.

## Region 2: بيانات الحساب (Form, Source Table = `ACCOUNTS`)

| Item | النوع | ملاحظات |
|---|---|---|
| `P10_ACCOUNT_ID` | Hidden, Primary Key | |
| `P10_PARENT_ID` | Popup LOV | `SELECT account_code\|\|' - '\|\|name_ar d, account_id r FROM accounts WHERE acc_level < 4 ORDER BY account_code`. فارغ = حساب رئيسي |
| `P10_ACC_LEVEL` | Display Only | يُحسب تلقائياً |
| `P10_ACCOUNT_CODE` | Text Field, Required | يُقترح تلقائياً عند اختيار الأب |
| `P10_NAME_AR` | Text Field, Required | |
| `P10_NAME_EN` | Text Field | |
| `P10_ACC_TYPE` | Select List | ASSET/LIAB/EQUITY/REV/EXP. يُورَّث من الأب، ويُعدَّل يدوياً فقط في المستوى 1 |
| `P10_NATURE` | Radio Group | D = مدين / C = دائن |
| `P10_CASH_BANK` | Radio Group | N لا / C صندوق / B بنك. يظهر فقط في المستوى 4 |
| `P10_CURRENCY_CODE` | Select List (LOV_CURRENCIES) | |
| `P10_COMPANY_ID` | Select List (LOV_COMPANIES) | فارغ = حساب مشترك لكل الشركات |
| `P10_IS_ACTIVE` | Switch | |

### Dynamic Action: عند تغيير `P10_PARENT_ID` (اقتراح الرقم والمستوى)

Action: **Execute Server-side Code**
- Items to Submit: `P10_PARENT_ID`
- Items to Return: `P10_ACC_LEVEL,P10_ACCOUNT_CODE,P10_ACC_TYPE,P10_NATURE`

```sql
DECLARE
  l_parent accounts%ROWTYPE;
  l_len    PLS_INTEGER;
  l_max    VARCHAR2(20);
BEGIN
  IF :P10_PARENT_ID IS NULL THEN
    :P10_ACC_LEVEL := 1;
    SELECT TO_CHAR(NVL(MAX(TO_NUMBER(account_code)), 0) + 1)
    INTO   :P10_ACCOUNT_CODE
    FROM   accounts WHERE acc_level = 1;
    RETURN;
  END IF;

  SELECT * INTO l_parent FROM accounts WHERE account_id = :P10_PARENT_ID;
  :P10_ACC_LEVEL := l_parent.acc_level + 1;
  :P10_ACC_TYPE  := l_parent.acc_type;
  :P10_NATURE    := l_parent.nature;

  -- طول الجزء الخاص بالمستوى: م2 = 1 خانة ، م3 = 2 خانة ، م4 = 3 خانات
  l_len := CASE :P10_ACC_LEVEL WHEN 2 THEN 1 WHEN 3 THEN 2 ELSE 3 END;

  SELECT MAX(account_code) INTO l_max
  FROM   accounts WHERE parent_id = l_parent.account_id;

  :P10_ACCOUNT_CODE := l_parent.account_code ||
       LPAD(NVL(TO_NUMBER(SUBSTR(l_max, -l_len)), 0) + 1, l_len, '0');
END;
```

### Validations (كلها من نوع PL/SQL Function Body returning Error Text)

**1. المستوى لا يتجاوز 4، والأب ليس حساباً تحليلياً**

```sql
DECLARE l_lvl NUMBER;
BEGIN
  IF :P10_PARENT_ID IS NULL THEN RETURN NULL; END IF;
  SELECT acc_level INTO l_lvl FROM accounts WHERE account_id = :P10_PARENT_ID;
  IF l_lvl >= 4 THEN
    RETURN 'لا يمكن إضافة حساب تحت حساب تحليلي (مستوى 4)';
  END IF;
  IF :P10_ACCOUNT_ID = :P10_PARENT_ID THEN
    RETURN 'الحساب لا يكون أباً لنفسه';
  END IF;
  RETURN NULL;
END;
```

**2. الرقم يبدأ برقم الأب وطوله صحيح**

```sql
DECLARE l_pcode VARCHAR2(20); l_lvl NUMBER;
BEGIN
  IF :P10_PARENT_ID IS NULL THEN
    l_lvl := 1;
  ELSE
    SELECT account_code, acc_level + 1 INTO l_pcode, l_lvl
    FROM accounts WHERE account_id = :P10_PARENT_ID;
  END IF;

  IF LENGTH(:P10_ACCOUNT_CODE) <> CASE l_lvl WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 4 ELSE 7 END THEN
    RETURN 'طول رقم الحساب في المستوى ' || l_lvl || ' يجب أن يكون '
           || CASE l_lvl WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 4 ELSE 7 END || ' خانات';
  END IF;
  IF l_pcode IS NOT NULL AND :P10_ACCOUNT_CODE NOT LIKE l_pcode || '%' THEN
    RETURN 'رقم الحساب يجب أن يبدأ برقم الحساب الأب ' || l_pcode;
  END IF;
  IF NOT REGEXP_LIKE(:P10_ACCOUNT_CODE, '^[0-9]+$') THEN
    RETURN 'رقم الحساب أرقام فقط';
  END IF;
  RETURN NULL;
END;
```

**3. لا يُضاف حساب فرعي تحت حساب عليه حركات** (مهم عند تحويل حساب إلى أب)

```sql
DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM journal_lines WHERE account_id = :P10_PARENT_ID;
  RETURN CASE WHEN l_cnt > 0 THEN 'الحساب الأب عليه قيود، ولا يمكن أن يكون له حسابات فرعية' END;
END;
```

**4. عند الحذف: لا توجد حسابات فرعية ولا حركات** (Condition: Request = DELETE)

```sql
DECLARE l_ch NUMBER; l_mv NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_ch FROM accounts      WHERE parent_id  = :P10_ACCOUNT_ID;
  SELECT COUNT(*) INTO l_mv FROM journal_lines WHERE account_id = :P10_ACCOUNT_ID;
  IF l_ch > 0 THEN RETURN 'لا يمكن حذف حساب له حسابات فرعية'; END IF;
  IF l_mv > 0 THEN RETURN 'لا يمكن حذف حساب عليه قيود. يمكنك إيقافه بدلاً من الحذف'; END IF;
  RETURN NULL;
END;
```

**5. عند تعديل حساب موجود: لا يُغيَّر أبوه إذا كان له أبناء**

```sql
DECLARE l_old NUMBER; l_ch NUMBER;
BEGIN
  IF :P10_ACCOUNT_ID IS NULL THEN RETURN NULL; END IF;
  SELECT parent_id INTO l_old FROM accounts WHERE account_id = :P10_ACCOUNT_ID;
  SELECT COUNT(*) INTO l_ch FROM accounts WHERE parent_id = :P10_ACCOUNT_ID;
  IF l_ch > 0 AND DECODE(l_old, :P10_PARENT_ID, 0, 1) = 1 THEN
    RETURN 'لا يمكن نقل حساب له حسابات فرعية';
  END IF;
  RETURN NULL;
END;
```

### Processes

1. **Computation** (Before Processing): ضبط `P10_ACC_LEVEL`

```sql
CASE WHEN :P10_PARENT_ID IS NULL THEN 1
     ELSE (SELECT acc_level + 1 FROM accounts WHERE account_id = :P10_PARENT_ID) END
```

2. **Form - Automatic Row Processing (DML)** على جدول `ACCOUNTS`.
3. **Branch** إلى صفحة 10 مع `P10_ACCOUNT_ID` = `&P10_ACCOUNT_ID.` لإبقاء الحساب محدداً.

### الأزرار

| الزر | الإجراء |
|---|---|
| جديد | Redirect إلى صفحة 10 مع Clear Cache |
| حساب فرعي | Redirect إلى صفحة 10 مع Clear Cache، و `P10_PARENT_ID` = `&P10_ACCOUNT_ID.`. يظهر فقط إذا `P10_ACC_LEVEL < 4` |
| حفظ | Submit (CREATE أو SAVE) |
| حذف | Submit (DELETE) مع رسالة تأكيد |

**Server-side condition على `P10_CASH_BANK`:** `:P10_ACC_LEVEL = 4`

## تقرير الحسابات بالأرصدة (Region إضافي اختياري، Interactive Report)

Item للفلترة: `P10_FILTER_COMPANY` من نوع Select List (LOV_COMPANIES). القيمة الفارغة تعني "كل الشركات مجمّعة". Page Items to Submit = `P10_FILTER_COMPANY`.

```sql
SELECT LPAD(' ', (a.acc_level - 1) * 4, ' ') || a.account_code AS "رقم الحساب",
       a.name_ar                                               AS "اسم الحساب",
       a.acc_level                                             AS "المستوى",
       NVL(SUM(b.dr), 0)                                       AS "مدين",
       NVL(SUM(b.cr), 0)                                       AS "دائن",
       NVL(SUM(b.dr) - SUM(b.cr), 0)                           AS "الرصيد"
FROM   accounts a
LEFT JOIN (SELECT d.account_code, SUM(l.debit_base) dr, SUM(l.credit_base) cr
           FROM   journal_lines l
           JOIN   journals j ON j.journal_id = l.journal_id
                            AND j.status IN ('POSTED','REVERSED')
                            AND (:P10_FILTER_COMPANY IS NULL OR j.company_id = :P10_FILTER_COMPANY)
           JOIN   accounts d ON d.account_id = l.account_id
           GROUP  BY d.account_code) b
       ON b.account_code LIKE a.account_code || '%'
GROUP  BY a.account_code, a.name_ar, a.acc_level
ORDER  BY a.account_code
```
