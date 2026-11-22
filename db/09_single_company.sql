-- =====================================================================
--  09_single_company.sql : النظام لشركة واحدة وعملة واحدة (الجنيه السوداني)
--  + سعر البيع وسعر الشراء في الأصناف
-- =====================================================================
DECLARE
  l_parent NUMBER;
  l_cnt    NUMBER;
  PROCEDURE ddl (p VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p;
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE NOT IN (-1430, -1442) THEN RAISE; END IF;   -- العمود موجود / سبق تعديله
  END;
BEGIN
  -- 1) العملة الوحيدة: الجنيه السوداني
  INSERT INTO currencies (currency_code, name_ar, name_en, symbol, decimals, is_base, is_active)
  SELECT 'SDG', 'جنيه سوداني', 'Sudanese Pound', 'ج.س', 2, 'N', 'Y' FROM dual
  WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE currency_code = 'SDG');
  UPDATE currencies SET is_base = 'N' WHERE currency_code <> 'SDG';
  UPDATE currencies SET is_base = 'Y', is_active = 'Y' WHERE currency_code = 'SDG';
  UPDATE currencies SET is_active = 'N' WHERE currency_code <> 'SDG';

  -- 2) سعر البيع وسعر الشراء للصنف (للوحدة الأساسية ، وتُضرب في معامل الوحدة)
  ddl('ALTER TABLE items ADD (sale_price NUMBER(18,4) DEFAULT 0, purchase_price NUMBER(18,4) DEFAULT 0)');

  -- 3) الشركة الواحدة: الشركة الأم افتراضية في الجداول التي كان يُختار فيها الفرع
  SELECT company_id INTO l_parent FROM companies WHERE is_parent = 'Y';
  ddl('ALTER TABLE app_users  MODIFY (company_id DEFAULT ' || l_parent || ')');
  ddl('ALTER TABLE warehouses MODIFY (company_id DEFAULT ' || l_parent || ')');
  ddl('ALTER TABLE employees  MODIFY (company_id DEFAULT ' || l_parent || ')');
  ddl('ALTER TABLE budgets    MODIFY (company_id DEFAULT ' || l_parent || ')');
  ddl('ALTER TABLE account_settings MODIFY (company_id DEFAULT ' || l_parent || ')');
  ddl('ALTER TABLE job_grades  MODIFY (currency_code DEFAULT ''SDG'')');
  ddl('ALTER TABLE price_lists MODIFY (currency_code DEFAULT ''SDG'')');

  COMMIT;
END;
/
