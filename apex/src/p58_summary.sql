SELECT DECODE(i.pay_type, 'CREDIT', 'آجل', DECODE(i.pay_method, 'BANK', 'نقدي - بنك', 'نقدي - خزينة')) AS "طريقة الدفع",
       a.account_code || ' - ' || a.name_ar AS "الحساب",
       COUNT(*) AS "عدد الفواتير",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE 0 END) AS "المبيعات",
       SUM(CASE WHEN i.invoice_type = 'RETURN' THEN i.net_amount ELSE 0 END) AS "المرتجعات",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE -i.net_amount END) AS "الصافي"
FROM   invoices i JOIN accounts a ON a.account_id = i.account_id
WHERE  i.shift_id = :P58_SHIFT_ID AND i.status = 'POSTED'
GROUP BY i.pay_type, i.pay_method, a.account_code, a.name_ar
ORDER BY 1, 2
