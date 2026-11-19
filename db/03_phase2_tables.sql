-- =====================================================================
--  03_phase2_tables.sql : المخزون، مسير الرواتب، نقاط البيع، الموازنة
--  يُشغَّل بعد 01_tables.sql و 02_seed.sql
-- =====================================================================
SET DEFINE OFF

-- =====================================================================
-- 1) المخزون (نظام جرد مستمر بمتوسط التكلفة - بالوحدة الأساسية والعملة الأساسية)
-- =====================================================================
CREATE TABLE stock_trans (
  trans_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  trans_type        VARCHAR2(10)   NOT NULL
                    CHECK (trans_type IN ('RECEIPT','ISSUE','TRANSFER','COUNT','INV_OUT','INV_IN','POS')),
                    -- RECEIPT استلام من مورد , ISSUE صرف داخلي , TRANSFER تحويل بين مخازن الشركة
                    -- COUNT تسوية جرد , INV_OUT/INV_IN آلي من فواتير الشركات , POS آلي من نقاط البيع
  trans_no          VARCHAR2(30)   NOT NULL,
  trans_date        DATE           NOT NULL,
  warehouse_id      NUMBER         NOT NULL REFERENCES warehouses,
  to_warehouse_id   NUMBER         REFERENCES warehouses,          -- للتحويل
  counter_account_id NUMBER        REFERENCES accounts,            -- المورد / حساب الصرف
  currency_code     VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate     NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  description       VARCHAR2(500),
  source_type       VARCHAR2(10)   DEFAULT 'MANUAL' NOT NULL CHECK (source_type IN ('MANUAL','INVOICE','POS')),
  source_id         NUMBER,
  status            VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  journal_id        NUMBER         REFERENCES journals,
  created_by        VARCHAR2(100),
  created_on        DATE           DEFAULT SYSDATE,
  CONSTRAINT stock_trans_no_uk UNIQUE (company_id, trans_type, trans_no)
);
CREATE INDEX stock_trans_src_ix ON stock_trans (source_type, source_id);

CREATE TABLE stock_trans_lines (
  line_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  trans_id          NUMBER         NOT NULL REFERENCES stock_trans ON DELETE CASCADE,
  line_no           NUMBER         NOT NULL,
  warehouse_id      NUMBER         NOT NULL REFERENCES warehouses,  -- المخزن الذي تتأثر كميته
  item_id           NUMBER         NOT NULL,
  unit_id           NUMBER         NOT NULL,
  factor            NUMBER(18,6)   NOT NULL,
  qty               NUMBER(18,4)   NOT NULL,                        -- بالوحدة المختارة (موجبة دائماً)
  qty_base          NUMBER(18,4)   NOT NULL,                        -- بالوحدة الأساسية: + وارد / - صادر
  unit_cost         NUMBER(18,6)   DEFAULT 0 NOT NULL,              -- تكلفة الوحدة المختارة بعملة الحركة
  cost_base         NUMBER(18,6)   DEFAULT 0 NOT NULL,              -- تكلفة الوحدة الأساسية بالعملة الأساسية
  value_base        NUMBER(18,4)   DEFAULT 0 NOT NULL,              -- qty_base * cost_base (بإشارة)
  FOREIGN KEY (item_id, unit_id) REFERENCES item_units
);
CREATE INDEX stl_trans_ix ON stock_trans_lines (trans_id);
CREATE INDEX stl_item_ix  ON stock_trans_lines (warehouse_id, item_id);

ALTER TABLE invoices ADD (
  to_warehouse_id   NUMBER REFERENCES warehouses,                   -- مخزن الشركة الفرعية المستلِم
  stock_out_id      NUMBER REFERENCES stock_trans,
  stock_in_id       NUMBER REFERENCES stock_trans
);

-- رصيد ومتوسط تكلفة كل صنف في كل مخزن (الحركات المرحّلة فقط)
CREATE OR REPLACE VIEW v_stock_balance AS
SELECT l.warehouse_id, w.company_id, l.item_id,
       SUM(l.qty_base)                                             AS qty_base,
       SUM(l.value_base)                                           AS value_base,
       CASE WHEN SUM(CASE WHEN l.qty_base > 0 THEN l.qty_base END) > 0
            THEN SUM(CASE WHEN l.qty_base > 0 THEN l.value_base END)
               / SUM(CASE WHEN l.qty_base > 0 THEN l.qty_base END) END AS avg_cost
