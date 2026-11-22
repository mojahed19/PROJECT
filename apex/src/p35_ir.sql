SELECT d.journal_id, d.cash_voucher_id, d.chq_voucher_id, d.adj_id, d.voucher_type, d.adj_type,
       d."المستند", d."قيد", d."إذن نقدي", d."إذن شيكات", d."تسوية رواتب", d."التاريخ", d."البيان", d."المبلغ",
       DECODE(d.st, 'DRAFT', 'مسودة - بانتظار المراجعة', 'RETURNED', 'معاد للمدخل',
              'REVIEWED', 'مُراجَع - بانتظار الاعتماد', 'APPROVED', 'معتمد - بانتظار الترحيل') AS "الحالة",
       d."المدخل", d."سبب الإعادة"
FROM (
  SELECT 'قيد يومية' AS "المستند", j.journal_no AS "قيد", NULL AS "إذن نقدي", NULL AS "إذن شيكات", NULL AS "تسوية رواتب",
         j.journal_id, NULL AS cash_voucher_id, NULL AS chq_voucher_id, NULL AS adj_id, NULL AS voucher_type, NULL AS adj_type,
         j.journal_date AS "التاريخ", j.description AS "البيان", j.total_debit AS "المبلغ", j.status AS st,
         j.created_by AS "المدخل", j.return_note AS "سبب الإعادة"
  FROM   journals j WHERE j.status IN ('DRAFT','RETURNED','REVIEWED','APPROVED') AND j.source_type IN ('MANUAL','CHEQUE')
  UNION ALL
  SELECT CASE v.voucher_type WHEN 'R' THEN 'إذن توريد ' ELSE 'إذن صرف ' END || CASE v.voucher_kind WHEN 'CHEQUE' THEN 'شيكات' ELSE 'نقدي' END,
         NULL, CASE WHEN v.voucher_kind = 'CASH' THEN v.voucher_no END, CASE WHEN v.voucher_kind = 'CHEQUE' THEN v.voucher_no END, NULL,
         NULL, CASE WHEN v.voucher_kind = 'CASH' THEN v.voucher_id END, CASE WHEN v.voucher_kind = 'CHEQUE' THEN v.voucher_id END, NULL,
         v.voucher_type, NULL,
         v.voucher_date, v.description, v.total_amount, v.status, v.created_by, v.return_note
  FROM   vouchers v WHERE v.status IN ('DRAFT','RETURNED','REVIEWED','APPROVED')
  UNION ALL
  SELECT DECODE(a.adj_type, 'DED', 'خصم', 'DIFF', 'فرق مبلغ', 'حافز'), NULL, NULL, NULL, a.adj_no,
         NULL, NULL, NULL, a.adj_id, NULL, a.adj_type,
         a.adj_date, a.reason, NULL, a.status, a.created_by, a.return_note
  FROM   payroll_adj a WHERE a.status IN ('DRAFT','RETURNED','REVIEWED')
) d
WHERE (:G_USER_ROLE = 'ADMIN'
       OR (:G_USER_ROLE = 'ENTRY'    AND d.st IN ('DRAFT','RETURNED'))
       OR (:G_USER_ROLE = 'REVIEWER' AND d.st IN ('DRAFT','REVIEWED'))
       OR (:G_USER_ROLE = 'APPROVER' AND d.st IN ('REVIEWED','APPROVED')))
