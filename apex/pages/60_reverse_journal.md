# صفحة 60 - عكس القيود

تنشئ هذه الشاشة **قيداً عكسياً** (نوع `REV`) تتبادل فيه أعمدة المدين والدائن، ويُعلَّم القيد الأصلي بأنه "معكوس".
لا يُحذف أي قيد مرحّل ولا يُعدَّل، فيبقى سجل التدقيق كاملاً.

**قواعد العكس:**
- القيد يجب أن يكون **مرحّلاً**، وغير معكوس من قبل، وليس هو نفسه قيداً عكسياً.
- إذا كان القيد من **سند**، يُعلَّم السند "معكوس".
- إذا كان من **فاتورة شركة**، يُعكس قيد الأم وقيد الشركة الفرعية معاً، وتُعلَّم الفاتورة "معكوسة".
- تاريخ العكس ≥ تاريخ القيد الأصلي، ويقع في سنة مالية مفتوحة.
- السبب إلزامي.

## الشكل

```
┌ البحث عن قيد ─────────────────────────────────────────────────────────────┐
│ الشركة [__▾]  من [__] إلى [__]  النوع [__▾]  رقم القيد [______] [بحث]    │
├───────────────────────────────────────────────────────────────────────────┤
│ ○ JV-2026-00012 │ 15/11/2026 │ قيد يومية │ 500.00 USD │ تسوية صندوق    │
│ ● RV-2026-00031 │ 17/11/2026 │ سند قبض   │ 1,200.00   │ سداد فاتورة    │
└───────────────────────────────────────────────────────────────────────────┘
┌ القيد المختار: RV-2026-00031 ─────────────────────────────────────────────┐
│ الحساب                    │ مدين       │ دائن     ← سيصبح →  مدين │ دائن │
│ 1101001 الصندوق           │ 1,200.00   │                      │ 1,200│
│ 1103001 ذمة الفرعية 1     │            │ 1,200.00   1,200    │      │
├───────────────────────────────────────────────────────────────────────────┤
│ تاريخ العكس [19/11/2026]   سبب العكس [_____________________________]     │
│                                                      [ عكس القيد ]        │
└───────────────────────────────────────────────────────────────────────────┘
```

## Region 1: القيود القابلة للعكس (Interactive Report)

```sql
SELECT j.journal_id,
       j.journal_no           AS "رقم القيد",
       j.journal_date         AS "التاريخ",
       c.name_ar              AS "الشركة",
       t.name_ar              AS "النوع",
       j.total_debit          AS "المبلغ",
       j.currency_code        AS "العملة",
       j.description          AS "البيان",
       DECODE(j.source_type,'MANUAL','يدوي','VOUCHER','سند','INVOICE','فاتورة','PAYROLL','رواتب') AS "المصدر",
       'اختيار'               AS "اختيار"
FROM   journals j
JOIN   companies c     ON c.company_id = j.company_id
JOIN   journal_types t ON t.jt_code    = j.jt_code
WHERE  j.status = 'POSTED'
AND    j.reversal_of_id IS NULL
AND    j.jt_code <> 'REV'
AND    (:G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
        OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
-- قيد الشركة الفرعية الناتج عن فاتورة يُعكس من قيد الأم فقط
AND    NOT EXISTS (SELECT 1 FROM invoices i WHERE i.sub_journal_id = j.journal_id)
```

- **Link Column "اختيار":** صفحة 60 مع `P60_JOURNAL_ID = #JOURNAL_ID#`
- **Authorization:** `IS_ACCOUNTANT`

## Region 2: سطور القيد المختار (Classic Report)

- **Condition:** `P60_JOURNAL_ID` Is Not Null

