-- =====================================================================
--  14_budget_plan.sql
--  الخطة (الموازنة التقديرية) للإدارات بالأرباع الأربعة حسب بنود الميزانية ، ولكل بند رقم إيضاح
--  يُشغّل مرة واحدة بعد 13 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
  PROCEDURE mk (p_name VARCHAR2, p_ddl VARCHAR2) IS
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = UPPER(p_name);
    IF l_cnt = 0 THEN EXECUTE IMMEDIATE p_ddl; END IF;
  END;
BEGIN
  mk('DEPARTMENTS', q'[
CREATE TABLE departments (
  dept_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dept_code  VARCHAR2(20)  NOT NULL UNIQUE,
  name_ar    VARCHAR2(150) NOT NULL,
  is_active  CHAR(1)       DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
)]');

  mk('BUDGET_ITEMS', q'[
CREATE TABLE budget_items (
  bitem_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  note_no    VARCHAR2(20)  NOT NULL UNIQUE,                       -- رقم الإيضاح
  name_ar    VARCHAR2(200) NOT NULL,
  item_type  VARCHAR2(3)   DEFAULT 'EXP' NOT NULL CHECK (item_type IN ('REV','EXP')),   -- إيراد / مصروف
  account_id NUMBER        REFERENCES accounts,                   -- الحساب (وما تحته) لحساب الفعلي
  sort_order NUMBER        DEFAULT 0 NOT NULL,
  is_active  CHAR(1)       DEFAULT 'Y' NOT NULL CHECK (is_active IN ('Y','N'))
)]');

  mk('BUDGET_PLANS', q'[
CREATE TABLE budget_plans (
  plan_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  NUMBER        NOT NULL REFERENCES companies,
  fy_year     NUMBER(4)     NOT NULL,
  dept_id     NUMBER        NOT NULL REFERENCES departments,
  description VARCHAR2(500),
  status      VARCHAR2(10)  DEFAULT 'DRAFT' NOT NULL
              CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED')),
  created_by  VARCHAR2(100), created_on DATE DEFAULT SYSDATE,
  reviewed_by VARCHAR2(100), reviewed_on DATE,
  approved_by VARCHAR2(100), approved_on DATE,
  return_note VARCHAR2(500),
  CONSTRAINT budget_plans_uk UNIQUE (fy_year, dept_id)
)]');

  mk('BUDGET_PLAN_LINES', q'[
CREATE TABLE budget_plan_lines (
  pline_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plan_id   NUMBER       NOT NULL REFERENCES budget_plans ON DELETE CASCADE,
  bitem_id  NUMBER       NOT NULL REFERENCES budget_items,
  q1 NUMBER(18,2) DEFAULT 0 NOT NULL, q2 NUMBER(18,2) DEFAULT 0 NOT NULL,
  q3 NUMBER(18,2) DEFAULT 0 NOT NULL, q4 NUMBER(18,2) DEFAULT 0 NOT NULL,
  total     NUMBER(18,2) GENERATED ALWAYS AS (q1 + q2 + q3 + q4) VIRTUAL,
  notes     VARCHAR2(300),
  CONSTRAINT budget_plan_lines_uk UNIQUE (plan_id, bitem_id)
)]');
END;
/
COMMIT;
