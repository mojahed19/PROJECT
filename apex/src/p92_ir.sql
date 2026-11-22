SELECT c.name_ar "الشركة", w.name_ar "المخزن", i.item_code "الكود", i.name_ar "الصنف",
       ub.name_ar "الوحدة الأساسية",
       b.qty_base "الرصيد",
       (SELECT LISTAGG(TRUNC(b.qty_base / u.factor) || ' ' || un.name_ar, ' + ') WITHIN GROUP (ORDER BY u.factor DESC)
        FROM item_units u JOIN units un ON un.unit_id = u.unit_id
        WHERE u.item_id = i.item_id AND u.factor > 1) "بالوحدات الكبرى",
       ROUND(b.avg_cost, 4) "متوسط التكلفة",
       ROUND(b.qty_base * b.avg_cost, 2) "قيمة المخزون",
       CASE WHEN b.qty_base <= i.reorder_level THEN 'تحت حد الطلب' END "تنبيه"
FROM v_stock_balance b
JOIN items i ON i.item_id = b.item_id
JOIN units ub ON ub.unit_id = i.base_unit_id
JOIN warehouses w ON w.warehouse_id = b.warehouse_id
JOIN companies c ON c.company_id = b.company_id
WHERE (:G_USER_ROLE = 'ADMIN' OR b.company_id = :G_COMPANY_ID)
AND   b.qty_base <> 0
