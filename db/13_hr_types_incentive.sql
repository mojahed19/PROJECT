-- =====================================================================
--  13_hr_types_incentive.sql
--  * أنواع الموظفين: موظف / عامل / عسكري / ضابط ، ورتب العسكريين والضباط
--  * الحافز السنوي = النسبة × المرتبات المصروفة خلال السنة (مسيرات معتمدة)
--  يُشغّل مرة واحدة بعد 12 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
  PROCEDURE add_col (p_table VARCHAR2, p_col VARCHAR2, p_def VARCHAR2) IS
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = UPPER(p_table) AND column_name = UPPER(p_col);
    IF l_cnt = 0 THEN EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table || ' ADD (' || p_col || ' ' || p_def || ')'; END IF;
  END;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'MILITARY_RANKS';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE military_ranks (
  rank_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rank_type   VARCHAR2(10)  NOT NULL CHECK (rank_type IN ('SOLDIER','OFFICER')),   -- عسكري / ضابط
  name_ar     VARCHAR2(100) NOT NULL,
  sort_order  NUMBER        DEFAULT 0 NOT NULL,
  CONSTRAINT military_ranks_uk UNIQUE (rank_type, name_ar)
)]';
  END IF;

  add_col('EMPLOYEES', 'emp_type', q'[VARCHAR2(10) DEFAULT 'EMPLOYEE' NOT NULL]');
  add_col('EMPLOYEES', 'rank_id',  'NUMBER REFERENCES military_ranks');
  SELECT COUNT(*) INTO l_cnt FROM user_constraints WHERE constraint_name = 'EMPLOYEES_TYPE_CK';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[ALTER TABLE employees ADD CONSTRAINT employees_type_ck
        CHECK (emp_type IN ('EMPLOYEE','WORKER','SOLDIER','OFFICER'))]';
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'ANNUAL_INCENTIVES';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE annual_incentives (
  inc_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id   NUMBER        NOT NULL REFERENCES companies,
  inc_no       VARCHAR2(20)  NOT NULL UNIQUE,                 -- 18 + السنة + 5 خانات
  fy_year      NUMBER(4)     NOT NULL,
  percent      NUMBER(9,4)   NOT NULL CHECK (percent > 0),
  basis        VARCHAR2(10)  DEFAULT 'BASIC' NOT NULL CHECK (basis IN ('BASIC','GROSS')),  -- الأساسي / إجمالي الاستحقاقات
  emp_type     VARCHAR2(10),                                  -- NULL = كل الأنواع
  description  VARCHAR2(500),
  total_amount NUMBER(18,4)  DEFAULT 0 NOT NULL,
  status       VARCHAR2(10)  DEFAULT 'DRAFT' NOT NULL
               CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','POSTED','REVERSED')),
  journal_id   NUMBER        REFERENCES journals,
  created_by   VARCHAR2(100), created_on DATE DEFAULT SYSDATE,
  reviewed_by  VARCHAR2(100), reviewed_on DATE,
  approved_by  VARCHAR2(100), approved_on DATE,
  return_note  VARCHAR2(500)
)]';
    EXECUTE IMMEDIATE q'[
CREATE TABLE annual_incentive_lines (
  line_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  inc_id         NUMBER       NOT NULL REFERENCES annual_incentives ON DELETE CASCADE,
  employee_id    NUMBER       NOT NULL REFERENCES employees,
  months_paid    NUMBER(3)    NOT NULL,
  salaries_paid  NUMBER(18,4) NOT NULL,
  amount         NUMBER(18,4) NOT NULL,
  CONSTRAINT annual_inc_lines_uk UNIQUE (inc_id, employee_id)
)]';
  END IF;
END;
/

-- رتب افتراضية (قابلة للتعديل من صفحة الرتب)
MERGE INTO military_ranks r
USING (SELECT 'SOLDIER' t, 'جندي' n, 1 s FROM dual UNION ALL SELECT 'SOLDIER', 'وكيل عريف', 2 FROM dual UNION ALL
       SELECT 'SOLDIER', 'عريف', 3 FROM dual UNION ALL SELECT 'SOLDIER', 'رقيب', 4 FROM dual UNION ALL
       SELECT 'SOLDIER', 'رقيب أول', 5 FROM dual UNION ALL SELECT 'SOLDIER', 'مساعد', 6 FROM dual UNION ALL
       SELECT 'OFFICER', 'ملازم', 1 FROM dual UNION ALL SELECT 'OFFICER', 'ملازم أول', 2 FROM dual UNION ALL
       SELECT 'OFFICER', 'نقيب', 3 FROM dual UNION ALL SELECT 'OFFICER', 'رائد', 4 FROM dual UNION ALL
       SELECT 'OFFICER', 'مقدم', 5 FROM dual UNION ALL SELECT 'OFFICER', 'عقيد', 6 FROM dual UNION ALL
       SELECT 'OFFICER', 'عميد', 7 FROM dual UNION ALL SELECT 'OFFICER', 'لواء', 8 FROM dual UNION ALL
       SELECT 'OFFICER', 'فريق', 9 FROM dual UNION ALL SELECT 'OFFICER', 'فريق أول', 10 FROM dual) s
ON (r.rank_type = s.t AND r.name_ar = s.n)
WHEN NOT MATCHED THEN INSERT (rank_type, name_ar, sort_order) VALUES (s.t, s.n, s.s);

MERGE INTO journal_types t
USING (SELECT 'AINC' c FROM dual) s ON (t.jt_code = s.c)
WHEN NOT MATCHED THEN INSERT (jt_code, name_ar, name_en, prefix, manual_allowed, sort_order)
VALUES ('AINC', 'الحافز السنوي', 'Annual Incentive', 'AINC', 'N', 31);

COMMIT;
