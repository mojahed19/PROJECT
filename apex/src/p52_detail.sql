SELECT i.invoice_id, i.invoice_no AS "رقم الفاتورة", TO_CHAR(i.invoice_date, 'DD/MM/YYYY') AS "التاريخ",
       i.created_by AS "المستخدم",
       DECODE(i.invoice_type, 'SALE', 'مبيعات', 'مرتجع') AS "النوع",
       DECODE(i.pay_type, 'CREDIT', 'آجل', DECODE(i.pay_method, 'BANK', 'نقدي - بنك', 'نقدي - خزينة')) AS "طريقة الدفع",
       a.name_ar AS "الحساب", NVL(i.customer_name, a.name_ar) AS "العميل",
       CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE -i.net_amount END AS "الصافي",
       s.shift_no AS "الوردية"
FROM   invoices i JOIN accounts a ON a.account_id = i.account_id
LEFT JOIN sales_shifts s ON s.shift_id = i.shift_id
WHERE  i.status = 'POSTED' AND i.invoice_date BETWEEN NVL(TO_DATE(:P52_FROM, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND NVL(TO_DATE(:P52_TO, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND (:P52_USER IS NULL OR i.created_by = :P52_USER)
ORDER BY i.invoice_id
