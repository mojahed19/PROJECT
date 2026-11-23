SELECT a.account_code || ' - ' || a.name_ar AS "الحساب المدفوع به",
       DECODE(a.cash_bank, 'C', 'خزينة', 'B', 'بنك', 'حساب عميل') AS "النوع",
       COUNT(*) AS "عدد الفواتير",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE 0 END) AS "المبيعات",
       SUM(CASE WHEN i.invoice_type = 'RETURN' THEN i.net_amount ELSE 0 END) AS "المرتجعات",
       SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE -i.net_amount END) AS "الصافي"
FROM   invoices i JOIN accounts a ON a.account_id = i.account_id
WHERE  i.status = 'POSTED' AND i.invoice_date BETWEEN NVL(TO_DATE(:P52_FROM, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND NVL(TO_DATE(:P52_TO, 'DD/MM/YYYY'), TRUNC(SYSDATE)) AND (:P52_USER IS NULL OR i.created_by = :P52_USER)
GROUP BY a.account_code, a.name_ar, a.cash_bank
ORDER BY 1
