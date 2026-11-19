-- =====================================================================
--  نظام مجموعة الشركات  -  Oracle Database 21c / Oracle APEX
--  01_tables.sql : إنشاء الجداول (بدون Packages - كل المنطق في صفحات APEX)
--  يُشغَّل داخل الـ Schema المرتبطة بـ Workspace الـ APEX
-- =====================================================================
SET DEFINE OFF

-- =====================================================================
-- 1) الإعدادات العامة
-- =====================================================================

CREATE TABLE currencies (
  currency_code   VARCHAR2(3)    PRIMARY KEY,
  name_ar         VARCHAR2(50)   NOT NULL,
  name_en         VARCHAR2(50),
  symbol          VARCHAR2(10),
  decimals        NUMBER(1)      DEFAULT 2 NOT NULL,
  is_base         CHAR(1)        DEFAULT 'N' NOT NULL CHECK (is_base IN ('Y','N')),
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);
-- عملة أساسية واحدة فقط
CREATE UNIQUE INDEX currencies_one_base_ux ON currencies (CASE WHEN is_base = 'Y' THEN 'Y' END);

CREATE TABLE exchange_rates (
  rate_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  currency_code   VARCHAR2(3)    NOT NULL REFERENCES currencies,
  rate_date       DATE           NOT NULL,
  rate            NUMBER(18,8)   NOT NULL CHECK (rate > 0),   -- قيمة 1 من العملة بالعملة الأساسية
  created_by      VARCHAR2(100)  DEFAULT COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER),
  created_on      DATE           DEFAULT SYSDATE,
  CONSTRAINT exchange_rates_uk UNIQUE (currency_code, rate_date)
);

CREATE TABLE companies (
  company_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_code      VARCHAR2(10)   NOT NULL UNIQUE,
  name_ar           VARCHAR2(150)  NOT NULL,
  name_en           VARCHAR2(150),
  parent_id         NUMBER         REFERENCES companies,      -- NULL = الشركة الأم
  is_parent         CHAR(1)        DEFAULT 'N' NOT NULL CHECK (is_parent IN ('Y','N')),
  price_list_id     NUMBER,                                    -- قائمة أسعار الصرف لها (FK لاحقاً)
  tax_no            VARCHAR2(50),
  phone             VARCHAR2(50),
  address           VARCHAR2(300),
  is_active         CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N')),
  CONSTRAINT companies_parent_ck CHECK (
     (is_parent = 'Y' AND parent_id IS NULL) OR (is_parent = 'N' AND parent_id IS NOT NULL))
);

CREATE TABLE fiscal_years (
  fy_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fy_year         NUMBER(4)      NOT NULL UNIQUE,
  start_date      DATE           NOT NULL,
  end_date        DATE           NOT NULL,
  is_closed       CHAR(1)        DEFAULT 'N' NOT NULL CHECK (is_closed IN ('Y','N')),
  CHECK (end_date > start_date)
);

CREATE TABLE app_users (
  user_name       VARCHAR2(100)  PRIMARY KEY,                  -- نفس اسم دخول APEX (UPPER)
  full_name       VARCHAR2(150)  NOT NULL,
  company_id      NUMBER         NOT NULL REFERENCES companies, -- الشركة الافتراضية
  user_role       VARCHAR2(20)   DEFAULT 'USER' NOT NULL
                  CHECK (user_role IN ('GM','ACCOUNTANT','HR','STORE','CASHIER','USER')),
  password_hash   VARCHAR2(64),                                 -- SHA256(USER_NAME || ':' || password)
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

CREATE TABLE user_companies (                                   -- الشركات المسموح للمستخدم رؤيتها
  user_name       VARCHAR2(100)  NOT NULL REFERENCES app_users,
  company_id      NUMBER         NOT NULL REFERENCES companies,
  PRIMARY KEY (user_name, company_id)
);

-- ترقيم المستندات لكل شركة / نوع / سنة
CREATE TABLE doc_sequences (
  company_id      NUMBER         NOT NULL REFERENCES companies,
  doc_type        VARCHAR2(10)   NOT NULL,     -- JV,RV,PV,REV,INV,RET,DED,DIFF,INC ...
  fy_year         NUMBER(4)      NOT NULL,
  last_no         NUMBER         DEFAULT 0 NOT NULL,
  PRIMARY KEY (company_id, doc_type, fy_year)
);

-- =====================================================================
-- 2) الحسابات العامة
-- =====================================================================

