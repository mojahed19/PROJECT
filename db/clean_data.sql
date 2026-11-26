-- =====================================================================
--  clean_data.sql  -  تنظيف بيانات التجربة قبل البدء الفعلي (ليس ضمن install_db.sql)
--
--  يبقى كما هو (بيانات النظام):
--    COMPANIES (المؤسسة فقط) ، APP_USERS (عدا TESTER) ، CURRENCIES ، EXCHANGE_RATES ،
--    FISCAL_YEARS ، JOURNAL_TYPES ، CHEQUE_LAYOUTS (بدون ربط ببنك)
--  يُفرَّغ:
--    المعاملات   : القيود ، الأذونات ، الشيكات ، الفواتير ، المشتريات ، حركات المخزون ، الورديات ،
--                  الرواتب والخصومات والحوافز ، الخطط والموازنات ، سجل المراجعة والاعتماد ، الإيضاحات ،
--                  الترقيم (يبدأ من 1)
--    الحسابات    : شجرة الحسابات ، الحسابات الافتراضية ، حسابات الشركات ، أرصدة الفروع
--    الأصناف     : الأصناف ووحداتها ، الوحدات ، المخازن ، قوائم الأسعار
--    الموظفون    : الموظفون ، الدرجات ، العلاوات ، أنواع العلاوات ، الرتب ، الإدارات ، بنود الميزانية
--  يُحذف (جداول لا تستخدمها أي صفحة): POS_* (6 جداول نقاط البيع) ، VOUCHER_LINES
--
--  الخطوة 1 تنسخ كل جدول فيه بيانات إلى BK_<الجدول> قبل أي حذف (للاسترجاع عند الحاجة) ،
--  وتُحذف النسخ لاحقاً يدوياً بعد التأكد: DROP TABLE BK_...
-- =====================================================================
SET DEFINE OFF

------------------------------------------------------------------ 1) النسخة الاحتياطية
DECLARE
  l_cnt NUMBER; l_rows NUMBER;
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name NOT LIKE 'BK\_%' ESCAPE '\' AND table_name NOT LIKE 'BIN$%' ORDER BY table_name) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM "' || t.table_name || '"' INTO l_rows;
    SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = SUBSTR('BK_' || t.table_name, 1, 128);
    IF l_rows > 0 AND l_cnt = 0 THEN
      EXECUTE IMMEDIATE 'CREATE TABLE "BK_' || t.table_name || '" AS SELECT * FROM "' || t.table_name || '"';
      DBMS_OUTPUT.PUT_LINE('BACKUP BK_' || t.table_name || ' ' || l_rows);
    END IF;
  END LOOP;
END;
/

------------------------------------------------------------------ 2) حذف الجداول غير المستخدمة (قبل التفريغ: POS_TERMINALS يشير للحسابات والمخازن)
DECLARE
  PROCEDURE drop_t (p VARCHAR2) IS l NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l FROM user_tables WHERE table_name = UPPER(p);
    IF l > 0 THEN EXECUTE IMMEDIATE 'DROP TABLE ' || p || ' CASCADE CONSTRAINTS PURGE'; DBMS_OUTPUT.PUT_LINE('DROPPED ' || p); END IF;
  END;
BEGIN
  drop_t('pos_payments');
  drop_t('pos_sale_lines');
  drop_t('pos_sales');
  drop_t('pos_shifts');
  drop_t('pos_terminal_users');
  drop_t('pos_terminals');
  drop_t('voucher_lines');
END;
/

------------------------------------------------------------------ 3) تفريغ البيانات (الأبناء قبل الآباء)
DECLARE
  l_hq NUMBER;
  PROCEDURE del (p_table VARCHAR2, p_where VARCHAR2 DEFAULT NULL) IS
  BEGIN
    EXECUTE IMMEDIATE 'DELETE FROM ' || p_table || CASE WHEN p_where IS NOT NULL THEN ' WHERE ' || p_where END;
    DBMS_OUTPUT.PUT_LINE('DELETED ' || p_table || ' ' || SQL%ROWCOUNT);
  END;
