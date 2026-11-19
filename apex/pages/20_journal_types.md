# صفحة 20 / 21 - أنواع القيود

## صفحة 20: Interactive Report

```sql
SELECT jt_code         AS "الرمز",
       name_ar         AS "النوع",
       prefix          AS "البادئة",
       DECODE(manual_allowed,'Y','يدوي','آلي من الشاشات') AS "طريقة الإدخال",
       DECODE(is_active,'Y','فعّال','موقوف')             AS "الحالة",
       (SELECT COUNT(*) FROM journals j WHERE j.jt_code = t.jt_code) AS "عدد القيود",
       sort_order
FROM   journal_types t
ORDER  BY sort_order
```

Link Column: يفتح الصفحة 21 (Modal Dialog) مع `P21_JT_CODE`.

## صفحة 21: Form (Modal Dialog) على جدول `JOURNAL_TYPES`

| Item | النوع |
|---|---|
| `P21_JT_CODE` | Text Field، Required، أحرف إنجليزية كبيرة. يصبح Read Only عند التعديل |
| `P21_NAME_AR` | Text Field، Required |
| `P21_NAME_EN` | Text Field |
| `P21_PREFIX` | Text Field، Required |
| `P21_MANUAL_ALLOWED` | Switch: يظهر في شاشة القيد اليدوي |
| `P21_IS_ACTIVE` | Switch |
| `P21_SORT_ORDER` | Number |

**الأنواع المعرّفة مسبقاً:**

| الرمز | النوع | المصدر |
|---|---|---|
| JV | قيد يومية عام | يدوي |
| OB | قيد افتتاحي | يدوي |
| ADJ | قيد تسوية | يدوي |
| CL | قيد إقفال | يدوي |
| RV | سند قبض | آلي من شاشة السندات |
| PV | سند صرف | آلي من شاشة السندات |
| INV | فاتورة صرف لشركة | آلي من شاشة الفواتير |
| RET | مرتجع من شركة | آلي من شاشة الفواتير |
| PAY | قيد رواتب | آلي من مسير الرواتب |
| REV | قيد عكسي | آلي من شاشة العكس |

**Validation: لا يُحذف نوع عليه قيود**

```sql
DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM journals WHERE jt_code = :P21_JT_CODE;
  RETURN CASE WHEN l_cnt > 0 THEN 'لا يمكن حذف نوع قيد مستخدم. أوقفه بدلاً من ذلك' END;
END;
```

**Validation: الأنواع الآلية لا تتحول إلى يدوية**

```sql
RETURN CASE WHEN :P21_JT_CODE IN ('RV','PV','INV','RET','PAY','REV')
             AND :P21_MANUAL_ALLOWED = 'Y'
            THEN 'هذا النوع يُنشأ آلياً من شاشته ولا يُدخل يدوياً' END;
```