-- شجرة الحسابات: أربع مستويات
--   المستوى 1 : رئيسي    (رقم 1 خانة)      مثال 1      الأصول
--   المستوى 2 : عام      (رقم 2 خانة)      مثال 11     الأصول المتداولة
--   المستوى 3 : مساعد    (رقم 4 خانات)     مثال 1101   النقدية
--   المستوى 4 : تحليلي   (رقم 7 خانات)     مثال 1101001 الصندوق الرئيسي   <-- الوحيد الذي تُسجَّل عليه القيود
CREATE TABLE accounts (
  account_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_code    VARCHAR2(20)   NOT NULL UNIQUE,
  name_ar         VARCHAR2(150)  NOT NULL,
  name_en         VARCHAR2(150),
  parent_id       NUMBER         REFERENCES accounts,
  acc_level       NUMBER(1)      NOT NULL CHECK (acc_level BETWEEN 1 AND 4),
  acc_type        VARCHAR2(10)   NOT NULL
                  CHECK (acc_type IN ('ASSET','LIAB','EQUITY','REV','EXP')),
  nature          CHAR(1)        NOT NULL CHECK (nature IN ('D','C')),   -- طبيعة الحساب مدين/دائن
  cash_bank       CHAR(1)        DEFAULT 'N' NOT NULL CHECK (cash_bank IN ('N','C','B')), -- صندوق/بنك
  currency_code   VARCHAR2(3)    REFERENCES currencies,       -- عملة الحساب (اختياري)
  company_id      NUMBER         REFERENCES companies,        -- NULL = مشترك لكل الشركات
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N')),
  is_postable     CHAR(1)        GENERATED ALWAYS AS (CASE WHEN acc_level = 4 THEN 'Y' ELSE 'N' END) VIRTUAL,
  CONSTRAINT accounts_parent_ck CHECK (
     (acc_level = 1 AND parent_id IS NULL) OR (acc_level > 1 AND parent_id IS NOT NULL)),
  CONSTRAINT accounts_cash_ck CHECK (cash_bank = 'N' OR acc_level = 4)
);
CREATE INDEX accounts_parent_ix ON accounts (parent_id);

-- أنواع القيود
CREATE TABLE journal_types (
  jt_code         VARCHAR2(10)   PRIMARY KEY,   -- JV قيد يومية, RV قبض, PV صرف, INV فاتورة ...
  name_ar         VARCHAR2(100)  NOT NULL,
  name_en         VARCHAR2(100),
  prefix          VARCHAR2(10)   NOT NULL,      -- بادئة رقم القيد
  manual_allowed  CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (manual_allowed IN ('Y','N')), -- يظهر في شاشة القيد اليدوي
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N')),
  sort_order      NUMBER         DEFAULT 0
);

