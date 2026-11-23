-- =====================================================================
--  12_items_shifts.sql
--  * الأصناف: الوحدة الكبرى وما يعادلها من الصغرى وأسعارها وتاريخ الصلاحية
--  * المشتريات وحركات المخزون (منها إشعار الإضافة): مراجعة ثم اعتماد (يُرحّل عند الاعتماد)
--  * ورديات المبيعات: تُفتح وتُغلق ثم تُراجع وتُعتمد ، وعند الاعتماد تُرحّل قيود مبيعاتها
--  يُشغّل مرة واحدة بعد 11 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  PROCEDURE add_col (p_table VARCHAR2, p_col VARCHAR2, p_def VARCHAR2) IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = UPPER(p_table) AND column_name = UPPER(p_col);
    IF l_cnt = 0 THEN EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table || ' ADD (' || p_col || ' ' || p_def || ')'; END IF;
  END;
  PROCEDURE drop_checks (p_table VARCHAR2, p_col VARCHAR2) IS
  BEGIN
    FOR c IN (SELECT cc.constraint_name
              FROM   user_constraints cc
              JOIN   user_cons_columns col ON col.constraint_name = cc.constraint_name
              WHERE  cc.table_name = UPPER(p_table) AND cc.constraint_type = 'C'
              AND    col.column_name = UPPER(p_col)
              AND    UPPER(cc.search_condition_vc) LIKE '% IN %') LOOP
      EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table || ' DROP CONSTRAINT ' || c.constraint_name;
    END LOOP;
  END;
BEGIN
  ------------------------------------------------------------------ الأصناف
  add_col('ITEMS', 'big_unit_id',        'NUMBER REFERENCES units');
  add_col('ITEMS', 'big_factor',         'NUMBER(18,4)');
  add_col('ITEMS', 'big_purchase_price', 'NUMBER(18,4)');
  add_col('ITEMS', 'big_sale_price',     'NUMBER(18,4)');
  add_col('ITEMS', 'expiry_date',        'DATE');

  ------------------------------------------------------------------ دورة المراجعة للمشتريات وحركات المخزون
  FOR t IN (SELECT 'PURCHASE_INVOICES' tn FROM dual UNION ALL SELECT 'STOCK_TRANS' FROM dual) LOOP
    drop_checks(t.tn, 'STATUS');
    add_col(t.tn, 'reviewed_by', 'VARCHAR2(100)');
    add_col(t.tn, 'reviewed_on', 'DATE');
    add_col(t.tn, 'approved_by', 'VARCHAR2(100)');
    add_col(t.tn, 'approved_on', 'DATE');
    add_col(t.tn, 'return_note', 'VARCHAR2(500)');
  END LOOP;
  EXECUTE IMMEDIATE q'[ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_inv_status_ck
      CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','POSTED','REVERSED'))]';
  EXECUTE IMMEDIATE q'[ALTER TABLE stock_trans ADD CONSTRAINT stock_trans_status_ck
      CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','POSTED','REVERSED'))]';

  ------------------------------------------------------------------ الورديات
  add_col('INVOICES', 'shift_id', 'NUMBER');
END;
/

DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'SALES_SHIFTS';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE sales_shifts (
  shift_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id   NUMBER        NOT NULL REFERENCES companies,
  shift_no     VARCHAR2(20)  NOT NULL UNIQUE,            -- 17 + السنة + 5 خانات
  user_name    VARCHAR2(100) NOT NULL,
  opened_on    DATE          DEFAULT SYSDATE NOT NULL,
  closed_on    DATE,
  -- OPEN مفتوحة ، DRAFT مغلقة بانتظار المراجعة ، RETURNED معادة للبائع ، REVIEWED ، POSTED معتمدة ومرحّلة
  status       VARCHAR2(10)  DEFAULT 'OPEN' NOT NULL
               CHECK (status IN ('OPEN','DRAFT','RETURNED','REVIEWED','APPROVED','POSTED')),
  notes        VARCHAR2(500),
  reviewed_by  VARCHAR2(100), reviewed_on DATE,
  approved_by  VARCHAR2(100), approved_on DATE,
  return_note  VARCHAR2(500)
)]';
    EXECUTE IMMEDIATE 'CREATE INDEX sales_shifts_user_ix ON sales_shifts (user_name, status)';
    EXECUTE IMMEDIATE 'ALTER TABLE invoices ADD CONSTRAINT invoices_shift_fk FOREIGN KEY (shift_id) REFERENCES sales_shifts';
  END IF;
END;
/

-- الوحدة الكبرى للأصناف الحالية: أكبر وحدة في وحدات الصنف
UPDATE items i
SET    (big_unit_id, big_factor) = (SELECT MAX(u.unit_id) KEEP (DENSE_RANK LAST ORDER BY u.factor), MAX(u.factor)
                                    FROM item_units u WHERE u.item_id = i.item_id AND u.factor > 1)
WHERE  i.big_unit_id IS NULL
AND    EXISTS (SELECT 1 FROM item_units u WHERE u.item_id = i.item_id AND u.factor > 1);

COMMIT;
