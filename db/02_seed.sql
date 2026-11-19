-- =====================================================================
--  02_seed.sql : بيانات أولية (أمثلة - عدّلها قبل التشغيل حسب شركتك)
-- =====================================================================
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- العملات (مثال: العملة الأساسية YER - غيّرها حسب عملتك الأساسية)
-- ---------------------------------------------------------------------
INSERT INTO currencies (currency_code, name_ar, name_en, symbol, decimals, is_base) VALUES ('YER','ريال يمني','Yemeni Rial','ر.ي',2,'Y');
INSERT INTO currencies (currency_code, name_ar, name_en, symbol, decimals, is_base) VALUES ('USD','دولار أمريكي','US Dollar','$',2,'N');
INSERT INTO currencies (currency_code, name_ar, name_en, symbol, decimals, is_base) VALUES ('SAR','ريال سعودي','Saudi Riyal','ر.س',2,'N');

INSERT INTO exchange_rates (currency_code, rate_date, rate) VALUES ('USD', TRUNC(SYSDATE,'YYYY'), 530);
INSERT INTO exchange_rates (currency_code, rate_date, rate) VALUES ('SAR', TRUNC(SYSDATE,'YYYY'), 140);

-- ---------------------------------------------------------------------
-- السنة المالية
-- ---------------------------------------------------------------------
INSERT INTO fiscal_years (fy_year, start_date, end_date)
VALUES (EXTRACT(YEAR FROM SYSDATE), TRUNC(SYSDATE,'YYYY'), ADD_MONTHS(TRUNC(SYSDATE,'YYYY'),12)-1);

-- ---------------------------------------------------------------------
-- الشركات
-- ---------------------------------------------------------------------
INSERT INTO companies (company_code, name_ar, is_parent) VALUES ('HQ','الشركة الأم','Y');
INSERT INTO companies (company_code, name_ar, is_parent, parent_id)
  SELECT 'C01','الشركة الفرعية الأولى','N', company_id FROM companies WHERE company_code='HQ';
INSERT INTO companies (company_code, name_ar, is_parent, parent_id)
  SELECT 'C02','الشركة الفرعية الثانية','N', company_id FROM companies WHERE company_code='HQ';

-- ---------------------------------------------------------------------
-- أنواع القيود
-- ---------------------------------------------------------------------
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('JV' ,'قيد يومية عام'      ,'General Journal'   ,'JV' ,'Y',1);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('OB' ,'قيد افتتاحي'        ,'Opening Balance'   ,'OB' ,'Y',2);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('ADJ','قيد تسوية'          ,'Adjustment'        ,'ADJ','Y',3);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('CL' ,'قيد إقفال'          ,'Closing'           ,'CL' ,'Y',4);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('RV' ,'سند قبض'            ,'Receipt Voucher'   ,'RV' ,'N',10);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('PV' ,'سند صرف'            ,'Payment Voucher'   ,'PV' ,'N',11);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('INV','فاتورة صرف لشركة'   ,'Interco Invoice'   ,'INV','N',20);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('RET','مرتجع من شركة'      ,'Interco Return'    ,'RET','N',21);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('PAY','قيد رواتب'          ,'Payroll'           ,'PAY','N',30);
INSERT INTO journal_types (jt_code,name_ar,name_en,prefix,manual_allowed,sort_order) VALUES ('REV','قيد عكسي'           ,'Reversal'          ,'REV','N',90);

-- ---------------------------------------------------------------------
-- شجرة الحسابات (4 مستويات): 1 / 11 / 1101 / 1101001
-- ---------------------------------------------------------------------
DECLARE
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2, p_parent VARCHAR2,
                 p_type VARCHAR2 DEFAULT NULL, p_nature CHAR DEFAULT NULL, p_cash CHAR DEFAULT 'N') IS
    l_parent_id NUMBER; l_level NUMBER; l_type VARCHAR2(10); l_nature CHAR(1);
  BEGIN
    IF p_parent IS NULL THEN
      l_level := 1; l_type := p_type; l_nature := p_nature;
    ELSE
      SELECT account_id, acc_level + 1, acc_type, nature
      INTO   l_parent_id, l_level, l_type, l_nature
      FROM   accounts WHERE account_code = p_parent;
    END IF;
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature, cash_bank)
    VALUES (p_code, p_name, l_parent_id, l_level, l_type, l_nature, p_cash);
  END;
