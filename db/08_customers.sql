-- =====================================================================
--  08_customers.sql : مجموعة حسابات العملاء (تظهر في قائمة "آجل" في فاتورة المبيعات)
--  أضف كل عميل كحساب تحليلي تحت 1106 من شاشة شجرة الحسابات
-- =====================================================================
BEGIN
  INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature)
  SELECT '1106', 'العملاء', account_id, 3, acc_type, nature FROM accounts
  WHERE account_code = '11' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '1106');

  INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature)
  SELECT '1106001', 'عملاء عامون', account_id, 4, acc_type, nature FROM accounts
  WHERE account_code = '1106' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = '1106001');
  COMMIT;
END;
/
