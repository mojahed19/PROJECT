-- =====================================================================
--  create_schema_workspace.sql : إنشاء Schema الاختبار و Workspace في APEX
--  يُشغَّل مرة واحدة بحساب مدير (SYS أو SYSTEM) على orclpdb:
--
--    sqlplus sys@localhost:1521/orclpdb as sysdba @install/create_schema_workspace.sql
--
--  يطلب: اسم الـ Schema، كلمة مرورها، واسم الـ Workspace
-- =====================================================================
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

ACCEPT schema_name CHAR DEFAULT 'GRP_TEST' PROMPT 'اسم الـ Schema [GRP_TEST]: '
ACCEPT schema_pass CHAR HIDE              PROMPT 'كلمة مرور الـ Schema: '
ACCEPT ws_name     CHAR DEFAULT 'GRP'      PROMPT 'اسم الـ Workspace [GRP]: '

CREATE USER &schema_name IDENTIFIED BY "&schema_pass"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE SYNONYM,
      CREATE MATERIALIZED VIEW, CREATE JOB TO &schema_name;

-- Workspace مرتبط بالـ Schema (يحتاج صلاحية APEX_ADMINISTRATOR_ROLE أو SYS)
BEGIN
  apex_instance_admin.add_workspace(
    p_workspace      => UPPER('&ws_name'),
    p_primary_schema => UPPER('&schema_name'));
  COMMIT;
END;
/

PROMPT
PROMPT تم. أنشئ الآن مستخدماً للـ Workspace من: http://localhost/ords/apex_admin
PROMPT (Manage Workspaces > Manage Developers and Users)