BEGIN
  -- 1 الأصول
  acc('1','الأصول',NULL,'ASSET','D');
    acc('11','الأصول المتداولة','1');
      acc('1101','النقدية بالصناديق','11');
        acc('1101001','الصندوق الرئيسي','1101',p_cash=>'C');
        acc('1101002','صندوق نقاط البيع','1101',p_cash=>'C');
      acc('1102','النقدية بالبنوك','11');
        acc('1102001','البنك - حساب جاري','1102',p_cash=>'B');
      acc('1103','ذمم الشركات الفرعية','11');
        acc('1103001','ذمة الشركة الفرعية الأولى','1103');
        acc('1103002','ذمة الشركة الفرعية الثانية','1103');
      acc('1104','المخزون','11');
        acc('1104001','مخزون البضاعة','1104');
      acc('1105','ذمم الموظفين وسلفهم','11');
        acc('1105001','سلف الموظفين','1105');
    acc('12','الأصول الثابتة','1');
      acc('1201','الأثاث والأجهزة','12');
        acc('1201001','أجهزة حاسب','1201');
  -- 2 الخصوم
  acc('2','الخصوم',NULL,'LIAB','C');
    acc('21','الخصوم المتداولة','2');
      acc('2101','الموردون','21');
        acc('2101001','موردون عامون','2101');
      acc('2102','ذمم الشركة الأم','21');
        acc('2102001','الشركة الأم - حساب جاري','2102');
      acc('2103','رواتب مستحقة','21');
        acc('2103001','رواتب ومستحقات الموظفين','2103');
  -- 3 حقوق الملكية
  acc('3','حقوق الملكية',NULL,'EQUITY','C');
    acc('31','رأس المال','3');
      acc('3101','رأس المال المدفوع','31');
        acc('3101001','رأس المال','3101');
  -- 4 الإيرادات
  acc('4','الإيرادات',NULL,'REV','C');
    acc('41','إيرادات النشاط','4');
      acc('4101','المبيعات','41');
        acc('4101001','مبيعات للشركات الفرعية','4101');
        acc('4101002','مبيعات نقاط البيع','4101');
        acc('4101009','مردودات المبيعات','4101');
      acc('4102','إيرادات أخرى','41');
        acc('4102001','خصومات الموظفين (جزاءات)','4102');
  -- 5 المصروفات
  acc('5','المصروفات',NULL,'EXP','D');
    acc('51','تكلفة النشاط','5');
      acc('5101','المشتريات','51');
        acc('5101001','مشتريات من الشركة الأم','5101');
    acc('52','المصروفات الإدارية','5');
      acc('5201','الرواتب والأجور','52');
        acc('5201001','الرواتب الأساسية','5201');
        acc('5201002','العلاوات','5201');
        acc('5201003','الحوافز','5201');
        acc('5201004','فروقات رواتب','5201');
END;
/

-- ---------------------------------------------------------------------
-- الحسابات الافتراضية
-- ---------------------------------------------------------------------
INSERT INTO account_settings (company_id, setting_code, account_id)
SELECT c.company_id, s.code, a.account_id
FROM   companies c
CROSS JOIN (SELECT 'SALES' code, '4101001' acc FROM dual UNION ALL
            SELECT 'SALES_RETURN','4101009' FROM dual UNION ALL
            SELECT 'INTERCO_AP'  ,'2102001' FROM dual UNION ALL
            SELECT 'PURCHASES'   ,'5101001' FROM dual UNION ALL
            SELECT 'SALARY_EXP'  ,'5201001' FROM dual UNION ALL
            SELECT 'INCENTIVE_EXP','5201003' FROM dual UNION ALL
            SELECT 'SALARY_DIFF' ,'5201004' FROM dual UNION ALL
            SELECT 'SALARY_PAYABLE','2103001' FROM dual UNION ALL
            SELECT 'DEDUCTIONS'  ,'4102001' FROM dual) s
JOIN   accounts a ON a.account_code = s.acc;

INSERT INTO company_accounts (company_id, ar_account_id)
SELECT c.company_id, a.account_id FROM companies c JOIN accounts a ON a.account_code = '1103001' WHERE c.company_code = 'C01'
UNION ALL
SELECT c.company_id, a.account_id FROM companies c JOIN accounts a ON a.account_code = '1103002' WHERE c.company_code = 'C02';

-- ---------------------------------------------------------------------
-- أنواع العلاوات / الحوافز / الخصومات
-- ---------------------------------------------------------------------
INSERT INTO allowance_types (code,name_ar,kind,calc_method) VALUES ('HOUSING','بدل سكن','ALLOWANCE','PERCENT');
INSERT INTO allowance_types (code,name_ar,kind,calc_method) VALUES ('TRANSPORT','بدل مواصلات','ALLOWANCE','FIXED');
INSERT INTO allowance_types (code,name_ar,kind,calc_method) VALUES ('PERF','حافز أداء','INCENTIVE','FIXED');
INSERT INTO allowance_types (code,name_ar,kind,calc_method) VALUES ('ABSENCE','خصم غياب','DEDUCTION','FIXED');
INSERT INTO allowance_types (code,name_ar,kind,calc_method) VALUES ('PENALTY','جزاء إداري','DEDUCTION','FIXED');

COMMIT;
