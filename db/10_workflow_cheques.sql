-- =====================================================================
--  10_workflow_cheques.sql
--  * الأدوار: مدير النظام / مدخل / مراجع / معتمد
--  * دورة المستند: مسودة -> مُراجَع -> معتمد -> مرحّل (+ معاد للمدخل)
--  * الأذونات النقدية (حساب مقابل + مبلغ في الرأس) وأذونات الشيكات
--  * جدول الشيكات وإعدادات طباعة الشيك لكل بنك
--  * تسمية الصندوق بالخزينة
--  يُشغّل مرة واحدة بعد 01..09 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  -- حذف قيود CHECK القديمة على عمود معيّن قبل إعادة تعريفها
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
  PROCEDURE add_col (p_table VARCHAR2, p_col VARCHAR2, p_def VARCHAR2) IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = UPPER(p_table) AND column_name = UPPER(p_col);
    IF l_cnt = 0 THEN EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table || ' ADD (' || p_col || ' ' || p_def || ')'; END IF;
  END;
BEGIN
  ------------------------------------------------------------------ الأدوار
  drop_checks('APP_USERS', 'USER_ROLE');
  UPDATE app_users SET user_role = CASE user_role WHEN 'GM' THEN 'ADMIN' ELSE 'ENTRY' END
  WHERE  user_role NOT IN ('ADMIN','ENTRY','REVIEWER','APPROVER');
  EXECUTE IMMEDIATE 'ALTER TABLE app_users MODIFY (user_role DEFAULT ''ENTRY'')';
  EXECUTE IMMEDIATE q'[ALTER TABLE app_users ADD CONSTRAINT app_users_role_ck
                       CHECK (user_role IN ('ADMIN','ENTRY','REVIEWER','APPROVER'))]';

  ------------------------------------------------------------------ حالات المستندات + حقول المراجعة والاعتماد
  FOR t IN (SELECT 'JOURNALS' tn FROM dual UNION ALL SELECT 'VOUCHERS' FROM dual UNION ALL SELECT 'PAYROLL_ADJ' FROM dual) LOOP
    drop_checks(t.tn, 'STATUS');
    add_col(t.tn, 'reviewed_by', 'VARCHAR2(100)');
    add_col(t.tn, 'reviewed_on', 'DATE');
    add_col(t.tn, 'approved_by', 'VARCHAR2(100)');
    add_col(t.tn, 'approved_on', 'DATE');
    add_col(t.tn, 'return_note', 'VARCHAR2(500)');
  END LOOP;
  EXECUTE IMMEDIATE q'[ALTER TABLE journals ADD CONSTRAINT journals_status_ck
      CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','POSTED','REVERSED'))]';
  EXECUTE IMMEDIATE q'[ALTER TABLE vouchers ADD CONSTRAINT vouchers_status_ck
      CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','POSTED','REVERSED'))]';
  EXECUTE IMMEDIATE q'[ALTER TABLE payroll_adj ADD CONSTRAINT payroll_adj_status_ck
      CHECK (status IN ('DRAFT','RETURNED','REVIEWED','APPROVED','APPLIED','CANCELLED'))]';

  drop_checks('JOURNALS', 'SOURCE_TYPE');
  EXECUTE IMMEDIATE q'[ALTER TABLE journals ADD CONSTRAINT journals_source_ck
      CHECK (source_type IN ('MANUAL','VOUCHER','INVOICE','PAYROLL','REVERSAL','OPENING','PURCHASE','CHEQUE'))]';

  ------------------------------------------------------------------ الأذونات: نقدي / شيكات
  add_col('VOUCHERS', 'voucher_kind', q'[VARCHAR2(10) DEFAULT 'CASH' NOT NULL]');
  add_col('VOUCHERS', 'counter_account_id', 'NUMBER REFERENCES accounts');
  drop_checks('VOUCHERS', 'VOUCHER_KIND');
  EXECUTE IMMEDIATE q'[ALTER TABLE vouchers ADD CONSTRAINT vouchers_kind_ck CHECK (voucher_kind IN ('CASH','CHEQUE'))]';
  -- إذن الشيكات لا يحتاج خزينة (الحساب الوسيط من الإعدادات)
  EXECUTE IMMEDIATE 'ALTER TABLE vouchers MODIFY (cash_account_id NULL)';
END;
/

