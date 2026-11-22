SELECT j.journal_id,
       c.name_ar                  AS "الشركة",
       t.name_ar                  AS "النوع",
       j.journal_no               AS "رقم القيد",
       j.journal_date             AS "التاريخ",
       j.currency_code            AS "العملة",
       j.exchange_rate            AS "السعر",
       j.total_debit              AS "الإجمالي",
       j.total_debit * j.exchange_rate AS "الإجمالي بالأساسية",
       j.description              AS "البيان",
       DECODE(j.status,'DRAFT','مسودة','RETURNED','معاد للمدخل','REVIEWED','مُراجَع','APPROVED','معتمد','POSTED','مرحّل','REVERSED','معكوس') AS "الحالة",
       DECODE(j.source_type,'MANUAL','يدوي','CHEQUE','تسوية شيك','VOUCHER','إذن','INVOICE','فاتورة',
              'PAYROLL','رواتب','REVERSAL','عكس','OPENING','افتتاحي') AS "المصدر",
       j.created_by               AS "المستخدم"
FROM   journals j
JOIN   companies c     ON c.company_id = j.company_id
JOIN   journal_types t ON t.jt_code    = j.jt_code
WHERE  (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID
        OR j.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
AND    (:P31_COMPANY_ID IS NULL OR j.company_id = :P31_COMPANY_ID)
AND    j.journal_date BETWEEN NVL(TO_DATE(:P31_FROM,'DD/MM/YYYY'), DATE '1900-01-01')
                          AND NVL(TO_DATE(:P31_TO,'DD/MM/YYYY'),   DATE '2999-12-31')
