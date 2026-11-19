-- =====================================================================
--  install_db.sql : تنفيذ كل سكربتات قاعدة البيانات بالترتيب
--  يُشغَّل من مجلد المشروع الرئيسي:  @install/install_db.sql
-- =====================================================================
SET ECHO OFF FEEDBACK ON TERMOUT ON SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

SPOOL install/logs/install_db.log

PROMPT ===== 01_tables.sql
@db/01_tables.sql
PROMPT ===== 02_seed.sql
@db/02_seed.sql
PROMPT ===== 03_phase2_tables.sql
@db/03_phase2_tables.sql
PROMPT ===== 04_purchases.sql
@db/04_purchases.sql
PROMPT ===== 05_sales.sql
@db/05_sales.sql
PROMPT ===== 06_branch_balances.sql
@db/06_branch_balances.sql
PROMPT ===== 07_rename_vouchers.sql
@db/07_rename_vouchers.sql
PROMPT ===== 08_customers.sql
@db/08_customers.sql

PROMPT ===== Invalid objects check
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID';

PROMPT ===== Done
SPOOL OFF
