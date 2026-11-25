SELECT 'مستندات بانتظار المراجعة' "التنبيه",
       (SELECT COUNT(*) FROM journals WHERE status = 'DRAFT' AND source_type IN ('MANUAL','CHEQUE'))
     + (SELECT COUNT(*) FROM vouchers WHERE status = 'DRAFT') "العدد" FROM dual
UNION ALL
SELECT 'مستندات بانتظار الاعتماد',
       (SELECT COUNT(*) FROM journals WHERE status = 'REVIEWED') + (SELECT COUNT(*) FROM vouchers WHERE status = 'REVIEWED') FROM dual
UNION ALL
SELECT 'مستندات معادة للمدخل',
       (SELECT COUNT(*) FROM journals WHERE status = 'RETURNED') + (SELECT COUNT(*) FROM vouchers WHERE status = 'RETURNED') FROM dual
UNION ALL
SELECT 'شيكات مستحقة أو متأخرة', COUNT(*) FROM cheques c JOIN vouchers v ON v.voucher_id = c.voucher_id
WHERE c.status = 'PENDING' AND c.due_date <= TRUNC(SYSDATE) AND v.status IN ('APPROVED','POSTED')
UNION ALL
SELECT 'أصناف تحت حد الطلب', COUNT(*) FROM v_stock_balance b JOIN items i ON i.item_id = b.item_id
WHERE b.qty_base <= i.reorder_level AND (:P1_COMPANY_ID IS NULL OR b.company_id = :P1_COMPANY_ID)
