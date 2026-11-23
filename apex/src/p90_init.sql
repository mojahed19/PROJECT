DECLARE
  l_items CLOB; l_lines CLOB;
  l_wh NUMBER := TO_NUMBER(apex_application.g_x01);
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'id' VALUE i.item_id, 'code' VALUE i.item_code, 'name' VALUE i.name_ar,
           'bc0' VALUE i.barcode, 'bu' VALUE i.base_unit_id,
           'bc' VALUE (SELECT JSON_OBJECTAGG(KEY ub.barcode VALUE ub.unit_id) FROM item_units ub WHERE ub.item_id = i.item_id AND ub.barcode IS NOT NULL) FORMAT JSON,
           'bal'  VALUE NVL(b.qty_base, 0),
           'cost' VALUE NVL(b.avg_cost, 0),
           'units' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('v' VALUE u.unit_id, 't' VALUE un.name_ar,
                                                           'factor' VALUE u.factor, 'price' VALUE CASE WHEN u.unit_id = i.big_unit_id AND i.big_purchase_price > 0 THEN i.big_purchase_price ELSE NULLIF(i.purchase_price, 0) * u.factor END) ORDER BY u.factor)
                          FROM item_units u JOIN units un ON un.unit_id = u.unit_id
                          WHERE u.item_id = i.item_id) FORMAT JSON
         ) ORDER BY i.item_code RETURNING CLOB)
  INTO   l_items
  FROM   items i
  LEFT JOIN v_stock_balance b ON b.item_id = i.item_id AND b.warehouse_id = l_wh
  WHERE  i.is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT('ITEM_ID' VALUE item_id, 'UNIT_ID' VALUE unit_id,
                                   'QTY' VALUE qty, 'UNIT_COST' VALUE NULLIF(unit_cost, 0))
                       ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   stock_trans_lines
  WHERE  trans_id = TO_NUMBER(apex_application.g_x02)
  AND    (warehouse_id = l_wh OR l_wh IS NULL)          -- في التحويل: سطور المصدر فقط
  AND    (qty_base < 0 OR (SELECT trans_type FROM stock_trans WHERE trans_id = TO_NUMBER(apex_application.g_x02)) <> 'TRANSFER');

  apex_util.prn('{"items":' || COALESCE(l_items, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
