-- =====================================================================
--  23_backup_sys_setup.sql  -  إعداد النسخ الاحتياطي (يُشغَّل مرة واحدة بصلاحية SYS)
--    sqlplus / as sysdba @db/23_backup_sys_setup.sql
--
--  يسمح لمخطط التطبيق MOSS بكتابة النسخ الاحتياطية في مجلد يكتبه المستخدم في صفحة النسخ الاحتياطي،
--  بدون منحه صلاحية CREATE ANY DIRECTORY الواسعة: إجراء صغير يملكه SYS يعيد تعريف مجلد واحد فقط
--  (MOSS_BACKUP) على المسار المطلوب ويمنح MOSS القراءة والكتابة عليه ، وMOSS له تنفيذ هذا الإجراء فقط.
--  المسار مجلد على جهاز قاعدة البيانات (هذا الجهاز) ويجب أن يكون موجوداً.
-- =====================================================================
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = ORCLPDB;

CREATE OR REPLACE PROCEDURE sys.moss_backup_dir (p_path IN VARCHAR2) AUTHID DEFINER IS
  l_path VARCHAR2(400) := RTRIM(TRIM(p_path), '\/');
BEGIN
  -- مسار ويندوز كامل على قرص محلي ، بدون رجوع للأعلى ولا علامات اقتباس
  IF l_path IS NULL OR LENGTH(l_path) > 300
     OR NOT REGEXP_LIKE(l_path, '^[A-Za-z]:(\\|$)')
     OR INSTR(l_path, '..') > 0 OR INSTR(l_path, '''') > 0 OR INSTR(l_path, '"') > 0 OR INSTR(l_path, CHR(0)) > 0 THEN
    raise_application_error(-20301, 'Invalid backup folder path');   -- الصفحة تعرض الرسالة بالعربية
  END IF;
  IF LENGTH(l_path) = 2 THEN l_path := l_path || '\'; END IF;   -- جذر القرص مثل D:
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY MOSS_BACKUP AS ''' || l_path || '''';
  EXECUTE IMMEDIATE 'GRANT READ, WRITE ON DIRECTORY MOSS_BACKUP TO MOSS';
END;
/

GRANT EXECUTE ON sys.moss_backup_dir TO moss;
-- تهيئة أولى (يغيّرها المستخدم من الصفحة)
EXEC sys.moss_backup_dir('C:\')
PROMPT ===== backup setup done
EXIT
