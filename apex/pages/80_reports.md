# صفحة 80 - ميزان المراجعة / صفحة 81 - كشف حساب

كل الاستعلامات مكتوبة داخل الـ Region في الصفحة نفسها، ولا يوجد Package.

## صفحة 80 - ميزان المراجعة (حسب المستوى 1 إلى 4)

**Items:**

| Item | النوع | ملاحظات |
|---|---|---|
| `P80_COMPANY_ID` | Select List (LOV_COMPANIES) | Null Display = "كل الشركات (مجمّع)" |
| `P80_FROM` | Date Picker | Default أول السنة |
| `P80_TO` | Date Picker | Default اليوم |
| `P80_LEVEL` | Radio | 1 / 2 / 3 / 4، Default 4 |
| `P80_EXCLUDE_INTERCO` | Switch | استبعاد المعاملات البينية بين شركات المجموعة (للميزانية المجمّعة) |
| `P80_SEPARATE` | Switch | عرض كل شركة منفصلة (Control Break) |

**Interactive Report:**

```sql
WITH mv AS (   -- الحركات المرحّلة بالعملة الأساسية
  SELECT j.company_id, l.account_id,
         CASE WHEN j.journal_date <  TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.debit_base - l.credit_base ELSE 0 END AS open_bal,
         CASE WHEN j.journal_date >= TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.debit_base  ELSE 0 END AS dr,
         CASE WHEN j.journal_date >= TO_DATE(:P80_FROM,'DD/MM/YYYY') THEN l.credit_base ELSE 0 END AS cr
  FROM   journals j
  JOIN   journal_lines l ON l.journal_id = j.journal_id
  WHERE  j.status IN ('POSTED','REVERSED')
  AND    j.journal_date <= TO_DATE(:P80_TO,'DD/MM/YYYY')
  AND    (:P80_COMPANY_ID IS NULL OR j.company_id = :P80_COMPANY_ID)
  AND    (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
          OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
  AND    (NVL(:P80_EXCLUDE_INTERCO,'N') = 'N' OR l.partner_company_id IS NULL)
),
leaf AS (
  SELECT CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END AS company_id,
         a.account_code, SUM(open_bal) open_bal, SUM(dr) dr, SUM(cr) cr
  FROM   mv JOIN accounts a ON a.account_id = mv.account_id
  GROUP  BY CASE WHEN :P80_SEPARATE = 'Y' THEN mv.company_id END, a.account_code
)
SELECT c.name_ar                                       AS "الشركة",
       p.account_code                                  AS "رقم الحساب",
       p.name_ar                                       AS "اسم الحساب",
       SUM(CASE WHEN leaf.open_bal > 0 THEN leaf.open_bal ELSE 0 END) AS "رصيد أول مدين",
       SUM(CASE WHEN leaf.open_bal < 0 THEN -leaf.open_bal ELSE 0 END) AS "رصيد أول دائن",
       SUM(leaf.dr)                                    AS "حركة مدين",
       SUM(leaf.cr)                                    AS "حركة دائن",
       GREATEST(SUM(leaf.open_bal + leaf.dr - leaf.cr), 0)  AS "رصيد آخر مدين",
       GREATEST(-SUM(leaf.open_bal + leaf.dr - leaf.cr), 0) AS "رصيد آخر دائن"
FROM   accounts p
JOIN   leaf ON leaf.account_code LIKE p.account_code || '%'
LEFT JOIN companies c ON c.company_id = leaf.company_id
WHERE  p.acc_level = :P80_LEVEL
GROUP  BY c.name_ar, p.account_code, p.name_ar
HAVING SUM(ABS(leaf.open_bal)) + SUM(leaf.dr) + SUM(leaf.cr) <> 0
ORDER  BY c.name_ar, p.account_code
```

**Page Items to Submit:** كل حقول P80. أضف **Sum** على أعمدة المبالغ، و **Control Break** على "الشركة" عندما تكون "منفصلة" مفعّلة.

**أنماط العرض للمدير العام:**
- شركة واحدة: اختر الشركة.
- كل الشركات منفصلة: اترك الشركة فارغة وفعّل "منفصلة".
- ميزانية المجموعة المجمّعة: اترك الشركة فارغة وفعّل "استبعاد المعاملات البينية".

> **ملاحظة:** القيود المعكوسة تدخل في الميزان مع قيودها العكسية، فيصبح صافيها صفراً. بهذا يبقى أثر العكس ظاهراً في الحركة.

## صفحة 81 - كشف حساب

**Items:** `P81_ACCOUNT_ID` (Popup LOV للحسابات من المستوى 1 إلى 4، فيكون الكشف لحساب تحليلي أو تجميعي)، `P81_COMPANY_ID`، `P81_FROM`، `P81_TO`، `P81_CURRENCY` (فارغ = بالعملة الأساسية، أو عملة محددة لعرض المبالغ بعملة الحركة).

**Interactive Report:**

```sql
WITH acc AS (
  SELECT d.account_id FROM accounts d, accounts p
  WHERE  p.account_id = :P81_ACCOUNT_ID
  AND    d.account_code LIKE p.account_code || '%' AND d.acc_level = 4
),
rows_ AS (
  SELECT j.journal_date, j.journal_no, t.name_ar jt_name, j.journal_id, c.name_ar company,
         l.description, j.currency_code, j.exchange_rate,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.debit_base  ELSE l.debit  END dr,
         CASE WHEN :P81_CURRENCY IS NULL THEN l.credit_base ELSE l.credit END cr
  FROM   journals j
  JOIN   journal_lines l ON l.journal_id = j.journal_id
  JOIN   journal_types t ON t.jt_code    = j.jt_code
  JOIN   companies c     ON c.company_id = j.company_id
  WHERE  l.account_id IN (SELECT account_id FROM acc)
  AND    j.status IN ('POSTED','REVERSED')
  AND    (:P81_CURRENCY   IS NULL OR j.currency_code = :P81_CURRENCY)
  AND    (:P81_COMPANY_ID IS NULL OR j.company_id = :P81_COMPANY_ID)
  AND    (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID)
)
SELECT NULL AS "التاريخ", NULL AS "رقم القيد", 'رصيد سابق' AS "النوع", NULL AS "الشركة",
       NULL AS "البيان", NULL AS "العملة",
       GREATEST(SUM(dr - cr), 0) AS "مدين", GREATEST(SUM(cr - dr), 0) AS "دائن",
       SUM(dr - cr) AS "الرصيد", 0 AS sort_key
FROM   rows_ WHERE journal_date < TO_DATE(:P81_FROM,'DD/MM/YYYY')
UNION ALL
SELECT journal_date, journal_no, jt_name, company, description, currency_code,
       dr, cr,
       (SELECT NVL(SUM(dr - cr), 0) FROM rows_ WHERE journal_date < TO_DATE(:P81_FROM,'DD/MM/YYYY'))
       + SUM(dr - cr) OVER (ORDER BY journal_date, journal_id ROWS UNBOUNDED PRECEDING),
       1
FROM   rows_
WHERE  journal_date BETWEEN TO_DATE(:P81_FROM,'DD/MM/YYYY') AND TO_DATE(:P81_TO,'DD/MM/YYYY')
ORDER  BY sort_key, 1, 2
```

أخفِ العمود `SORT_KEY`، وأضف رابطاً على "رقم القيد" يفتح صفحة 30 للعرض.
