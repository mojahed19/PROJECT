-- =====================================================================
--  04_purchases.sql : فواتير المشتريات (للأم والفرعيات) + إشعار إضافة (بضاعة أول المدة)
--  يُشغَّل بعد 03_phase2_tables.sql ، ويصلح أيضاً لقاعدة مركّبة سابقاً
-- =====================================================================
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- 1) توسيع قيود الأنواع: OPENING (أول المدة) و PURCHASE (فاتورة مشتريات)
-- ---------------------------------------------------------------------
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
  drop_check('STOCK_TRANS', '%source_type IN%');
  drop_check('JOURNALS',    '%source_type IN%');

  EXECUTE IMMEDIATE q'~ALTER TABLE stock_trans ADD CONSTRAINT stock_trans_type_ck CHECK
    (trans_type IN ('RECEIPT','ISSUE','TRANSFER','COUNT','INV_OUT','INV_IN','POS','OPENING','PURCHASE'))~';
  EXECUTE IMMEDIATE q'~ALTER TABLE stock_trans ADD CONSTRAINT stock_trans_src_ck CHECK
    (source_type IN ('MANUAL','INVOICE','POS','PURCHASE'))~';
  EXECUTE IMMEDIATE q'~ALTER TABLE journals ADD CONSTRAINT journals_src_ck CHECK
    (source_type IN ('MANUAL','VOUCHER','INVOICE','PAYROLL','REVERSAL','OPENING','PURCHASE'))~';
END;
/

-- ---------------------------------------------------------------------
-- 2) فواتير المشتريات
-- ---------------------------------------------------------------------
CREATE TABLE purchase_invoices (
  pinv_id             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id          NUMBER         NOT NULL REFERENCES companies,   -- الأم أو أي شركة فرعية
  invoice_type        VARCHAR2(10)   DEFAULT 'PURCHASE' NOT NULL CHECK (invoice_type IN ('PURCHASE','RETURN')),
  invoice_no          VARCHAR2(30)   NOT NULL,                        -- رقمنا الداخلي PUR-2026-00001
  supplier_inv_no     VARCHAR2(50),                                   -- رقم فاتورة المورد
  invoice_date        DATE           NOT NULL,
  pay_type            VARCHAR2(10)   DEFAULT 'CREDIT' NOT NULL CHECK (pay_type IN ('CREDIT','CASH')),
  supplier_account_id NUMBER         NOT NULL REFERENCES accounts,    -- حساب المورد (آجل) أو الصندوق (نقدي)
  supplier_name       VARCHAR2(150),
  warehouse_id        NUMBER         NOT NULL REFERENCES warehouses,
  currency_code       VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate       NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  gross_amount        NUMBER(18,4)   DEFAULT 0 NOT NULL,
  discount_amount     NUMBER(18,4)   DEFAULT 0 NOT NULL,
  net_amount          NUMBER(18,4)   DEFAULT 0 NOT NULL,
  description         VARCHAR2(500),
  status              VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  journal_id          NUMBER         REFERENCES journals,
  stock_trans_id      NUMBER         REFERENCES stock_trans,
  created_by          VARCHAR2(100),
  created_on          DATE           DEFAULT SYSDATE,
  CONSTRAINT purchase_invoices_no_uk UNIQUE (company_id, invoice_type, invoice_no)
);
CREATE INDEX purchase_inv_sup_ix ON purchase_invoices (company_id, supplier_inv_no);

CREATE TABLE purchase_invoice_lines (
  line_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pinv_id         NUMBER         NOT NULL REFERENCES purchase_invoices ON DELETE CASCADE,
  line_no         NUMBER         NOT NULL,
  item_id         NUMBER         NOT NULL,
  unit_id         NUMBER         NOT NULL,
  factor          NUMBER(18,6)   NOT NULL,
  qty             NUMBER(18,4)   NOT NULL CHECK (qty > 0),
  price           NUMBER(18,4)   NOT NULL CHECK (price >= 0),
  discount        NUMBER(18,4)   DEFAULT 0 NOT NULL,
  line_total      NUMBER(18,4)   NOT NULL,
  FOREIGN KEY (item_id, unit_id) REFERENCES item_units
);
CREATE INDEX purchase_lines_ix ON purchase_invoice_lines (pinv_id);

-- نوع قيد المشتريات
INSERT INTO journal_types (jt_code, name_ar, name_en, prefix, manual_allowed, sort_order)
SELECT 'PUR', 'فاتورة مشتريات', 'Purchase Invoice', 'PUR', 'N', 15 FROM dual
WHERE NOT EXISTS (SELECT 1 FROM journal_types WHERE jt_code = 'PUR');
INSERT INTO journal_types (jt_code, name_ar, name_en, prefix, manual_allowed, sort_order)
SELECT 'PRT', 'مرتجع مشتريات', 'Purchase Return', 'PRT', 'N', 16 FROM dual
WHERE NOT EXISTS (SELECT 1 FROM journal_types WHERE jt_code = 'PRT');

COMMIT;
