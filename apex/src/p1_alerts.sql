SELECT 'مستندات بانتظار المراجعة' "التنبيه",
       (SELECT COUNT(*) FROM journals WHERE status = 'DRAFT' AND source_type IN ('MANUAL','CHEQUE'))
     + (SELECT COUNT(*) FROM vouchers WHERE status = 'DRAFT') "العدد" FROM dual
UNION ALL
SELECT 'مستندات بانتظار الاعتماد',
       (SELECT COUNT(*) FROM journals WHERE status = 'REVIEWED') + (SELECT COUNT(*) FROM vouchers WHERE status = 'REVIEWED') FROM dual
UNION ALL
SELECT 'مستندات معادة للمدخل',
       (SELECT COUNT(*) FROM journals WHERE status = 'RETURNED') + (SELECT COUNT(*) FROM vouchers WHERE status = 'RETURNED') FROM dual
UNION ALL
SELECT 'شيكات مستحقة أو متأخرة', COUNT(*) FROM cheques c JOIN vouchers v ON v.voucher_id = c.voucher_id
WHERE c.status = 'PENDING' AND c.due_date <= TRUNC(SYSDATE) AND v.status IN ('APPROVED','POSTED')
UNION ALL
SELECT 'شيكات تستحق خلال 7 أيام', COUNT(*) FROM cheques c JOIN vouchers v ON v.voucher_id = c.voucher_id
WHERE c.status = 'PENDING' AND c.due_date > TRUNC(SYSDATE) AND c.due_date <= TRUNC(SYSDATE) + 7 AND v.status IN ('APPROVED','POSTED')
UNION ALL
SELECT 'أصناف تحت حد الطلب', COUNT(*) FROM v_stock_balance b JOIN items i ON i.item_id = b.item_id
WHERE b.qty_base <= i.reorder_level AND (:P1_COMPANY_ID IS NULL OR b.company_id = :P1_COMPANY_ID)
UNION ALL
-- أرصدة العملاء (حسابات المستوى 4 تحت 1106) من القيود المرحّلة
SELECT 'عملاء تجاوزوا حد الائتمان', COUNT(*) FROM (
  SELECT a.account_id FROM accounts a
  JOIN   journal_lines l ON l.account_id = a.account_id
  JOIN   journals j ON j.journal_id = l.journal_id AND j.status IN ('POSTED','REVERSED')
  WHERE  a.account_code LIKE '1106%' AND a.acc_level = 4 AND a.credit_limit > 0
  GROUP  BY a.account_id, a.credit_limit
  HAVING SUM(l.debit_base - l.credit_base) > a.credit_limit)
UNION ALL
-- جزء من الرصيد أقدم من 90 يوماً: الرصيد أكبر من كل ما زاده (المدين) خلال آخر 90 يوماً
SELECT 'عملاء عليهم ديون أقدم من 90 يوماً (أعمار الديون)', COUNT(*) FROM (
  SELECT a.account_id FROM accounts a
  JOIN   journal_lines l ON l.account_id = a.account_id
  JOIN   journals j ON j.journal_id = l.journal_id AND j.status IN ('POSTED','REVERSED')
  WHERE  a.account_code LIKE '1106%' AND a.acc_level = 4
  GROUP  BY a.account_id
  HAVING SUM(l.debit_base - l.credit_base) > 0
  AND    SUM(l.debit_base - l.credit_base) > SUM(CASE WHEN j.journal_date > TRUNC(SYSDATE) - 90 THEN l.debit_base ELSE 0 END) + 0.01)
UNION ALL
SELECT 'خزائن رصيدها سالب (خطأ إدخال)', COUNT(*) FROM (
  SELECT a.account_id FROM accounts a
  JOIN   journal_lines l ON l.account_id = a.account_id
  JOIN   journals j ON j.journal_id = l.journal_id AND j.status IN ('POSTED','REVERSED')
  WHERE  a.cash_bank = 'C'
  GROUP  BY a.account_id
  HAVING SUM(l.debit_base - l.credit_base) < -0.01)
