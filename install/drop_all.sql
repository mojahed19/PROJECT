-- =====================================================================
--  drop_all.sql : حذف كل جداول وكائنات المشروع (لإعادة التركيب في بيئة الاختبار فقط)
--  يمسح البيانات نهائياً. لا تشغّله على قاعدة بيانات الإنتاج.
-- =====================================================================
SET SERVEROUTPUT ON
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(128);
  l_views  t_list := t_list('V_LATEST_RATES','V_ACCOUNTS_TREE','V_STOCK_BALANCE');
  l_tables t_list := t_list(
    'POS_PAYMENTS','POS_SALE_LINES','POS_SALES','POS_SHIFTS','POS_TERMINAL_USERS','POS_TERMINALS',
    'BUDGET_LINES','BUDGETS',
    'PAYROLL_RUN_JOURNALS','PAYROLL_LINE_DETAILS','PAYROLL_LINES',
    'PAYROLL_ADJ_LINES','PAYROLL_ADJ','PAYROLL_RUNS',
    'STOCK_TRANS_LINES','STOCK_TRANS',
    'INVOICE_LINES','INVOICES','PRICE_LIST_ITEMS',
    'VOUCHER_LINES','VOUCHERS',
    'EMP_ALLOWANCES','GRADE_ALLOWANCES','ALLOWANCE_TYPES',
    'JOURNAL_LINES','JOURNALS','JOURNAL_TYPES',
    'ACCOUNT_SETTINGS','COMPANY_ACCOUNTS','EMPLOYEES','JOB_GRADES',
    'ITEM_UNITS','ITEMS','UNITS','WAREHOUSES','PRICE_LISTS',
    'DOC_SEQUENCES','USER_COMPANIES','APP_USERS','ACCOUNTS',
    'FISCAL_YEARS','EXCHANGE_RATES','COMPANIES','CURRENCIES');
  PROCEDURE run (p VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p;
    DBMS_OUTPUT.PUT_LINE('OK   ' || p);
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE NOT IN (-942, -4043) THEN RAISE; END IF;   -- غير موجود: تجاهل
  END;
BEGIN
  FOR i IN 1 .. l_views.COUNT  LOOP run('DROP VIEW '  || l_views(i)); END LOOP;
  FOR i IN 1 .. l_tables.COUNT LOOP run('DROP TABLE ' || l_tables(i) || ' CASCADE CONSTRAINTS PURGE'); END LOOP;
END;
/
