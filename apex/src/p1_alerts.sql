SELECT 'قيود مسودة' "التنبيه", COUNT(*) "العدد" FROM journals
WHERE status = 'DRAFT' AND created_on < SYSDATE - 3 AND (:P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'سندات مسودة', COUNT(*) FROM vouchers
WHERE status = 'DRAFT' AND created_on < SYSDATE - 3 AND (:P1_COMPANY_ID IS NULL OR company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'أصناف تحت حد الطلب', COUNT(*) FROM v_stock_balance b JOIN items i ON i.item_id = b.item_id
WHERE b.qty_base <= i.reorder_level AND (:P1_COMPANY_ID IS NULL OR b.company_id = :P1_COMPANY_ID)
UNION ALL
SELECT 'ورديات مفتوحة أكثر من 12 ساعة', COUNT(*) FROM pos_shifts s JOIN pos_terminals t ON t.terminal_id = s.terminal_id
WHERE s.status = 'OPEN' AND s.opened_on < SYSDATE - 0.5 AND (:P1_COMPANY_ID IS NULL OR t.company_id = :P1_COMPANY_ID)
