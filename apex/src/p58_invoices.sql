SELECT i.invoice_no AS "رقم الفاتورة", TO_CHAR(i.created_on, 'HH24:MI') AS "الوقت",
       DECODE(i.invoice_type, 'SALE', 'مبيعات', 'مرتجع') AS "النوع",
       DECODE(i.pay_type, 'CREDIT', 'آجل', DECODE(i.pay_method, 'BANK', 'نقدي - بنك', 'نقدي - خزينة')) AS "الدفع",
       NVL(i.customer_name, a.name_ar) AS "العميل",
       i.net_amount AS "الصافي",
       DECODE(i.status, 'DRAFT', 'مسودة', 'POSTED', 'محفوظة', 'REVERSED', 'معكوسة') AS "الحالة"
FROM   invoices i JOIN accounts a ON a.account_id = i.account_id
WHERE  i.shift_id = :P58_SHIFT_ID
ORDER BY i.invoice_id
