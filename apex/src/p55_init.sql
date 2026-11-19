DECLARE
  l_items CLOB;
  l_lines CLOB;
  l_wh    NUMBER := TO_NUMBER(apex_application.g_x01);
BEGIN
  -- كل الأصناف الفعّالة: الكود، الاسم، الباركودات، الوحدات وآخر سعر شراء لكل وحدة
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'id'   VALUE i.item_id,
           'code' VALUE i.item_code,
           'name' VALUE i.name_ar,
           'bc0'  VALUE i.barcode,
           'bu'   VALUE i.base_unit_id,
           'bc'   VALUE (SELECT JSON_OBJECTAGG(KEY ub.barcode VALUE ub.unit_id)
                         FROM item_units ub WHERE ub.item_id = i.item_id AND ub.barcode IS NOT NULL) FORMAT JSON,
           'bal'  VALUE NVL(b.qty_base, 0),
           'units' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                                   'v'      VALUE u.unit_id,
                                   't'      VALUE un.name_ar,
                                   'factor' VALUE u.factor,
                                   'price'  VALUE (SELECT MAX(l.price) KEEP (DENSE_RANK LAST ORDER BY p.invoice_date, l.line_id)
                                                   FROM purchase_invoice_lines l
                                                   JOIN purchase_invoices p ON p.pinv_id = l.pinv_id AND p.status = 'POSTED'
                                                   WHERE l.item_id = u.item_id AND l.unit_id = u.unit_id))
                                 ORDER BY u.factor)
                          FROM item_units u JOIN units un ON un.unit_id = u.unit_id
                          WHERE u.item_id = i.item_id) FORMAT JSON
         ) ORDER BY i.item_code RETURNING CLOB)
  INTO   l_items
  FROM   items i
  LEFT JOIN v_stock_balance b ON b.item_id = i.item_id AND b.warehouse_id = l_wh
  WHERE  i.is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'ITEM_ID' VALUE item_id, 'UNIT_ID' VALUE unit_id, 'QTY' VALUE qty,
           'PRICE' VALUE price, 'DISCOUNT' VALUE NULLIF(discount, 0), 'LINE_TOTAL' VALUE line_total)
         ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   purchase_invoice_lines WHERE pinv_id = TO_NUMBER(apex_application.g_x02);

  apex_util.prn('{"items":' || COALESCE(l_items, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
