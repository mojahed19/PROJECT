SELECT s.shift_id, s.shift_no AS "رقم الوردية", s.user_name AS "البائع",
       TO_CHAR(s.opened_on, 'DD/MM/YYYY HH24:MI') AS "الفتح", TO_CHAR(s.closed_on, 'DD/MM/YYYY HH24:MI') AS "الإغلاق",
       (SELECT COUNT(*) FROM invoices i WHERE i.shift_id = s.shift_id AND i.status = 'POSTED') AS "عدد الفواتير",
       (SELECT SUM(CASE WHEN i.invoice_type = 'SALE' THEN i.net_amount ELSE -i.net_amount END)
        FROM invoices i WHERE i.shift_id = s.shift_id AND i.status = 'POSTED') AS "صافي المبيعات",
       DECODE(s.status, 'OPEN', 'مفتوحة', 'DRAFT', 'مغلقة - بانتظار المراجعة', 'RETURNED', 'معادة للبائع',
              'REVIEWED', 'مُراجَعة - بانتظار الاعتماد', 'POSTED', 'معتمدة ومرحّلة') AS "الحالة",
       s.reviewed_by AS "المراجع", s.approved_by AS "المعتمد"
FROM   sales_shifts s
WHERE  (:G_USER_ROLE <> 'ENTRY' OR s.user_name = :APP_USER)
AND    (:P59_STATUS IS NULL OR s.status = :P59_STATUS)
ORDER BY s.shift_id DESC