```sql
SELECT l.line_no                      AS "#",
       a.account_code                 AS "رقم الحساب",
       a.name_ar                      AS "الحساب",
       NULLIF(l.debit, 0)             AS "مدين (الأصل)",
       NULLIF(l.credit, 0)            AS "دائن (الأصل)",
       NULLIF(l.credit, 0)            AS "مدين (بعد العكس)",
       NULLIF(l.debit, 0)             AS "دائن (بعد العكس)",
       l.description                  AS "البيان"
FROM   journal_lines l
JOIN   accounts a ON a.account_id = l.account_id
WHERE  l.journal_id = :P60_JOURNAL_ID
UNION ALL
-- سطور قيد الشركة الفرعية إن كان القيد من فاتورة
SELECT l.line_no, a.account_code, a.name_ar || ' (قيد الشركة الفرعية)',
       NULLIF(l.debit, 0), NULLIF(l.credit, 0), NULLIF(l.credit, 0), NULLIF(l.debit, 0), l.description
FROM   invoices i
JOIN   journal_lines l ON l.journal_id = i.sub_journal_id
JOIN   accounts a      ON a.account_id = l.account_id
WHERE  i.journal_id = :P60_JOURNAL_ID
```

## Region 3: بيانات العكس (Static Content, Static ID = `R_HEADER`)

| Item | النوع | Default |
|---|---|---|
| `P60_JOURNAL_ID` | Hidden | |
| `P60_JOURNAL_INFO` | Display Only | Source SQL: `SELECT journal_no \|\| ' - ' \|\| TO_CHAR(journal_date,'DD/MM/YYYY') FROM journals WHERE journal_id = :P60_JOURNAL_ID` |
| `P60_REV_DATE` | Date Picker `DD/MM/YYYY` | `TO_CHAR(SYSDATE,'DD/MM/YYYY')` |
| `P60_REASON` | Textarea، Required | |

**الزر:** `REVERSE` "عكس القيد" (Hot، class `js-enter`، Submit، رسالة تأكيد: *هل تريد عكس هذا القيد؟ لا يمكن التراجع*).
Condition: `P60_JOURNAL_ID` Is Not Null.

## Validations (When Button Pressed = REVERSE)

```sql
-- 1. حالة القيد والصلاحية
DECLARE j journals%ROWTYPE; l_cnt NUMBER;
BEGIN
  SELECT * INTO j FROM journals WHERE journal_id = :P60_JOURNAL_ID;
  IF j.status <> 'POSTED'            THEN RETURN 'القيد غير مرحّل أو معكوس مسبقاً'; END IF;
  IF j.reversal_of_id IS NOT NULL
     OR j.jt_code = 'REV'            THEN RETURN 'لا يمكن عكس قيد عكسي'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM invoices WHERE sub_journal_id = j.journal_id;
  IF l_cnt > 0 THEN RETURN 'هذا قيد شركة فرعية ناتج عن فاتورة. اعكس قيد الشركة الأم'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = j.company_id);
  IF l_cnt = 0 THEN RETURN 'ليس لديك صلاحية على هذه الشركة'; END IF;
  RETURN NULL;
EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'القيد غير موجود';
END;
```

```sql
-- 2. تاريخ العكس
DECLARE l_d DATE; l_orig DATE; l_cnt NUMBER;
BEGIN
  l_d := TO_DATE(:P60_REV_DATE, 'DD/MM/YYYY');
  SELECT journal_date INTO l_orig FROM journals WHERE journal_id = :P60_JOURNAL_ID;
  IF l_d < l_orig THEN RETURN 'تاريخ العكس قبل تاريخ القيد الأصلي'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years
  WHERE l_d BETWEEN start_date AND end_date AND is_closed = 'N';
  IF l_cnt = 0 THEN RETURN 'تاريخ العكس خارج سنة مالية مفتوحة'; END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN RETURN 'تاريخ العكس غير صحيح';
END;
```

3. `P60_REASON` Is Not Null: "سبب العكس مطلوب".

## Process: `REVERSE_JOURNAL` (When Button Pressed = REVERSE)

