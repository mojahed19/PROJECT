# 00 - إعدادات التطبيق المشتركة

كل ما في هذا الملف يُعمل مرة واحدة على مستوى التطبيق (Shared Components). منطق كل شاشة موجود في ملف الشاشة نفسها.

## 1. خصائص التطبيق

| الخاصية | القيمة |
|---|---|
| Globalization > Application Primary Language | Arabic (ar) |
| Globalization > Text direction | **Right to Left** |
| Application Date Format | `DD/MM/YYYY` |
| Theme | Universal Theme (Vita أو Redwood Light) |

**مهم:** كل حقول التاريخ في الشاشات تأخذ Format Mask = `DD/MM/YYYY`، لأن كود الحفظ يقرأ التاريخ بهذه الصيغة.

## 2. الملفات الثابتة

ارفع الملفات الثلاثة من مجلد `apex/static` إلى **Shared Components > Static Application Files**:

- `enter_nav.js`
- `json_lines.js`
- `app.css`

ثم أضفها في **Shared Components > User Interface Attributes > JavaScript / CSS**:

```
JavaScript File URLs:
#APP_FILES#enter_nav#MIN#.js
#APP_FILES#json_lines#MIN#.js

CSS File URLs:
#APP_FILES#app#MIN#.css
```

> بهذا يعمل **مفتاح ENTER للانتقال بين الحقول في كل صفحات التطبيق**.
> في كل حقل نصي (Text Field) اجعل **Submit when Enter pressed = No** حتى لا يُرسَل النموذج بالضغط على Enter.

## 3. Application Items

| الاسم | Session State Protection | الوصف |
|---|---|---|
| `G_COMPANY_ID` | Restricted - May not be set from browser | شركة المستخدم |
| `G_PARENT_ID` | Restricted | رقم الشركة الأم |
| `G_USER_ROLE` | Restricted | GM / ACCOUNTANT / HR / ... |

## 4. Application Process: تهيئة المستخدم بعد الدخول

- **Name:** `INIT_USER`
- **Point:** After Authentication

```sql
BEGIN
  SELECT u.company_id, u.user_role
  INTO   :G_COMPANY_ID, :G_USER_ROLE
  FROM   app_users u
  WHERE  u.user_name = UPPER(:APP_USER)
  AND    u.is_active = 'Y';

  SELECT company_id INTO :G_PARENT_ID FROM companies WHERE is_parent = 'Y';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    raise_application_error(-20000, 'المستخدم غير معرّف في جدول المستخدمين أو غير فعّال');
END;
```

## 5. Application Processes (Ajax Callback) مشتركة

تُنشأ من **Shared Components > Application Processes**، ونوع النقطة **Ajax Callback**. تستدعيها الصفحات بـ `apex.server.process`.

### GET_RATE: سعر الصرف حسب العملة والتاريخ

```sql
DECLARE
  l_rate NUMBER;
  l_date DATE := NVL(TO_DATE(apex_application.g_x02, 'DD/MM/YYYY'), TRUNC(SYSDATE));
BEGIN
  SELECT CASE WHEN c.is_base = 'Y' THEN 1
              ELSE (SELECT r.rate FROM exchange_rates r
                    WHERE  r.currency_code = c.currency_code
                    AND    r.rate_date <= l_date
                    ORDER  BY r.rate_date DESC FETCH FIRST 1 ROW ONLY) END
  INTO   l_rate
  FROM   currencies c
  WHERE  c.currency_code = apex_application.g_x01;

  apex_json.open_object;
  apex_json.write('rate', l_rate);
  apex_json.close_object;
EXCEPTION WHEN NO_DATA_FOUND THEN
  apex_json.open_object; apex_json.write('rate', ''); apex_json.close_object;
END;
```

### GET_ACCOUNTS: الحسابات التحليلية (المستوى 4) لشركة

```sql
DECLARE
  l_json CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(
           JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code,
                       'name' VALUE name_ar, 'cash' VALUE cash_bank)
           ORDER BY account_code RETURNING CLOB)
  INTO   l_json
  FROM   accounts
  WHERE  is_postable = 'Y'
  AND    is_active   = 'Y'
  AND    (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  apex_util.prn(COALESCE(l_json, TO_CLOB('[]')), FALSE);
END;
```

## 6. Authorization Schemes

| الاسم | النوع | الشرط |
|---|---|---|
| `IS_GM` | Exists SQL Query | `SELECT 1 FROM app_users WHERE user_name = UPPER(:APP_USER) AND user_role = 'GM'` |
| `IS_ACCOUNTANT` | Exists SQL Query | `... AND user_role IN ('GM','ACCOUNTANT')` |
| `IS_HR` | Exists SQL Query | `... AND user_role IN ('GM','HR')` |

## 7. شرط صلاحية الشركة (يتكرر في كل شاشة)

يُستخدم داخل كود الحفظ في الصفحات: المستخدم يرى شركته، أو الشركات المسموحة له، أو كل الشركات إذا كان مديراً عاماً.

```sql
SELECT COUNT(*) INTO l_cnt FROM dual
WHERE  :G_USER_ROLE = 'GM'
   OR  l_company = :G_COMPANY_ID
   OR  EXISTS (SELECT 1 FROM user_companies
               WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
```

## 8. Shared LOVs

