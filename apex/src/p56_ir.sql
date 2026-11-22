SELECT p.pinv_id,
       DECODE(p.invoice_type,'PURCHASE','مشتريات','مرتجع') AS "النوع",
       c.name_ar AS "الشركة", p.invoice_no AS "الرقم", p.supplier_inv_no AS "رقم فاتورة المورد",
       p.invoice_date AS "التاريخ", NVL(p.supplier_name, a.name_ar) AS "المورد",
       DECODE(p.pay_type,'CASH','نقدي','آجل') AS "الدفع", w.name_ar AS "المخزن",
       p.net_amount AS "الصافي", p.currency_code AS "العملة",
       ROUND(p.net_amount * p.exchange_rate, 2) AS "بالعملة الأساسية",
       DECODE(p.status,'DRAFT','مسودة','POSTED','مرحّلة','REVERSED','معكوسة') AS "الحالة",
       p.invoice_type AS invoice_type_code,
       'طباعة' AS "طباعة A4"
FROM purchase_invoices p
JOIN companies  c ON c.company_id = p.company_id
JOIN accounts   a ON a.account_id = p.supplier_account_id
JOIN warehouses w ON w.warehouse_id = p.warehouse_id
WHERE (:G_USER_ROLE = 'ADMIN' OR p.company_id = :G_COMPANY_ID
       OR p.company_id IN (SELECT company_id FROM user_companies WHERE user_name = UPPER(:APP_USER)))
