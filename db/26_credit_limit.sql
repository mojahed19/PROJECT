-- =====================================================================
--  26_credit_limit.sql  -  حد الائتمان للعميل
--   accounts.credit_limit: أقصى رصيد مدين مسموح لحساب العميل (تحت 1106) بالعملة الأساسية
--   فارغ أو صفر = بدون حد. يُدخل من شجرة الحسابات (صفحة 10) ويُفحص عند ترحيل فاتورة بيع آجل (صفحة 50)
--   ويظهر في تنبيهات الرئيسية العملاء الذين تجاوزوه
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = 'ACCOUNTS' AND column_name = 'CREDIT_LIMIT';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE accounts ADD (credit_limit NUMBER(18,2) CHECK (credit_limit IS NULL OR credit_limit >= 0))';
    DBMS_OUTPUT.PUT_LINE('ADDED accounts.credit_limit');
  END IF;
END;
/
