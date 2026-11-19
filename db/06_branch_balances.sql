-- =====================================================================
--  06_branch_balances.sql : بنود ميزانية الفروع (إدخال يدوي) لدمجها مع ميزانية الشركة الأم
--  الفروع لها نظامها الخاص، ويُدخل هنا رصيد كل حساب في تاريخ معيّن (بالعملة الأساسية)
-- =====================================================================
CREATE TABLE branch_balances (
  bal_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    NUMBER         NOT NULL REFERENCES companies,      -- الفرع
  as_of_date    DATE           NOT NULL,                           -- تاريخ الميزانية
  account_id    NUMBER         NOT NULL REFERENCES accounts,       -- الحساب (المستوى 4)
  debit         NUMBER(18,2)   DEFAULT 0 NOT NULL CHECK (debit  >= 0),
  credit        NUMBER(18,2)   DEFAULT 0 NOT NULL CHECK (credit >= 0),
  notes         VARCHAR2(300),
  entered_by    VARCHAR2(100),
  entered_on    DATE           DEFAULT SYSDATE,
  CONSTRAINT branch_balances_uk UNIQUE (company_id, as_of_date, account_id)
);
CREATE INDEX branch_balances_ix ON branch_balances (company_id, as_of_date);
