-- =====================================================================
--  07_rename_vouchers.sql : تسمية السندات إذن توريد / إذن صرف
-- =====================================================================
UPDATE journal_types SET name_ar = 'إذن توريد' WHERE jt_code = 'RV';
UPDATE journal_types SET name_ar = 'إذن صرف'   WHERE jt_code = 'PV';
COMMIT;
