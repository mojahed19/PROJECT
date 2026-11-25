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
PROMPT ===== 09_single_company.sql
@db/09_single_company.sql
PROMPT ===== 10_workflow_cheques.sql
@db/10_workflow_cheques.sql
PROMPT ===== 11_cheque_bank_serial.sql
@db/11_cheque_bank_serial.sql
PROMPT ===== 12_items_shifts.sql
@db/12_items_shifts.sql
PROMPT ===== 13_hr_types_incentive.sql
@db/13_hr_types_incentive.sql
PROMPT ===== 14_budget_plan.sql
@db/14_budget_plan.sql
PROMPT ===== 15_damaged_goods.sql
@db/15_damaged_goods.sql
PROMPT ===== 16_fs_notes.sql
@db/16_fs_notes.sql
PROMPT ===== 17_indexes.sql
@db/17_indexes.sql
PROMPT ===== 18_base_accounts.sql
@db/18_base_accounts.sql
PROMPT ===== 19_customers_credit_sales.sql
@db/19_customers_credit_sales.sql
PROMPT ===== 20_audit_log.sql
@db/20_audit_log.sql
PROMPT ===== 21_year_closing.sql
@db/21_year_closing.sql
PROMPT ===== 22_no_delete_posted.sql
@db/22_no_delete_posted.sql
-- قبل 24: شغّل مرة واحدة بصلاحية SYS: sqlplus / as sysdba @db/23_backup_sys_setup.sql
PROMPT ===== 24_backup.sql
@db/24_backup.sql
PROMPT ===== 25_damage_loss.sql
@db/25_damage_loss.sql

PROMPT ===== Invalid objects check
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID';

PROMPT ===== Done
SPOOL OFF
