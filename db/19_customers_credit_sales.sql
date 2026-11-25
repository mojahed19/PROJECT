-- =====================================================================
--  19_customers_credit_sales.sql
--   - مجموعة العملاء 1106 (البيع الآجل يعرض الحسابات تحتها) ومجموعة الموردين 2101 (الشراء الآجل)
--   - فصل إيراد المبيعات: 4101001 المبيعات النقدية (SALES_EXT) ، 4101002 المبيعات الآجلة (SALES_CREDIT)
--  آمن لإعادة التشغيل: لا يضيف حساباً موجوداً ، ولا يغيّر اسماً عدّله المستخدم
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_hq NUMBER;
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2, p_type VARCHAR2, p_nature VARCHAR2) IS
    l_cnt NUMBER; l_parent NUMBER; l_lvl NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_code = p_code;
    IF l_cnt > 0 THEN DBMS_OUTPUT.PUT_LINE('EXISTS ' || p_code); RETURN; END IF;
    l_lvl := CASE LENGTH(p_code) WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 4 THEN 3 ELSE 4 END;
    SELECT account_id INTO l_parent FROM accounts
    WHERE  account_code = SUBSTR(p_code, 1, CASE l_lvl WHEN 2 THEN 1 WHEN 3 THEN 2 ELSE 4 END);
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature, cash_bank, is_active)
    VALUES (p_code, p_name, l_parent, l_lvl, p_type, p_nature, 'N', 'Y');
    DBMS_OUTPUT.PUT_LINE('ADDED ' || p_code || ' ' || p_name);
  END;
BEGIN
  SELECT company_id INTO l_hq FROM companies WHERE is_parent = 'Y';

  -- العملاء والموردون (يُضاف كل عميل / مورد حساباً تحليلياً تحت مجموعته)
  acc('1106', 'العملاء',  'ASSET', 'D');
  acc('2101', 'الموردون', 'LIAB',  'C');

  -- المبيعات النقدية والآجلة
  UPDATE accounts SET name_ar = 'المبيعات النقدية' WHERE account_code = '4101001' AND name_ar = 'مبيعات للعملاء';
  IF SQL%ROWCOUNT > 0 THEN DBMS_OUTPUT.PUT_LINE('RENAMED 4101001 المبيعات النقدية'); END IF;
  acc('4101002', 'المبيعات الآجلة', 'REV', 'C');

  MERGE INTO account_settings s
  USING (SELECT l_hq company_id, 'SALES_CREDIT' setting_code,
                (SELECT account_id FROM accounts WHERE account_code = '4101002') account_id FROM dual) x
  ON (s.company_id = x.company_id AND s.setting_code = x.setting_code)
  WHEN MATCHED THEN UPDATE SET s.account_id = x.account_id
  WHEN NOT MATCHED THEN INSERT (company_id, setting_code, account_id) VALUES (x.company_id, x.setting_code, x.account_id);
  DBMS_OUTPUT.PUT_LINE('SETTING SALES_CREDIT -> 4101002');
  COMMIT;
END;
/