FROM   stock_trans_lines l
JOIN   stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED'
JOIN   warehouses  w ON w.warehouse_id = l.warehouse_id
GROUP  BY l.warehouse_id, w.company_id, l.item_id;

-- =====================================================================
-- 2) مسير الرواتب
-- =====================================================================
CREATE TABLE payroll_runs (
  run_id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pay_period        VARCHAR2(6)    NOT NULL,                        -- YYYYMM
  company_id        NUMBER         REFERENCES companies,            -- NULL = كل الشركات
  run_date          DATE           DEFAULT TRUNC(SYSDATE) NOT NULL,
  currency_code     VARCHAR2(3)    NOT NULL REFERENCES currencies,  -- عملة المسير (الأساسية)
  status            VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL CHECK (status IN ('DRAFT','APPROVED','CANCELLED')),
  total_net         NUMBER(18,4)   DEFAULT 0 NOT NULL,
  notes             VARCHAR2(500),
  created_by        VARCHAR2(100),
  created_on        DATE           DEFAULT SYSDATE,
  approved_by       VARCHAR2(100),
  approved_on       DATE
);
-- لا يتكرر مسير معتمد أو مسودة لنفس الشهر والشركة
CREATE UNIQUE INDEX payroll_runs_uk ON payroll_runs
  (CASE WHEN status <> 'CANCELLED' THEN pay_period END,
   CASE WHEN status <> 'CANCELLED' THEN NVL(company_id, 0) END);

CREATE TABLE payroll_lines (
  pline_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id            NUMBER         NOT NULL REFERENCES payroll_runs ON DELETE CASCADE,
  employee_id       NUMBER         NOT NULL REFERENCES employees,
  company_id        NUMBER         NOT NULL REFERENCES companies,   -- الشركة التي يُحمَّل عليها
  grade_id          NUMBER         NOT NULL REFERENCES job_grades,
  basic_salary      NUMBER(18,4)   DEFAULT 0 NOT NULL,
  total_allowances  NUMBER(18,4)   DEFAULT 0 NOT NULL,
  total_incentives  NUMBER(18,4)   DEFAULT 0 NOT NULL,
  total_diff        NUMBER(18,4)   DEFAULT 0 NOT NULL,              -- بإشارة
  total_deductions  NUMBER(18,4)   DEFAULT 0 NOT NULL,
  net_salary        NUMBER(18,4)   DEFAULT 0 NOT NULL,
  CONSTRAINT payroll_lines_uk UNIQUE (run_id, employee_id)
);

CREATE TABLE payroll_line_details (
  detail_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pline_id          NUMBER         NOT NULL REFERENCES payroll_lines ON DELETE CASCADE,
  item_kind         VARCHAR2(10)   NOT NULL CHECK (item_kind IN ('BASIC','ALLOWANCE','INCENTIVE','DIFF','DEDUCTION')),
  allowance_id      NUMBER         REFERENCES allowance_types,
  adj_id            NUMBER         REFERENCES payroll_adj,          -- إن جاء من شاشة الخصم/الفرق/الحافز
  description       VARCHAR2(200),
  amount            NUMBER(18,4)   NOT NULL                         -- موجب = استحقاق ، سالب = استقطاع
);
CREATE INDEX pld_line_ix ON payroll_line_details (pline_id);

ALTER TABLE payroll_adj ADD CONSTRAINT payroll_adj_run_fk
  FOREIGN KEY (applied_run_id) REFERENCES payroll_runs;

CREATE TABLE payroll_run_journals (                 -- القيود الناتجة عن المسير (قيد لكل شركة)
  run_id            NUMBER NOT NULL REFERENCES payroll_runs,
  journal_id        NUMBER NOT NULL REFERENCES journals,
  PRIMARY KEY (run_id, journal_id)
);

-- =====================================================================
-- 3) نقاط البيع (منفصلة لكل شركة)
-- =====================================================================
ALTER TABLE companies ADD (
  pos_price_list_id NUMBER REFERENCES price_lists                    -- أسعار البيع للجمهور في نقاط بيع الشركة
);

