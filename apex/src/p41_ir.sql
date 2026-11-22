SELECT v.voucher_id, v.voucher_type,
       DECODE(v.voucher_type, 'R', 'توريد نقدي', 'صرف نقدي') AS "النوع",
       v.voucher_no AS "الرقم", v.voucher_date AS "التاريخ",
       a.name_ar AS "الخزينة", ca.account_code || ' - ' || ca.name_ar AS "الحساب المقابل",
       v.party_name AS "الاسم", v.total_amount AS "المبلغ", v.description AS "البيان",
       DECODE(v.status, 'DRAFT', 'مسودة', 'RETURNED', 'معاد للمدخل', 'REVIEWED', 'مُراجَع',
              'APPROVED', 'معتمد', 'POSTED', 'مرحّل', 'REVERSED', 'معكوس') AS "الحالة",
       v.created_by AS "المدخل", v.reviewed_by AS "المراجع", v.approved_by AS "المعتمد"
FROM   vouchers v
LEFT JOIN accounts a  ON a.account_id  = v.cash_account_id
LEFT JOIN accounts ca ON ca.account_id = v.counter_account_id
WHERE  v.voucher_kind = 'CASH'
AND    (:P41_TYPE IS NULL OR v.voucher_type = :P41_TYPE)
AND    (:P41_STATUS IS NULL OR v.status = :P41_STATUS)
ORDER BY v.voucher_date DESC, v.voucher_no DESC
