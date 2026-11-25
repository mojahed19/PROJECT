-- التوالف غير المصفّاة (تنتظر قرار المدير بالتصفير): لكل مخزن وصنف بالوحدة الصغرى وقيمتها بسعر الشراء
WITH d AS (
  SELECT w.name_ar wh, i.item_code, i.name_ar item, un.name_ar unit, d.qty_base qty, NVL(i.purchase_price, 0) price
  FROM   v_damaged_balance d
  JOIN   warehouses w ON w.warehouse_id = d.warehouse_id
  JOIN   items i      ON i.item_id      = d.item_id
  JOIN   units un     ON un.unit_id     = i.base_unit_id
  WHERE  d.qty_base > 0
  AND    (:P1_COMPANY_ID IS NULL OR w.company_id = TO_NUMBER(:P1_COMPANY_ID))
)
SELECT wh || LPAD(item_code, 20, '0') AS sort_key, wh AS "المخزن", item_code AS "الكود", item AS "الصنف",
       qty AS "الكمية التالفة", unit AS "الوحدة", ROUND(qty * price, 2) AS "القيمة"
FROM   d
UNION ALL
SELECT 'zzzz', NULL, NULL, 'إجمالي التوالف غير المصفّاة', NULL, NULL, NVL(SUM(ROUND(qty * price, 2)), 0)
FROM   d
ORDER  BY 1
