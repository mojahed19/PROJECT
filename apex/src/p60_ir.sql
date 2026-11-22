SELECT j.journal_id,
       j.journal_no           AS "رقم القيد",
       j.journal_date         AS "التاريخ",
       c.name_ar              AS "الشركة",
       t.name_ar              AS "النوع",
       j.total_debit          AS "المبلغ",
       j.currency_code        AS "العملة",
       j.description          AS "البيان",
       DECODE(j.source_type,'MANUAL','يدوي','CHEQUE','تسوية شيك','VOUCHER','إذن','INVOICE','فاتورة','PAYROLL','رواتب') AS "المصدر",
       'اختيار'               AS "اختيار"
FROM   journals j
JOIN   companies c     ON c.company_id = j.company_id
JOIN   journal_types t ON t.jt_code    = j.jt_code
WHERE  j.status = 'POSTED'
AND    j.reversal_of_id IS NULL
AND    j.jt_code <> 'REV'
AND    (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID
        OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
-- قيد الشركة الفرعية الناتج عن فاتورة يُعكس من قيد الأم فقط
AND    NOT EXISTS (SELECT 1 FROM invoices i WHERE i.sub_journal_id = j.journal_id)