-- سجل إجراءات المستندات (من راجع / اعتمد / أعاد / رحّل ومتى)
DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'DOC_ACTIONS';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE doc_actions (
  action_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  doc_type    VARCHAR2(20)  NOT NULL,       -- JOURNAL / VOUCHER / PAYADJ
  doc_id      NUMBER        NOT NULL,
  action      VARCHAR2(20)  NOT NULL,       -- SAVE / REVIEW / UNREVIEW / APPROVE / UNAPPROVE / RETURN / POST
  from_status VARCHAR2(10),
  to_status   VARCHAR2(10),
  note        VARCHAR2(500),
  action_by   VARCHAR2(100) NOT NULL,
  action_on   DATE DEFAULT SYSDATE NOT NULL
)]';
    EXECUTE IMMEDIATE 'CREATE INDEX doc_actions_doc_ix ON doc_actions (doc_type, doc_id)';
  END IF;

  -- الشيكات: كل شيك سطر مستقل بحالة خاصة
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'CHEQUES';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE cheques (
  cheque_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  voucher_id       NUMBER        NOT NULL REFERENCES vouchers ON DELETE CASCADE,
  line_no          NUMBER        NOT NULL,
  cheque_no        VARCHAR2(30)  NOT NULL,
  bank_account_id  NUMBER        REFERENCES accounts,    -- صرف: حساب بنكنا المسحوب عليه
  bank_name        VARCHAR2(100),                         -- توريد: بنك الساحب
  due_date         DATE          NOT NULL,                -- تاريخ الاستحقاق (الصرف)
  amount           NUMBER(18,4)  NOT NULL CHECK (amount > 0),
  payee_name       VARCHAR2(150),                         -- المستفيد (يُطبع على الشيك)
  status           VARCHAR2(10)  DEFAULT 'PENDING' NOT NULL
                   CHECK (status IN ('PENDING','CLEARED','BOUNCED')),
  settle_date      DATE,
  settle_bank_id   NUMBER        REFERENCES accounts,     -- توريد: البنك الذي حُصّل فيه
  settle_journal_id NUMBER       REFERENCES journals,
  settled_by       VARCHAR2(100),
  print_count      NUMBER        DEFAULT 0 NOT NULL
)]';
    EXECUTE IMMEDIATE 'CREATE INDEX cheques_due_ix ON cheques (status, due_date)';
    EXECUTE IMMEDIATE 'CREATE INDEX cheques_voucher_ix ON cheques (voucher_id)';
  END IF;

  -- مواضع حقول الشيك لكل بنك (بالمليمتر من أعلى يمين الشيك)
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'CHEQUE_LAYOUTS';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE cheque_layouts (
  layout_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bank_account_id  NUMBER        UNIQUE REFERENCES accounts,   -- NULL = المقاس الافتراضي
  layout_name      VARCHAR2(100) NOT NULL,
  width_mm         NUMBER DEFAULT 175 NOT NULL,
  height_mm        NUMBER DEFAULT 80  NOT NULL,
  date_top         NUMBER DEFAULT 10  NOT NULL, date_right   NUMBER DEFAULT 125 NOT NULL,
  payee_top        NUMBER DEFAULT 25  NOT NULL, payee_right  NUMBER DEFAULT 25  NOT NULL,
  words_top        NUMBER DEFAULT 35  NOT NULL, words_right  NUMBER DEFAULT 25  NOT NULL, words_width NUMBER DEFAULT 110 NOT NULL,
  amount_top       NUMBER DEFAULT 35  NOT NULL, amount_right NUMBER DEFAULT 140 NOT NULL,
  font_size        NUMBER DEFAULT 13  NOT NULL
)]';
    EXECUTE IMMEDIATE q'[INSERT INTO cheque_layouts (bank_account_id, layout_name) VALUES (NULL, 'المقاس الافتراضي')]';
  END IF;
END;
/

-- أنواع قيود الشيكات
MERGE INTO journal_types t
USING (SELECT 'CR' c, 'إذن توريد شيكات' n, 'Cheque Receipt' e, 12 s FROM dual UNION ALL
       SELECT 'CP', 'إذن صرف شيكات', 'Cheque Payment', 13 FROM dual UNION ALL
       SELECT 'CQ', 'تسوية شيكات (صرف / تحصيل / ارتداد)', 'Cheque Settlement', 14 FROM dual) s
ON (t.jt_code = s.c)
WHEN NOT MATCHED THEN INSERT (jt_code, name_ar, name_en, prefix, manual_allowed, sort_order)
VALUES (s.c, s.n, s.e, s.c, 'N', s.s);

UPDATE journal_types SET name_ar = 'إذن توريد نقدي' WHERE jt_code = 'RV';
UPDATE journal_types SET name_ar = 'إذن صرف نقدي'   WHERE jt_code = 'PV';

-- الحسابات الوسيطة للشيكات + ربطها بالإعدادات
DECLARE
  l_parent NUMBER; l_id NUMBER; l_cnt NUMBER; l_co NUMBER;
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2, p_parent VARCHAR2) IS
    l_p accounts%ROWTYPE;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_code = p_code;
    IF l_cnt = 0 THEN
      SELECT * INTO l_p FROM accounts WHERE account_code = p_parent;
      INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature)
      VALUES (p_code, p_name, l_p.account_id, l_p.acc_level + 1, l_p.acc_type, l_p.nature);
    END IF;
  END;
BEGIN
  acc('1107',    'شيكات تحت التحصيل', '11');
  acc('1107001', 'شيكات تحت التحصيل', '1107');
  acc('2104',    'شيكات تحت الصرف', '21');
  acc('2104001', 'شيكات تحت الصرف', '2104');

  SELECT company_id INTO l_co FROM companies WHERE is_parent = 'Y' AND ROWNUM = 1;
  MERGE INTO account_settings s
  USING (SELECT 'CHEQUES_IN' c, (SELECT account_id FROM accounts WHERE account_code = '1107001') a FROM dual UNION ALL
         SELECT 'CHEQUES_OUT',  (SELECT account_id FROM accounts WHERE account_code = '2104001') FROM dual) x
  ON (s.company_id = l_co AND s.setting_code = x.c)
  WHEN NOT MATCHED THEN INSERT (company_id, setting_code, account_id) VALUES (l_co, x.c, x.a);
END;
/

-- الصندوق -> الخزينة
UPDATE accounts SET name_ar = REPLACE(REPLACE(name_ar, 'الصناديق', 'الخزائن'), 'الصندوق', 'الخزينة')
WHERE  name_ar LIKE '%الصندوق%' OR name_ar LIKE '%الصناديق%';
UPDATE accounts SET name_ar = REPLACE(name_ar, 'صندوق', 'خزينة') WHERE name_ar LIKE '%صندوق%';

COMMIT;
UPDATE accounts SET name_ar = REPLACE(name_ar, 'الخزينة الرئيسي', 'الخزينة الرئيسية') WHERE name_ar = 'الخزينة الرئيسي';
COMMIT;
