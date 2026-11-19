-- =====================================================================
--  install_app.sql : تنزيل تطبيق APEX من ملف التصدير apex/app/f100.sql
--  الاستخدام:  @install/install_app.sql <WORKSPACE> <APP_ID>
--  يُشغَّل بحساب الـ Schema المرتبطة بالـ Workspace
-- =====================================================================
SET DEFINE ON VERIFY OFF FEEDBACK OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

SPOOL install/logs/install_app.log

DEFINE ws     = '&1'
DEFINE app_id = '&2'

BEGIN
  apex_application_install.set_workspace(UPPER('&ws'));
  apex_application_install.set_application_id(&app_id);
  apex_application_install.generate_offset;
  apex_application_install.set_schema(USER);
  apex_application_install.set_application_alias('GRP' || &app_id);
END;
/

SET DEFINE OFF
@apex/app/f100.sql

SPOOL OFF
