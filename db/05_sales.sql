-- =====================================================================
--  05_sales.sql : فاتورة المبيعات لفروع الشركة وللعملاء الخارجيين
--                 + طريقة الدفع (صندوق / تحويل بنكي / آجل) للمبيعات والمشتريات
--  يُشغَّل بعد 04_purchases.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) جدول الفواتير: العميل فرع أو عميل خارجي، والدفع نقدي أو آجل
-- ---------------------------------------------------------------------
ALTER TABLE invoices ADD (
  customer_type   VARCHAR2(10) DEFAULT 'BRANCH' NOT NULL,   -- BRANCH فرع من الشركة / EXTERNAL عميل خارجي
  pay_type        VARCHAR2(10) DEFAULT 'CREDIT' NOT NULL,   -- CASH نقدي / CREDIT آجل
  pay_method      VARCHAR2(10),                             -- للنقدي: CASH صندوق / BANK تحويل بنكي
  account_id      NUMBER REFERENCES accounts,               -- الصندوق أو البنك (نقدي) أو حساب العميل (آجل)
  customer_name   VARCHAR2(150)
);
ALTER TABLE invoices MODIFY (customer_company_id NULL, price_list_id NULL);
ALTER TABLE invoices ADD CONSTRAINT invoices_cust_ck CHECK (
  (customer_type = 'BRANCH'   AND customer_company_id IS NOT NULL) OR
  (customer_type = 'EXTERNAL' AND customer_company_id IS NULL));
ALTER TABLE invoices ADD CONSTRAINT invoices_pay_ck CHECK (
  pay_type IN ('CASH','CREDIT') AND (pay_type = 'CREDIT' OR pay_method IN ('CASH','BANK')));

-- ---------------------------------------------------------------------
-- 2) المشتريات: طريقة الدفع للنقدي
-- ---------------------------------------------------------------------
ALTER TABLE purchase_invoices ADD (pay_method VARCHAR2(10));
ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_pay_ck CHECK (pay_type = 'CREDIT' OR pay_method IN ('CASH','BANK'));

-- ---------------------------------------------------------------------
-- 3) حساب مبيعات العملاء الخارجيين
-- ---------------------------------------------------------------------
UPDATE accounts SET name_ar = 'مبيعات للعملاء' WHERE account_code = '4101002';

INSERT INTO account_settings (company_id, setting_code, account_id)
SELECT c.company_id, 'SALES_EXT', a.account_id
FROM   companies c JOIN accounts a ON a.account_code = '4101002'
WHERE  NOT EXISTS (SELECT 1 FROM account_settings s WHERE s.company_id = c.company_id AND s.setting_code = 'SALES_EXT');

-- مردودات المبيعات و تكلفة المبيعات والمخزون موجودة لكل الشركات من 02 و 03
COMMIT;