| الاسم | الاستعلام |
|---|---|
| `LOV_COMPANIES` (حسب الصلاحية) | `SELECT name_ar d, company_id r FROM companies c WHERE is_active='Y' AND (:G_USER_ROLE='GM' OR company_id=:G_COMPANY_ID OR EXISTS (SELECT 1 FROM user_companies u WHERE u.user_name=UPPER(:APP_USER) AND u.company_id=c.company_id)) ORDER BY is_parent DESC, company_code` |
| `LOV_SUB_COMPANIES` | `SELECT name_ar d, company_id r FROM companies WHERE is_parent='N' AND is_active='Y' ORDER BY company_code` |
| `LOV_CURRENCIES` | `SELECT currency_code \|\| ' - ' \|\| name_ar d, currency_code r FROM currencies WHERE is_active='Y' ORDER BY is_base DESC, currency_code` |
| `LOV_JT_MANUAL` | `SELECT name_ar d, jt_code r FROM journal_types WHERE manual_allowed='Y' AND is_active='Y' ORDER BY sort_order` |
| `LOV_CASH_ACCOUNTS` | `SELECT account_code \|\| ' - ' \|\| name_ar d, account_id r FROM accounts WHERE cash_bank IN ('C','B') AND is_active='Y' AND (company_id IS NULL OR company_id = :G_COMPANY_ID) ORDER BY account_code` |
| `LOV_PAY_PERIODS` | `SELECT TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYY-MM') d, TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYYMM') r FROM dual CONNECT BY LEVEL <= 13` |

## 9. قائمة التنقل (Navigation Menu)

```
الحسابات العامة
   ├─ شجرة الحسابات ................ صفحة 10
   ├─ أنواع القيود ................. صفحة 20
   ├─ قيد يومية .................... صفحة 30
   ├─ قائمة القيود ................. صفحة 31
   ├─ عكس القيود ................... صفحة 60
   ├─ ميزان المراجعة ............... صفحة 80
   └─ كشف حساب ..................... صفحة 81
الصندوق والبنوك
   ├─ سند قبض ...................... صفحة 40  (P40_VOUCHER_TYPE = R)
   ├─ سند صرف ...................... صفحة 40  (P40_VOUCHER_TYPE = P)
   └─ قائمة السندات ................ صفحة 41
المبيعات للشركات
   ├─ فاتورة صرف لشركة ............. صفحة 50  (P50_INVOICE_TYPE = SALE)
   ├─ مرتجع من شركة ................ صفحة 50  (P50_INVOICE_TYPE = RETURN)
   └─ قائمة الفواتير ............... صفحة 51
الرواتب
   ├─ خصم .......................... صفحة 70  (P70_ADJ_TYPE = DED)
   ├─ فرق مبلغ ..................... صفحة 70  (P70_ADJ_TYPE = DIFF)
   ├─ حافز ......................... صفحة 70  (P70_ADJ_TYPE = INC)
   ├─ قائمة الخصومات والحوافز ...... صفحة 71
   ├─ مسير الرواتب ................. صفحة 100
   └─ توزيع الرواتب على الشركات .... صفحة 102
المخزون
   ├─ استلام بضاعة ................. صفحة 90  (P90_TRANS_TYPE = RECEIPT)
   ├─ صرف داخلي .................... صفحة 90  (P90_TRANS_TYPE = ISSUE)
   ├─ تحويل بين المخازن ............ صفحة 90  (P90_TRANS_TYPE = TRANSFER)
   ├─ تسوية جرد .................... صفحة 90  (P90_TRANS_TYPE = COUNT)
   ├─ قائمة الحركات ................ صفحة 91
   ├─ أرصدة المخزون ................ صفحة 92
   └─ كارت صنف ..................... صفحة 93
نقاط البيع
   ├─ شاشة الكاشير ................. صفحة 110
   ├─ إغلاق الوردية ................ صفحة 111
   └─ تقارير المبيعات .............. صفحة 113
الموازنة والإدارة
   ├─ لوحة المدير العام ............ صفحة 1
   ├─ الموازنة التقديرية ........... صفحة 120
   └─ الموازنة مقابل الفعلي ........ صفحة 121
```

## 10. نمط شاشات JSON (مشترك بين القيود والسندات والفواتير والخصومات)

```
┌──────────────────────────── رأس المستند (Static Content) ──────────────────────────────┐
│ الشركة [__]  النوع [__]  الرقم: JV-2026-00012   التاريخ [__]  العملة [__]  السعر [__] │
│ البيان [______________________________]                         الحالة: [مسودة]        │
└────────────────────────────────────────────────────────────────────────────────────────┘
┌──────────────────────────── السطور (div#..._lines) ─────────────────────────────────────┐
│ #  │ الحساب               │ مدين      │ دائن      │ البيان           │ شركة مقابلة │ 🗑 │
│ 1  │ 1101001 الصندوق      │ 1,000.00  │           │ ...              │             │    │
│ 2  │ 4101001 مبيعات       │           │ 1,000.00  │ ...              │             │    │
│    │                      │ 1,000.00  │ 1,000.00  │ الفرق: 0.00 ✔                  │    │
└────────────────────────────────────────────────────────────────────────────────────────┘
 [حفظ مسودة  Ctrl+S]   [حفظ وترحيل]   [جديد]   [طباعة]   [عكس القيد]
```

- **التحميل:** Ajax Callback اسمه `INIT_DATA` يرجع القوائم (الحسابات، الأصناف، الموظفين...) وسطور المستند بصيغة JSON.
- **الحفظ:** JavaScript يجمع الرأس والسطور في كائن واحد `{header:{...}, lines:[...]}` ويرسله في `p_clob_01` إلى Ajax Callback اسمه `SAVE_DOC`. هذا الإجراء يقرأه بـ `JSON_TABLE` ثم يتحقق ويحفظ ويرحّل في عملية واحدة.
- **لا يوجد Interactive Grid ولا Package.** كل الكود داخل الصفحة.
