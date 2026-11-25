-- =====================================================================
--  16_fs_notes.sql
--  أرقام الإيضاحات في القوائم المالية (الصفحة 84): يكتبها المستخدم لكل سطر وتُحفظ
--    line_key: BS:<رقم الحساب> بنود المركز المالي ، CS:<رقم الحساب> تكلفة المبيعات ، IS:<رمز> قائمة الدخل
--  يُشغّل مرة واحدة بعد 15 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'FS_NOTES';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
CREATE TABLE fs_notes (
  line_key   VARCHAR2(40) PRIMARY KEY,
  note_text  VARCHAR2(50),
  updated_by VARCHAR2(100),
  updated_on DATE DEFAULT SYSDATE
)]';
  END IF;
END;
/
