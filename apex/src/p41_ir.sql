SELECT v.voucher_id,
       DECODE(v.voucher_type,'R','إذن توريد','إذن صرف') AS "النوع",
       c.name_ar AS "الشركة", v.voucher_no AS "الرقم", v.voucher_date AS "التاريخ",
       a.name_ar AS "الصندوق/البنك", v.party_name AS "الاسم",
       v.total_amount AS "المبلغ", v.currency_code AS "العملة",
       ROUND(v.total_amount * v.exchange_rate, 2) AS "بالعملة الأساسية",
       DECODE(v.pay_method,'CASH','نقدي','CHEQUE','شيك','TRANSFER','تحويل') AS "الطريقة",
       DECODE(v.status,'DRAFT','مسودة','POSTED','مرحّل','REVERSED','معكوس') AS "الحالة",
       v.created_by AS "المستخدم"
FROM vouchers v
JOIN companies c ON c.company_id = v.company_id
JOIN accounts  a ON a.account_id = v.cash_account_id
WHERE (:G_USER_ROLE = 'GM' OR v.company_id = :G_COMPANY_ID
       OR v.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
AND   (:P41_TYPE IS NULL OR v.voucher_type = :P41_TYPE)
