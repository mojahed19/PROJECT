-- =====================================================================
--  15_damaged_goods.sql
--  التوالف:
--    DAMAGE    فاتورة صرف توالف : تُنقص كمية المخزن عند الاعتماد ، بدون قيد محاسبي
--    DAMAGE_WO تصفير التوالف (قرار المدير آخر السنة) : يُقفل رصيد التوالف ، لا يغيّر الكمية ولا الحسابات
--  يُشغّل مرة واحدة بعد 14 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  PROCEDURE drop_check (p_table VARCHAR2, p_like VARCHAR2) IS
  BEGIN
    FOR c IN (SELECT constraint_name FROM user_constraints
              WHERE table_name = p_table AND constraint_type = 'C'
              AND search_condition_vc LIKE p_like) LOOP
      EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table || ' DROP CONSTRAINT ' || c.constraint_name;
    END LOOP;
  END;
BEGIN
  drop_check('STOCK_TRANS', '%trans_type IN%');
  EXECUTE IMMEDIATE q'~ALTER TABLE stock_trans ADD CONSTRAINT stock_trans_type_ck CHECK
    (trans_type IN ('RECEIPT','ISSUE','TRANSFER','COUNT','INV_OUT','INV_IN','POS','OPENING','PURCHASE','DAMAGE','DAMAGE_WO'))~';
END;
/

-- رصيد التوالف غير المصفّر لكل صنف في كل مخزن (بالوحدة الصغرى): التالف المعتمد − المصفّر المعتمد
CREATE OR REPLACE VIEW v_damaged_balance AS
SELECT l.warehouse_id, l.item_id,
       SUM(CASE t.trans_type WHEN 'DAMAGE' THEN -l.qty_base ELSE -(l.qty * l.factor) END) AS qty_base
FROM   stock_trans_lines l
JOIN   stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED' AND t.trans_type IN ('DAMAGE','DAMAGE_WO')
GROUP  BY l.warehouse_id, l.item_id
HAVING SUM(CASE t.trans_type WHEN 'DAMAGE' THEN -l.qty_base ELSE -(l.qty * l.factor) END) <> 0;