BEGIN
  SELECT company_id INTO l_hq FROM companies WHERE is_parent = 'Y';

  -- سجل المراجعة والإيضاحات
  del('doc_actions');
  del('fs_notes');
  -- الشيكات والفواتير والمشتريات والمخزون والورديات
  del('cheques');
  del('invoice_lines');
  del('invoices');
  del('purchase_invoice_lines');
  del('purchase_invoices');
  del('stock_trans_lines');
  del('stock_trans');
  del('sales_shifts');
  -- الرواتب والحوافز
  del('payroll_line_details');
  del('payroll_lines');
  del('payroll_run_journals');
  del('payroll_adj_lines');
  del('payroll_adj');
  del('payroll_runs');
  del('annual_incentive_lines');
  del('annual_incentives');
  -- الأذونات ثم القيود (فك روابط العكس أولاً)
  del('vouchers');
  del('journal_lines');
  EXECUTE IMMEDIATE 'UPDATE journals SET reversal_of_id = NULL, reversed_by_id = NULL';
  del('journals');
  -- الخطط والموازنات والإدارات
  del('budget_plan_lines');
  del('budget_plans');
  del('budget_lines');
  del('budgets');
  del('branch_balances');
  del('budget_items');
  del('departments');
  -- الموظفون
  del('emp_allowances');
  del('grade_allowances');
  del('employees');
  del('job_grades');
  del('allowance_types');
  del('military_ranks');
  -- الأصناف والمخازن وقوائم الأسعار
  EXECUTE IMMEDIATE 'UPDATE companies SET price_list_id = NULL, pos_price_list_id = NULL';
  del('price_list_items');
  del('price_lists');
  del('item_units');
  del('items');
  del('units');
  -- شجرة الحسابات وما يرتبط بها
  del('account_settings');
  del('company_accounts');
  EXECUTE IMMEDIATE 'UPDATE cheque_layouts SET bank_account_id = NULL';
  -- من المستوى 4 إلى 1 (القيد ACCOUNTS_PARENT_CK يمنع حساباً فرعياً بلا أب)
  del('accounts', 'acc_level = 4');
  del('accounts', 'acc_level = 3');
  del('accounts', 'acc_level = 2');
  del('accounts');
  -- الترقيم يبدأ من جديد
  del('doc_sequences');
  -- المستخدمون: ربطهم بالمؤسسة (حذف TESTER في الخطوة 5 بعد فحص التطبيق)
  del('user_companies');
  EXECUTE IMMEDIATE 'UPDATE app_users SET company_id = :1 WHERE company_id IS NOT NULL AND company_id <> :1' USING l_hq, l_hq;
  -- المخازن (تتبع الشركات) ثم الشركات الفرعية
  del('warehouses');
  del('companies', 'is_parent = ''N''');
  COMMIT;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  RAISE;
END;
/

------------------------------------------------------------------ 4) التقرير: عدد السجلات بعد التنظيف
DECLARE
  n NUMBER;
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name NOT LIKE 'BK\_%' ESCAPE '\' AND table_name NOT LIKE 'BIN$%' ORDER BY table_name) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM "' || t.table_name || '"' INTO n;
    DBMS_OUTPUT.PUT_LINE('ROWS ' || t.table_name || ' ' || n);
  END LOOP;
  SELECT COUNT(*) INTO n FROM user_objects WHERE status = 'INVALID';
  DBMS_OUTPUT.PUT_LINE('INVALID_OBJECTS ' || n);
END;
/

------------------------------------------------------------------ 5) حذف مستخدم التجارب TESTER (بعد فحص التطبيق)
BEGIN
  DELETE FROM app_users WHERE user_name = 'TESTER';
  DBMS_OUTPUT.PUT_LINE('DELETED TESTER ' || SQL%ROWCOUNT);
  COMMIT;
END;
/