CREATE TABLE pos_terminals (
  terminal_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  name_ar           VARCHAR2(100)  NOT NULL,
  warehouse_id      NUMBER         NOT NULL REFERENCES warehouses,   -- المخزن الذي يبيع منه
  cash_account_id   NUMBER         NOT NULL REFERENCES accounts,     -- صندوق نقطة البيع
  card_account_id   NUMBER         REFERENCES accounts,              -- حساب البطاقات/الشبكة
  is_active         CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

CREATE TABLE pos_terminal_users (
  terminal_id       NUMBER         NOT NULL REFERENCES pos_terminals,
  user_name         VARCHAR2(100)  NOT NULL REFERENCES app_users,
  PRIMARY KEY (terminal_id, user_name)
);

CREATE TABLE pos_shifts (
  shift_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  terminal_id       NUMBER         NOT NULL REFERENCES pos_terminals,
  user_name         VARCHAR2(100)  NOT NULL,
  opened_on         DATE           DEFAULT SYSDATE NOT NULL,
  opening_cash      NUMBER(18,4)   DEFAULT 0 NOT NULL,               -- بالعملة الأساسية
  closed_on         DATE,
  counted_cash      NUMBER(18,4),                                    -- النقد المعدود عند الإغلاق
  expected_cash     NUMBER(18,4),
  status            VARCHAR2(10)   DEFAULT 'OPEN' NOT NULL CHECK (status IN ('OPEN','CLOSED')),
  journal_id        NUMBER         REFERENCES journals,
  stock_trans_id    NUMBER         REFERENCES stock_trans
);
-- وردية مفتوحة واحدة لكل نقطة بيع
CREATE UNIQUE INDEX pos_shifts_open_ux ON pos_shifts (CASE WHEN status = 'OPEN' THEN terminal_id END);

CREATE TABLE pos_sales (
  sale_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shift_id          NUMBER         NOT NULL REFERENCES pos_shifts,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  sale_no           VARCHAR2(30)   NOT NULL,
  sale_type         VARCHAR2(10)   DEFAULT 'SALE' NOT NULL CHECK (sale_type IN ('SALE','RETURN')),
  sale_date         DATE           DEFAULT SYSDATE NOT NULL,
  customer_name     VARCHAR2(150),
  gross_amount      NUMBER(18,4)   DEFAULT 0 NOT NULL,               -- بالعملة الأساسية
  discount_amount   NUMBER(18,4)   DEFAULT 0 NOT NULL,
  net_amount        NUMBER(18,4)   DEFAULT 0 NOT NULL,
  paid_base         NUMBER(18,4)   DEFAULT 0 NOT NULL,
  change_base       NUMBER(18,4)   DEFAULT 0 NOT NULL,
  created_by        VARCHAR2(100),
  CONSTRAINT pos_sales_no_uk UNIQUE (company_id, sale_no)
);
CREATE INDEX pos_sales_shift_ix ON pos_sales (shift_id);

CREATE TABLE pos_sale_lines (
  line_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sale_id           NUMBER         NOT NULL REFERENCES pos_sales ON DELETE CASCADE,
  line_no           NUMBER         NOT NULL,
  item_id           NUMBER         NOT NULL,
  unit_id           NUMBER         NOT NULL,
  factor            NUMBER(18,6)   NOT NULL,
  qty               NUMBER(18,4)   NOT NULL CHECK (qty > 0),
  price             NUMBER(18,4)   NOT NULL,
  discount          NUMBER(18,4)   DEFAULT 0 NOT NULL,
  line_total        NUMBER(18,4)   NOT NULL,
  FOREIGN KEY (item_id, unit_id) REFERENCES item_units
);

CREATE TABLE pos_payments (                          -- الدفع بعملات متعددة وطرق متعددة
  payment_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sale_id           NUMBER         NOT NULL REFERENCES pos_sales ON DELETE CASCADE,
  pay_method        VARCHAR2(10)   NOT NULL CHECK (pay_method IN ('CASH','CARD')),
  currency_code     VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate     NUMBER(18,8)   NOT NULL,
  amount            NUMBER(18,4)   NOT NULL CHECK (amount > 0),
  amount_base       NUMBER(18,4)   NOT NULL
);

-- =====================================================================
-- 4) الموازنة التقديرية
-- =====================================================================
CREATE TABLE budgets (
  budget_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  fy_year           NUMBER(4)      NOT NULL,
  name_ar           VARCHAR2(150)  NOT NULL,
  status            VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL CHECK (status IN ('DRAFT','APPROVED')),
  created_by        VARCHAR2(100),
  approved_by       VARCHAR2(100),
  CONSTRAINT budgets_uk UNIQUE (company_id, fy_year)
);