```sql
DECLARE
  l_date  DATE := TO_DATE(:P60_REV_DATE, 'DD/MM/YYYY');
  l_main  journals%ROWTYPE;
  l_msg   VARCHAR2(4000);

  -- عكس قيد واحد، ويرجع رقم القيد العكسي
  FUNCTION reverse_one (p_id NUMBER) RETURN VARCHAR2 IS
    j      journals%ROWTYPE;
    l_new  NUMBER;
    l_seq  NUMBER;
    l_no   VARCHAR2(30);
  BEGIN
    SELECT * INTO j FROM journals WHERE journal_id = p_id FOR UPDATE;
    IF j.status <> 'POSTED' THEN
      raise_application_error(-20020, 'القيد ' || j.journal_no || ' لا يمكن عكسه');
    END IF;

    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = j.company_id AND doc_type = 'REV' AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (j.company_id, 'REV', EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := 'REV-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, source_id, reversal_of_id,
                          reverse_reason, total_debit, total_credit, created_by, posted_by, posted_on)
    VALUES (j.company_id, 'REV', l_no, l_date, j.currency_code, j.exchange_rate,
            SUBSTR('عكس القيد ' || j.journal_no || ' - ' || :P60_REASON, 1, 500), j.journal_no,
            'POSTED', 'REVERSAL', j.journal_id, j.journal_id,
            SUBSTR(:P60_REASON, 1, 500), j.total_credit, j.total_debit, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_new;

    -- تبادل المدين والدائن (بالعملة الأصلية وبالعملة الأساسية بنفس سعر الصرف الأصلي)
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, employee_id, description)
    SELECT l_new, line_no, account_id, credit, debit, credit_base, debit_base,
           partner_company_id, employee_id, SUBSTR('عكس: ' || description, 1, 500)
    FROM   journal_lines WHERE journal_id = p_id;

    UPDATE journals
    SET    status = 'REVERSED', reversed_by_id = l_new, reverse_reason = SUBSTR(:P60_REASON, 1, 500)
    WHERE  journal_id = p_id;

    RETURN l_no;
  END;
BEGIN
  SELECT * INTO l_main FROM journals WHERE journal_id = :P60_JOURNAL_ID;

  IF l_main.source_type = 'INVOICE' THEN
    FOR i IN (SELECT invoice_id, journal_id, sub_journal_id FROM invoices
              WHERE journal_id = l_main.journal_id FOR UPDATE) LOOP
      l_msg := reverse_one(i.journal_id);
      IF i.sub_journal_id IS NOT NULL THEN
        l_msg := l_msg || ' و ' || reverse_one(i.sub_journal_id);
      END IF;
      UPDATE invoices SET status = 'REVERSED' WHERE invoice_id = i.invoice_id;
    END LOOP;

  ELSIF l_main.source_type = 'VOUCHER' THEN
    l_msg := reverse_one(l_main.journal_id);
    UPDATE vouchers SET status = 'REVERSED' WHERE voucher_id = l_main.source_id;

  ELSE
    l_msg := reverse_one(l_main.journal_id);
  END IF;

  apex_application.g_print_success_message := 'تم عكس القيد ' || l_main.journal_no || ' بالقيد ' || l_msg;
  :P60_JOURNAL_ID := NULL;
  :P60_REASON     := NULL;
END;
```

**Branch:** صفحة 60.

## قائمة القيود المعكوسة (Region اختياري أسفل الصفحة)

```sql
SELECT o.journal_no AS "القيد الأصلي", o.journal_date AS "تاريخه",
       r.journal_no AS "القيد العكسي", r.journal_date AS "تاريخ العكس",
       o.total_debit AS "المبلغ", o.currency_code AS "العملة",
       o.reverse_reason AS "السبب", r.created_by AS "بواسطة"
FROM   journals o
JOIN   journals r ON r.journal_id = o.reversed_by_id
WHERE  (:G_USER_ROLE = 'GM' OR o.company_id = :G_COMPANY_ID)
ORDER  BY r.journal_date DESC
```
