SELECT t.trans_id, c.name_ar "الشركة",
       DECODE(t.trans_type,'RECEIPT','استلام','ISSUE','صرف','TRANSFER','تحويل','COUNT','تسوية جرد',
                           'INV_OUT','صرف لشركة','INV_IN','وارد من الأم','POS','نقاط بيع',
                           'OPENING','إشعار إضافة','PURCHASE','مشتريات','DAMAGE','صرف توالف','DAMAGE_WO','تصفير توالف') "النوع",
       t.trans_no "الرقم", t.trans_date "التاريخ", w.name_ar "المخزن", w2.name_ar "إلى مخزن",
       (SELECT SUM(ABS(value_base)) FROM stock_trans_lines l
        WHERE l.trans_id = t.trans_id AND l.warehouse_id = t.warehouse_id) "القيمة",
       DECODE(t.status,'DRAFT','مسودة','POSTED','مرحّلة','REVERSED','معكوسة') "الحالة"
FROM stock_trans t
JOIN companies c ON c.company_id = t.company_id
JOIN warehouses w ON w.warehouse_id = t.warehouse_id
LEFT JOIN warehouses w2 ON w2.warehouse_id = t.to_warehouse_id
WHERE (:G_USER_ROLE = 'ADMIN' OR t.company_id = :G_COMPANY_ID)