CREATE TABLE journals (
  journal_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  jt_code           VARCHAR2(10)   NOT NULL REFERENCES journal_types,
  journal_no        VARCHAR2(30)   NOT NULL,
  journal_date      DATE           NOT NULL,
  currency_code     VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate     NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  description       VARCHAR2(500),
  ref_no            VARCHAR2(50),                -- رقم مرجعي خارجي
  status            VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL
                    CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  source_type       VARCHAR2(10)   DEFAULT 'MANUAL' NOT NULL
                    CHECK (source_type IN ('MANUAL','VOUCHER','INVOICE','PAYROLL','REVERSAL','OPENING')),
  source_id         NUMBER,
  reversal_of_id    NUMBER         REFERENCES journals,   -- هذا القيد عكسٌ لقيد آخر
  reversed_by_id    NUMBER         REFERENCES journals,   -- هذا القيد تم عكسه بقيد آخر
  reverse_reason    VARCHAR2(500),
  total_debit       NUMBER(18,4)   DEFAULT 0 NOT NULL,
  total_credit      NUMBER(18,4)   DEFAULT 0 NOT NULL,
  created_by        VARCHAR2(100),
  created_on        DATE           DEFAULT SYSDATE,
  posted_by         VARCHAR2(100),
  posted_on         DATE,
  CONSTRAINT journals_no_uk UNIQUE (company_id, jt_code, journal_no)
);
CREATE INDEX journals_date_ix   ON journals (company_id, journal_date);
CREATE INDEX journals_source_ix ON journals (source_type, source_id);

CREATE TABLE journal_lines (
  line_id             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  journal_id          NUMBER         NOT NULL REFERENCES journals ON DELETE CASCADE,
  line_no             NUMBER         NOT NULL,
  account_id          NUMBER         NOT NULL REFERENCES accounts,
  debit               NUMBER(18,4)   DEFAULT 0 NOT NULL CHECK (debit  >= 0),
  credit              NUMBER(18,4)   DEFAULT 0 NOT NULL CHECK (credit >= 0),
  debit_base          NUMBER(18,4)   DEFAULT 0 NOT NULL,   -- بالعملة الأساسية
  credit_base         NUMBER(18,4)   DEFAULT 0 NOT NULL,
  partner_company_id  NUMBER         REFERENCES companies, -- للمعاملات البينية (تُستبعد في الدمج)
  employee_id         NUMBER,                              -- تحليل اختياري (FK بعد إنشاء employees)
  description         VARCHAR2(500),
  CONSTRAINT journal_lines_amt_ck CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);
CREATE INDEX journal_lines_jr_ix  ON journal_lines (journal_id);
CREATE INDEX journal_lines_acc_ix ON journal_lines (account_id);

-- الحسابات الافتراضية لكل شركة (تُستخدم في القيود الآلية)
CREATE TABLE account_settings (
  company_id      NUMBER         NOT NULL REFERENCES companies,
  setting_code    VARCHAR2(30)   NOT NULL,
     -- SALES          إيرادات المبيعات للشركات الفرعية (عند الأم)
     -- SALES_RETURN   مردودات المبيعات (عند الأم)
     -- INTERCO_AR     ذمم الشركات الفرعية (عند الأم)      - يُحدد لكل فرعية في companies_accounts
     -- INTERCO_AP     ذمم دائنة للشركة الأم (عند الفرعية)
     -- PURCHASES      مشتريات/مخزون وارد من الأم (عند الفرعية)
     -- SALARY_EXP     مصروف الرواتب
     -- INCENTIVE_EXP  مصروف الحوافز
     -- SALARY_PAYABLE رواتب مستحقة
     -- DEDUCTIONS     إيرادات/استقطاعات خصومات الموظفين
  account_id      NUMBER         NOT NULL REFERENCES accounts,
  PRIMARY KEY (company_id, setting_code)
);

-- حساب ذمة كل شركة فرعية في دفاتر الأم
CREATE TABLE company_accounts (
  company_id        NUMBER  PRIMARY KEY REFERENCES companies,  -- الشركة الفرعية
  ar_account_id     NUMBER  NOT NULL REFERENCES accounts       -- حسابها كعميل لدى الأم
);

