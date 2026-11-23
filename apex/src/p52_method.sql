SELECT DECODE(i.pay_type, 'CREDIT', 'آجل', DECODE(i.pay_method, 'BANK', 'نقدي - بنك', 'نقدي - خزينة')) AS "طريقة الدفع",
       COUNT(*) AS "عدد الفواتير",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE 0 END) AS "المبيعات",
       SUM(CASE WHEN i.invoice_type = 'RETURN' THEN i.net_amount ELSE 0 END) AS "المرتجعات",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE -i.net_amount END) AS "الصافي"
FROM   invoices i
WHERE  i.status = 'POSTED' AND i.invoice_date BETWEEN NVL(TO_DATE(:P52_FROM, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND NVL(TO_DATE(:P52_TO, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND (:P52_USER IS NULL OR i.created_by = :P52_USER)
GROUP BY i.pay_type, i.pay_method
ORDER BY 1
