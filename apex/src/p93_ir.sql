SELECT t.trans_date "التاريخ", t.trans_no "رقم الحركة",
       DECODE(t.trans_type,'RECEIPT','استلام','ISSUE','صرف','TRANSFER','تحويل','COUNT','جرد',
                           'INV_OUT','صرف لشركة','INV_IN','وارد من الأم','POS','مبيعات') "النوع",
       CASE WHEN l.qty_base > 0 THEN l.qty_base END "وارد",
       CASE WHEN l.qty_base < 0 THEN -l.qty_base END "صادر",
       SUM(l.qty_base) OVER (ORDER BY t.trans_date, t.trans_id, l.line_id ROWS UNBOUNDED PRECEDING) "الرصيد",
       ROUND(l.cost_base, 4) "التكلفة"
FROM stock_trans_lines l
JOIN stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED'
WHERE l.item_id = :P93_ITEM_ID
AND   l.warehouse_id = :P93_WAREHOUSE_ID
ORDER BY t.trans_date, t.trans_id, l.line_id