CREATE TABLE budget_lines (
  bline_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  budget_id         NUMBER         NOT NULL REFERENCES budgets ON DELETE CASCADE,
  account_id        NUMBER         NOT NULL REFERENCES accounts,
  m01 NUMBER(18,2) DEFAULT 0, m02 NUMBER(18,2) DEFAULT 0, m03 NUMBER(18,2) DEFAULT 0,
  m04 NUMBER(18,2) DEFAULT 0, m05 NUMBER(18,2) DEFAULT 0, m06 NUMBER(18,2) DEFAULT 0,
  m07 NUMBER(18,2) DEFAULT 0, m08 NUMBER(18,2) DEFAULT 0, m09 NUMBER(18,2) DEFAULT 0,
  m10 NUMBER(18,2) DEFAULT 0, m11 NUMBER(18,2) DEFAULT 0, m12 NUMBER(18,2) DEFAULT 0,
  total             NUMBER(18,2) GENERATED ALWAYS AS
                    (NVL(m01,0)+NVL(m02,0)+NVL(m03,0)+NVL(m04,0)+NVL(m05,0)+NVL(m06,0)+
                     NVL(m07,0)+NVL(m08,0)+NVL(m09,0)+NVL(m10,0)+NVL(m11,0)+NVL(m12,0)) VIRTUAL,
  CONSTRAINT budget_lines_uk UNIQUE (budget_id, account_id)
);

-- =====================================================================
-- 5) حسابات وإعدادات إضافية
-- =====================================================================
DECLARE
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2, p_parent VARCHAR2) IS
  BEGIN
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature)
    SELECT p_code, p_name, account_id, acc_level + 1, acc_type, nature
    FROM   accounts WHERE account_code = p_parent
    AND    NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = p_code);
  END;
BEGIN
  acc('5101002', 'تكلفة البضاعة المباعة', '5101');
  acc('5101003', 'فروقات الجرد',          '5101');
  acc('2101002', 'مستحقات استلام بضاعة',  '2101');
  -- مستوى 3 جديد ثم حساب تحليلي لعجز وزيادة الصناديق
  INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature)
  SELECT '5202', 'مصروفات أخرى', account_id, 3, acc_type, nature FROM accounts
  WHERE account_code = '52' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '5202');
  acc('5202001', 'عجز وزيادة الصناديق', '5202');
END;
/

INSERT INTO account_settings (company_id, setting_code, account_id)
SELECT c.company_id, s.code, a.account_id
FROM   companies c
CROSS JOIN (SELECT 'INVENTORY' code, '1104001' acc FROM dual UNION ALL
            SELECT 'COGS'          , '5101002'     FROM dual UNION ALL
            SELECT 'INVENTORY_ADJ' , '5101003'     FROM dual UNION ALL
            SELECT 'POS_SALES'     , '4101002'     FROM dual UNION ALL
            SELECT 'CASH_DIFF'     , '5202001'     FROM dual) s
JOIN   accounts a ON a.account_code = s.acc
WHERE  NOT EXISTS (SELECT 1 FROM account_settings x WHERE x.company_id = c.company_id AND x.setting_code = s.code);

-- الشركة الفرعية تسجّل البضاعة الواردة من الأم في حساب المخزون (جرد مستمر)
UPDATE account_settings s
SET    s.account_id = (SELECT account_id FROM accounts WHERE account_code = '1104001')
WHERE  s.setting_code = 'PURCHASES'
AND    s.company_id IN (SELECT company_id FROM companies WHERE is_parent = 'N');

COMMIT;
