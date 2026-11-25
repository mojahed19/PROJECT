-- =====================================================================
--  24_backup.sql  -  النسخ الاحتياطي من صفحة التطبيق (يتطلب تشغيل 23_backup_sys_setup.sql مرة واحدة بصلاحية SYS)
--   backup_run(النوع ، المجلد ، اسم الملف):
--     APP : تصدير التطبيق 115 كاملاً (الصفحات والقوائم والملفات الثابتة) إلى <الاسم>.sql
--           للاسترجاع: App Builder > Import
--     DB  : تصدير مخطط MOSS بالبيانات (Data Pump) إلى <الاسم>.dmp مع سجل <الاسم>.log
--           للاسترجاع: impdp ... DUMPFILE=<الاسم>.dmp SCHEMAS=MOSS
--   المجلد على جهاز قاعدة البيانات ويجب أن يكون موجوداً ، ولا يُكتب فوق ملف موجود
--   كل محاولة تُسجَّل في backup_log (ناجحة أو فاشلة)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'BACKUP_LOG';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE backup_log (
        backup_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        backup_type  VARCHAR2(3)    NOT NULL CHECK (backup_type IN ('APP','DB')),
        folder       VARCHAR2(400)  NOT NULL,
        file_name    VARCHAR2(200)  NOT NULL,
        status       VARCHAR2(5)    NOT NULL CHECK (status IN ('OK','ERROR')),
        file_size    NUMBER,
        message      VARCHAR2(4000),
        created_by   VARCHAR2(255),
        created_on   DATE DEFAULT SYSDATE NOT NULL
      )]';
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE backup_run (
  p_type   IN  VARCHAR2,          -- APP / DB
  p_folder IN  VARCHAR2,
  p_file   IN  VARCHAR2,          -- بدون امتداد (يُضاف .sql أو .dmp)
  p_user   IN  VARCHAR2,
  p_msg    OUT VARCHAR2
) IS
  l_file   VARCHAR2(200);
  l_ext    VARCHAR2(5) := CASE p_type WHEN 'APP' THEN '.sql' ELSE '.dmp' END;
  l_exists BOOLEAN; l_len NUMBER; l_bs BINARY_INTEGER;
  l_size   NUMBER;
  l_err    VARCHAR2(4000);

  PROCEDURE log_it (p_status VARCHAR2, p_text VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO backup_log (backup_type, folder, file_name, status, file_size, message, created_by)
    VALUES (p_type, SUBSTR(p_folder, 1, 400), NVL(l_file, SUBSTR(p_file, 1, 200)), p_status, l_size, SUBSTR(p_text, 1, 4000), p_user);
    COMMIT;
  END;

  PROCEDURE write_app IS
    l_files apex_t_export_files;
    l_clob  CLOB;
    l_fh    UTL_FILE.FILE_TYPE;
    l_pos   PLS_INTEGER := 1;
    l_chunk VARCHAR2(8000 CHAR);
    l_total PLS_INTEGER;
  BEGIN
    l_files := apex_export.get_application(p_application_id => 115, p_split => FALSE);
    l_clob  := l_files(1).contents;
    l_total := DBMS_LOB.GETLENGTH(l_clob);
    l_fh := UTL_FILE.FOPEN('MOSS_BACKUP', l_file, 'wb', 32767);
    WHILE l_pos <= l_total LOOP
      l_chunk := DBMS_LOB.SUBSTR(l_clob, 8000, l_pos);
      UTL_FILE.PUT_RAW(l_fh, UTL_I18N.STRING_TO_RAW(l_chunk, 'AL32UTF8'), TRUE);
      l_pos := l_pos + 8000;
    END LOOP;
    UTL_FILE.FCLOSE(l_fh);
  EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(l_fh) THEN UTL_FILE.FCLOSE(l_fh); END IF;
    RAISE;
  END;

  PROCEDURE write_db IS
    h       NUMBER;
    l_state VARCHAR2(30);
    l_log   VARCHAR2(200) := REGEXP_REPLACE(l_file, '\.dmp$', '.log');
  BEGIN
    h := DBMS_DATAPUMP.OPEN(operation => 'EXPORT', job_mode => 'SCHEMA',
                            job_name => 'MOSS_BACKUP_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3'));
    DBMS_DATAPUMP.ADD_FILE(h, l_file, 'MOSS_BACKUP', filetype => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE);
    DBMS_DATAPUMP.ADD_FILE(h, l_log,  'MOSS_BACKUP', filetype => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE);
    DBMS_DATAPUMP.METADATA_FILTER(h, 'SCHEMA_EXPR', 'IN (''MOSS'')');
    -- جداول النسخ القديمة من التنظيف (BK_) وجدول السجل نفسه لا حاجة لها في النسخة
    DBMS_DATAPUMP.METADATA_FILTER(h, 'NAME_EXPR', 'NOT LIKE ''BK\_%'' ESCAPE ''\''', 'TABLE');
    DBMS_DATAPUMP.START_JOB(h);
    DBMS_DATAPUMP.WAIT_FOR_JOB(h, l_state);
    IF l_state NOT IN ('COMPLETED') THEN
      raise_application_error(-20312, 'انتهت مهمة التصدير بالحالة ' || l_state || '. راجع ملف السجل ' || l_log);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    BEGIN DBMS_DATAPUMP.DETACH(h); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
  END;
BEGIN
  IF p_type NOT IN ('APP','DB') THEN raise_application_error(-20310, 'نوع النسخة غير صحيح'); END IF;
  -- اسم الملف: حروف إنجليزية وأرقام و _ - . فقط (يُحذف الامتداد إن كُتب)
  l_file := REGEXP_REPLACE(TRIM(p_file), '\.(sql|dmp|log)$', '', 1, 1, 'i');
  IF l_file IS NULL OR NOT REGEXP_LIKE(l_file, '^[A-Za-z0-9_.-]{1,100}$') THEN
    raise_application_error(-20311, 'اسم الملف: حروف إنجليزية وأرقام و _ و - فقط (بدون مسافات)');
  END IF;
  l_file := l_file || l_ext;

  BEGIN
    sys.moss_backup_dir(p_folder);
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20301 THEN raise_application_error(-20313, 'المجلد غير صحيح. اكتب مساراً كاملاً مثل D:\Backup\MOSS');
    ELSE RAISE; END IF;
  END;

  UTL_FILE.FGETATTR('MOSS_BACKUP', l_file, l_exists, l_len, l_bs);
  IF l_exists THEN raise_application_error(-20314, 'الملف ' || l_file || ' موجود في المجلد. اكتب اسماً آخر'); END IF;

  IF p_type = 'APP' THEN write_app; ELSE write_db; END IF;

  UTL_FILE.FGETATTR('MOSS_BACKUP', l_file, l_exists, l_len, l_bs);
  l_size := l_len;
  p_msg := CASE p_type WHEN 'APP' THEN 'نسخة التطبيق' ELSE 'نسخة قاعدة البيانات' END || ' حُفظت في '
           || RTRIM(p_folder, '\') || '\' || l_file || ' (' || TO_CHAR(ROUND(NVL(l_len, 0) / 1024), 'FM999G999G990') || ' كيلوبايت)';
  log_it('OK', p_msg);
EXCEPTION WHEN OTHERS THEN
  l_err := CASE
             WHEN SQLCODE BETWEEN -20399 AND -20300 THEN REGEXP_REPLACE(SQLERRM, '^ORA-[0-9]+: ', '')
             WHEN SQLCODE IN (-29280, -29283, -39002, -39070, -39087) THEN
               'تعذّر الكتابة في المجلد ' || p_folder || ': تأكد أن المجلد موجود على هذا الجهاز وأن خدمة Oracle تستطيع الكتابة فيه'
             WHEN SQLCODE = -6550 OR SQLCODE = -201 THEN
               'إعداد النسخ الاحتياطي غير مكتمل: شغّل db/23_backup_sys_setup.sql بصلاحية SYS مرة واحدة'
             ELSE SQLERRM END;
  l_size := NULL;
  log_it('ERROR', l_err || CASE WHEN SQLCODE NOT BETWEEN -20399 AND -20300 THEN ' [' || SQLERRM || ']' END);
  raise_application_error(-20399, l_err);
END;
/
