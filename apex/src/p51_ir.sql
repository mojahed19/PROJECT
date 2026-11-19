SELECT i.invoice_id,
       i.invoice_type AS invoice_type_code,
       DECODE(i.invoice_type,'SALE','مبيعات','مرتجع مبيعات') AS "النوع",
       i.invoice_no AS "الرقم", i.invoice_date AS "التاريخ",
       CASE i.customer_type WHEN 'BRANCH' THEN 'فرع: ' || c.name_ar
            ELSE NVL(i.customer_name, a.name_ar) END AS "العميل",
       CASE WHEN i.pay_type = 'CREDIT' THEN 'آجل'
            WHEN i.pay_method = 'BANK' THEN 'نقدي - تحويل بنكي' ELSE 'نقدي - صندوق' END AS "الدفع",
       a.name_ar AS "الحساب",
       w.name_ar AS "المخزن",
       i.net_amount AS "الصافي", i.currency_code AS "العملة",
       ROUND(i.net_amount * i.exchange_rate, 2) * DECODE(i.invoice_type,'SALE',1,-1) AS "بالعملة الأساسية",
       DECODE(i.status,'DRAFT','مسودة','POSTED','مرحّلة','REVERSED','معكوسة') AS "الحالة",
       'طباعة' AS "طباعة A4",
       'إيصال' AS "إيصال"
FROM invoices i
LEFT JOIN companies c ON c.company_id = i.customer_company_id
LEFT JOIN accounts  a ON a.account_id = i.account_id
JOIN warehouses w ON w.warehouse_id = i.warehouse_id
WHERE i.company_id = :G_PARENT_ID
