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