-- =====================================================================
-- 3) سندات القبض والصرف
-- =====================================================================
CREATE TABLE vouchers (
  voucher_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        NUMBER         NOT NULL REFERENCES companies,
  voucher_type      CHAR(1)        NOT NULL CHECK (voucher_type IN ('R','P')),  -- R قبض / P صرف
  voucher_no        VARCHAR2(30)   NOT NULL,
  voucher_date      DATE           NOT NULL,
  cash_account_id   NUMBER         NOT NULL REFERENCES accounts,   -- الصندوق أو البنك
  currency_code     VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate     NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  pay_method        VARCHAR2(10)   DEFAULT 'CASH' NOT NULL
                    CHECK (pay_method IN ('CASH','CHEQUE','TRANSFER')),
  cheque_no         VARCHAR2(30),
  cheque_date       DATE,
  bank_name         VARCHAR2(100),
  party_name        VARCHAR2(150),        -- استلمنا من / صرفنا إلى
  description       VARCHAR2(500),
  total_amount      NUMBER(18,4)   DEFAULT 0 NOT NULL,
  status            VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL
                    CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  journal_id        NUMBER         REFERENCES journals,
  created_by        VARCHAR2(100),
  created_on        DATE           DEFAULT SYSDATE,
  CONSTRAINT vouchers_no_uk UNIQUE (company_id, voucher_type, voucher_no)
);

CREATE TABLE voucher_lines (
  line_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  voucher_id        NUMBER         NOT NULL REFERENCES vouchers ON DELETE CASCADE,
  line_no           NUMBER         NOT NULL,
  account_id        NUMBER         NOT NULL REFERENCES accounts,   -- الحساب المقابل
  amount            NUMBER(18,4)   NOT NULL CHECK (amount > 0),
  partner_company_id NUMBER        REFERENCES companies,
  description       VARCHAR2(500)
);
CREATE INDEX voucher_lines_v_ix ON voucher_lines (voucher_id);

-- =====================================================================
-- 4) الأصناف والوحدات وقوائم الأسعار (اللازمة للفواتير)
-- =====================================================================
CREATE TABLE units (
  unit_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name_ar         VARCHAR2(50)   NOT NULL UNIQUE,
  name_en         VARCHAR2(50)
);

