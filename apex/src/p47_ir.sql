SELECT c.cheque_id,
       c.due_date AS "تاريخ الاستحقاق",
       CASE WHEN c.status <> 'PENDING' THEN NULL
            WHEN c.due_date <  TRUNC(SYSDATE) THEN 'متأخر'
            WHEN c.due_date =  TRUNC(SYSDATE) THEN 'مستحق اليوم'
            WHEN c.due_date <= TRUNC(SYSDATE) + 7 THEN 'خلال أسبوع' END AS "التنبيه",
       DECODE(v.voucher_type, 'R', 'وارد (تحصيل)', 'صادر (صرف)') AS "النوع",
       c.cheque_no AS "رقم الشيك",
       NVL(b.name_ar, c.bank_name) AS "البنك",
       c.payee_name AS "المستفيد / الساحب",
       c.amount AS "المبلغ",
       DECODE(c.status, 'PENDING', 'قائم',
              'CLEARED', CASE v.voucher_type WHEN 'R' THEN 'تم التحصيل' ELSE 'تم الصرف' END,
              'BOUNCED', 'مرتد') AS "حالة الشيك",
       c.settle_date AS "تاريخ التسوية",
       j.journal_no AS "قيد التسوية",
       DECODE(j.status, 'DRAFT', 'مسودة', 'RETURNED', 'معاد للمدخل', 'REVIEWED', 'مُراجَع',
              'APPROVED', 'معتمد', 'POSTED', 'مرحّل', 'REVERSED', 'معكوس') AS "حالة القيد",
       v.voucher_no AS "رقم الإذن",
       ca.name_ar AS "الحساب المقابل",
       'اختيار' AS "إجراء"
FROM   cheques c
JOIN   vouchers v ON v.voucher_id = c.voucher_id
LEFT JOIN accounts b  ON b.account_id  = c.bank_account_id
LEFT JOIN accounts ca ON ca.account_id = v.counter_account_id
LEFT JOIN journals j  ON j.journal_id  = c.settle_journal_id
WHERE  v.status IN ('APPROVED','POSTED')
AND    (:P47_TYPE IS NULL OR v.voucher_type = :P47_TYPE)
AND    (:P47_STATUS IS NULL OR c.status = :P47_STATUS)
AND    c.due_date BETWEEN NVL(TO_DATE(:P47_FROM, 'DD/MM/YYYY'), DATE '1900-01-01')
                      AND NVL(TO_DATE(:P47_TO,   'DD/MM/YYYY'), DATE '2999-12-31')
ORDER BY c.due_date, c.cheque_no
