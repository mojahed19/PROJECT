-- =====================================================================
--  18_base_accounts.sql  -  المستوى الأول من شجرة الحسابات + الحسابات الافتراضية التي يحتاجها النظام
--  (آمن لإعادة التشغيل: لا يضيف حساباً موجوداً برقمه ، ويحدّث ربط الإعداد فقط)
--
--  المستوى 1: 1 الأصول ، 2 الخصوم ، 3 حقوق الملكية ، 4 الإيرادات ، 5 المصروفات
--  ثم لكل حساب افتراضي المسار اللازم (مستوى 2 ← 3 ← 4) ، وتُعدَّل الأسماء لاحقاً من شجرة الحسابات
--  أطوال الأرقام: م1 = 1 خانة ، م2 = 2 ، م3 = 4 ، م4 = 7
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
    IF l_lvl > 1 THEN
      SELECT account_id INTO l_parent FROM accounts
      WHERE  account_code = SUBSTR(p_code, 1, CASE l_lvl WHEN 2 THEN 1 WHEN 3 THEN 2 ELSE 4 END);
    END IF;
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature, cash_bank, is_active)
    VALUES (p_code, p_name, l_parent, l_lvl, p_type, p_nature, 'N', 'Y');
    DBMS_OUTPUT.PUT_LINE('ADDED ' || p_code || ' ' || p_name);
  END;
  PROCEDURE setting (p_code VARCHAR2, p_account VARCHAR2) IS
  BEGIN
    MERGE INTO account_settings s
    USING (SELECT l_hq company_id, p_code setting_code, (SELECT account_id FROM accounts WHERE account_code = p_account) account_id FROM dual) x
    ON (s.company_id = x.company_id AND s.setting_code = x.setting_code)
    WHEN MATCHED THEN UPDATE SET s.account_id = x.account_id
    WHEN NOT MATCHED THEN INSERT (company_id, setting_code, account_id) VALUES (x.company_id, x.setting_code, x.account_id);
    DBMS_OUTPUT.PUT_LINE('SETTING ' || p_code || ' -> ' || p_account);
  END;
BEGIN
  SELECT company_id INTO l_hq FROM companies WHERE is_parent = 'Y';

  ------------------------------------------------------------------ المستوى الأول
  acc('1', 'الأصول',        'ASSET',  'D');
  acc('2', 'الخصوم',        'LIAB',   'C');
  acc('3', 'حقوق الملكية',  'EQUITY', 'C');
  acc('4', 'الإيرادات',     'REV',    'C');
  acc('5', 'المصروفات',     'EXP',    'D');

  ------------------------------------------------------------------ مسارات الحسابات الافتراضية
  -- الأصول المتداولة: المخزون ، الشيكات تحت التحصيل
  acc('11',      'الأصول المتداولة',            'ASSET', 'D');
  acc('1104',    'المخزون',                      'ASSET', 'D');
  acc('1104001', 'مخزون البضاعة',                'ASSET', 'D');
  acc('1107',    'شيكات تحت التحصيل',           'ASSET', 'D');
  acc('1107001', 'شيكات تحت التحصيل',           'ASSET', 'D');
  -- الخصوم المتداولة: الرواتب المستحقة ، الشيكات تحت الصرف
  acc('21',      'الخصوم المتداولة',            'LIAB', 'C');
  acc('2103',    'رواتب ومستحقات الموظفين',     'LIAB', 'C');
  acc('2103001', 'رواتب مستحقة',                 'LIAB', 'C');
  acc('2104',    'شيكات تحت الصرف',             'LIAB', 'C');
  acc('2104001', 'شيكات تحت الصرف',             'LIAB', 'C');
  -- الإيرادات: المبيعات ومردوداتها (طبيعتها مدين) ، خصومات الموظفين
  acc('41',      'إيرادات النشاط',              'REV', 'C');
  acc('4101',    'المبيعات',                     'REV', 'C');
  acc('4101001', 'مبيعات للعملاء',               'REV', 'C');
  acc('4101009', 'مردودات المبيعات',             'REV', 'D');
  acc('4102',    'إيرادات أخرى',                 'REV', 'C');
  acc('4102001', 'خصومات الموظفين (جزاءات)',     'REV', 'C');
  -- المصروفات: تكلفة المبيعات وفروقات الجرد ، الرواتب والحوافز والفروقات
  acc('51',      'تكلفة النشاط',                 'EXP', 'D');
  acc('5101',    'تكلفة المبيعات',               'EXP', 'D');
  acc('5101001', 'تكلفة البضاعة المباعة',        'EXP', 'D');
  acc('5101002', 'فروقات الجرد',                 'EXP', 'D');
  acc('52',      'المصروفات العمومية والإدارية', 'EXP', 'D');
  acc('5201',    'الرواتب والأجور',              'EXP', 'D');
  acc('5201001', 'الرواتب الأساسية',             'EXP', 'D');
  acc('5201002', 'الحوافز',                      'EXP', 'D');
  acc('5201003', 'فروقات الرواتب',               'EXP', 'D');

  ------------------------------------------------------------------ الحسابات الافتراضية للمؤسسة
  setting('SALES_EXT',      '4101001');   -- مبيعات للعملاء
  setting('SALES_RETURN',   '4101009');   -- مردودات المبيعات
  setting('INVENTORY',      '1104001');   -- المخزون
  setting('COGS',           '5101001');   -- تكلفة البضاعة المباعة
  setting('INVENTORY_ADJ',  '5101002');   -- فروقات الجرد
  setting('CHEQUES_IN',     '1107001');   -- شيكات تحت التحصيل
  setting('CHEQUES_OUT',    '2104001');   -- شيكات تحت الصرف
  setting('SALARY_EXP',     '5201001');   -- مصروف الرواتب
  setting('INCENTIVE_EXP',  '5201002');   -- مصروف الحوافز
  setting('SALARY_DIFF',    '5201003');   -- فروقات الرواتب
  setting('SALARY_PAYABLE', '2103001');   -- رواتب مستحقة
  setting('DEDUCTIONS',     '4102001');   -- خصومات الموظفين
  COMMIT;
END;
/