CREATE TABLE items (
  item_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_code       VARCHAR2(30)   NOT NULL UNIQUE,
  name_ar         VARCHAR2(200)  NOT NULL,
  name_en         VARCHAR2(200),
  base_unit_id    NUMBER         NOT NULL REFERENCES units,      -- أصغر وحدة
  barcode         VARCHAR2(50),
  reorder_level   NUMBER(18,4)   DEFAULT 0,
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

CREATE TABLE item_units (                 -- وحدات متعددة: كرتون = 24 حبة ...
  item_id         NUMBER         NOT NULL REFERENCES items ON DELETE CASCADE,
  unit_id         NUMBER         NOT NULL REFERENCES units,
  factor          NUMBER(18,6)   NOT NULL CHECK (factor > 0),   -- عدد الوحدات الأساسية
  barcode         VARCHAR2(50),
  PRIMARY KEY (item_id, unit_id)
);

CREATE TABLE warehouses (
  warehouse_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      NUMBER         NOT NULL REFERENCES companies,
  name_ar         VARCHAR2(100)  NOT NULL,
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

CREATE TABLE price_lists (
  price_list_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name_ar         VARCHAR2(100)  NOT NULL,
  currency_code   VARCHAR2(3)    NOT NULL REFERENCES currencies,
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

CREATE TABLE price_list_items (
  price_list_id   NUMBER         NOT NULL REFERENCES price_lists ON DELETE CASCADE,
  item_id         NUMBER         NOT NULL,
  unit_id         NUMBER         NOT NULL,
  price           NUMBER(18,4)   NOT NULL CHECK (price >= 0),
  PRIMARY KEY (price_list_id, item_id, unit_id),
  FOREIGN KEY (item_id, unit_id) REFERENCES item_units
);

ALTER TABLE companies ADD CONSTRAINT companies_pl_fk
  FOREIGN KEY (price_list_id) REFERENCES price_lists;

-- =====================================================================
-- 5) فواتير الصرف للشركات الفرعية (بيع من الأم) والمرتجعات
-- =====================================================================
CREATE TABLE invoices (
  invoice_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id          NUMBER         NOT NULL REFERENCES companies,  -- البائع (الأم)
  customer_company_id NUMBER         NOT NULL REFERENCES companies,  -- الشركة الفرعية
  invoice_type        VARCHAR2(10)   DEFAULT 'SALE' NOT NULL CHECK (invoice_type IN ('SALE','RETURN')),
  invoice_no          VARCHAR2(30)   NOT NULL,
  invoice_date        DATE           NOT NULL,
  warehouse_id        NUMBER         NOT NULL REFERENCES warehouses,
  price_list_id       NUMBER         NOT NULL REFERENCES price_lists,
  currency_code       VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate       NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  gross_amount        NUMBER(18,4)   DEFAULT 0 NOT NULL,
  discount_amount     NUMBER(18,4)   DEFAULT 0 NOT NULL,
  net_amount          NUMBER(18,4)   DEFAULT 0 NOT NULL,
  description         VARCHAR2(500),
  status              VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL
                      CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  journal_id          NUMBER         REFERENCES journals,   -- قيد الأم
  sub_journal_id      NUMBER         REFERENCES journals,   -- القيد المقابل في دفاتر الفرعية
  created_by          VARCHAR2(100),
  created_on          DATE           DEFAULT SYSDATE,
  CONSTRAINT invoices_no_uk UNIQUE (company_id, invoice_type, invoice_no)
);

CREATE TABLE invoice_lines (
  line_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id      NUMBER         NOT NULL REFERENCES invoices ON DELETE CASCADE,
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
CREATE INDEX invoice_lines_inv_ix ON invoice_lines (invoice_id);

-- =====================================================================
-- 6) الموظفين والدرجات والعلاوات
-- =====================================================================
CREATE TABLE job_grades (
  grade_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grade_code      VARCHAR2(10)   NOT NULL UNIQUE,
  name_ar         VARCHAR2(100)  NOT NULL,
  basic_salary    NUMBER(18,4)   NOT NULL,
  currency_code   VARCHAR2(3)    NOT NULL REFERENCES currencies
);

CREATE TABLE employees (
  employee_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  emp_no          VARCHAR2(20)   NOT NULL UNIQUE,
  name_ar         VARCHAR2(150)  NOT NULL,
  company_id      NUMBER         NOT NULL REFERENCES companies,   -- الشركة التي يُحمَّل عليها راتبه
  grade_id        NUMBER         NOT NULL REFERENCES job_grades,
  hire_date       DATE,
  basic_salary    NUMBER(18,4),                                    -- NULL = أساسي الدرجة
  bank_account    VARCHAR2(50),
  is_active       CHAR(1)        DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
);

ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_emp_fk
  FOREIGN KEY (employee_id) REFERENCES employees;

CREATE TABLE allowance_types (
  allowance_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code            VARCHAR2(20)   NOT NULL UNIQUE,
  name_ar         VARCHAR2(100)  NOT NULL,
  kind            VARCHAR2(10)   NOT NULL CHECK (kind IN ('ALLOWANCE','INCENTIVE','DEDUCTION')),
  calc_method     VARCHAR2(10)   DEFAULT 'FIXED' NOT NULL CHECK (calc_method IN ('FIXED','PERCENT')),
  account_id      NUMBER         REFERENCES accounts
);

CREATE TABLE grade_allowances (       -- الافتراضي حسب الدرجة
  grade_id        NUMBER         NOT NULL REFERENCES job_grades,
  allowance_id    NUMBER         NOT NULL REFERENCES allowance_types,
  value           NUMBER(18,4)   NOT NULL,
  PRIMARY KEY (grade_id, allowance_id)
);

CREATE TABLE emp_allowances (         -- خاص بالموظف ويغلب على الدرجة
  employee_id     NUMBER         NOT NULL REFERENCES employees,
  allowance_id    NUMBER         NOT NULL REFERENCES allowance_types,
  value           NUMBER(18,4)   NOT NULL,
  from_date       DATE,
  to_date         DATE,
  PRIMARY KEY (employee_id, allowance_id)
);

-- =====================================================================
-- 7) شاشة الخصم / فرق المبلغ / الحافز
-- =====================================================================
CREATE TABLE payroll_adj (
  adj_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adj_type        VARCHAR2(5)    NOT NULL CHECK (adj_type IN ('DED','DIFF','INC')),
                  -- DED خصم , DIFF فرق مبلغ (+/-) , INC حافز
  adj_no          VARCHAR2(30)   NOT NULL,
  adj_date        DATE           NOT NULL,
  pay_period      VARCHAR2(6)    NOT NULL,          -- YYYYMM شهر الراتب الذي يُطبَّق عليه
  allowance_id    NUMBER         REFERENCES allowance_types,  -- نوع البند (اختياري)
  currency_code   VARCHAR2(3)    NOT NULL REFERENCES currencies,
  exchange_rate   NUMBER(18,8)   NOT NULL CHECK (exchange_rate > 0),
  reason          VARCHAR2(500),
  total_amount    NUMBER(18,4)   DEFAULT 0 NOT NULL,
  status          VARCHAR2(10)   DEFAULT 'DRAFT' NOT NULL
                  CHECK (status IN ('DRAFT','APPROVED','APPLIED','CANCELLED')),
  applied_run_id  NUMBER,                            -- مسير الرواتب (مرحلة الرواتب)
  created_by      VARCHAR2(100),
  created_on      DATE           DEFAULT SYSDATE,
  approved_by     VARCHAR2(100),
  approved_on     DATE,
  CONSTRAINT payroll_adj_no_uk UNIQUE (adj_type, adj_no),
  CONSTRAINT payroll_adj_period_ck CHECK (REGEXP_LIKE(pay_period, '^[0-9]{4}(0[1-9]|1[0-2])$'))
);

CREATE TABLE payroll_adj_lines (
  line_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adj_id          NUMBER         NOT NULL REFERENCES payroll_adj ON DELETE CASCADE,
  line_no         NUMBER         NOT NULL,
  employee_id     NUMBER         NOT NULL REFERENCES employees,
  company_id      NUMBER         NOT NULL REFERENCES companies,  -- شركة الموظف وقت الحركة
  direction       CHAR(1)        DEFAULT '+' NOT NULL CHECK (direction IN ('+','-')),
                  -- الخصم دائماً '-' والحافز '+' وفرق المبلغ حسب الحالة
  amount          NUMBER(18,4)   NOT NULL CHECK (amount > 0),
  notes           VARCHAR2(300)
);
CREATE INDEX payroll_adj_lines_ix ON payroll_adj_lines (adj_id);
CREATE INDEX payroll_adj_emp_ix   ON payroll_adj_lines (employee_id);

-- =====================================================================
-- 8) View مساعد: آخر سعر صرف لكل عملة (للاستعلامات في الصفحات)
-- =====================================================================
CREATE OR REPLACE VIEW v_latest_rates AS
SELECT c.currency_code,
       CASE WHEN c.is_base = 'Y' THEN 1
            ELSE (SELECT r.rate FROM exchange_rates r
                  WHERE r.currency_code = c.currency_code
                  ORDER BY r.rate_date DESC FETCH FIRST 1 ROW ONLY) END AS rate
FROM   currencies c;

-- شجرة الحسابات مع المسار الكامل
CREATE OR REPLACE VIEW v_accounts_tree AS
SELECT a.account_id, a.account_code, a.name_ar, a.parent_id, a.acc_level,
       a.acc_type, a.nature, a.cash_bank, a.is_postable, a.is_active, a.company_id,
       SYS_CONNECT_BY_PATH(a.name_ar, ' / ') AS full_path
FROM   accounts a
START WITH a.parent_id IS NULL
CONNECT BY PRIOR a.account_id = a.parent_id;
