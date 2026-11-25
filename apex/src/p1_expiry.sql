-- أصناف قاربت انتهاء الصلاحية خلال 3 أشهر (أو انتهت) مع كمياتها بالمخزن
SELECT i.item_id, i.item_code AS "الكود", i.name_ar AS "الصنف",
       TO_CHAR(i.expiry_date, 'DD/MM/YYYY') AS "تاريخ الصلاحية",
       TRUNC(i.expiry_date) - TRUNC(SYSDATE) AS "عدد الأيام المتبقية",
       CASE WHEN i.expiry_date < TRUNC(SYSDATE) THEN 'منتهي الصلاحية'
            WHEN i.expiry_date <= ADD_MONTHS(TRUNC(SYSDATE), 1) THEN 'أقل من شهر'
            ELSE 'خلال 3 أشهر' END AS "التنبيه",
       un.name_ar AS "الوحدة الصغرى",
       NVL((SELECT SUM(b.qty_base) FROM v_stock_balance b WHERE b.item_id = i.item_id), 0) AS "الكمية بالمخزن",
       NVL((SELECT SUM(b.value_base) FROM v_stock_balance b WHERE b.item_id = i.item_id), 0) AS "القيمة"
FROM   items i JOIN units un ON un.unit_id = i.base_unit_id
WHERE  i.is_active = 'Y' AND i.expiry_date IS NOT NULL
AND    i.expiry_date <= ADD_MONTHS(TRUNC(SYSDATE), 3)
ORDER BY i.expiry_date
