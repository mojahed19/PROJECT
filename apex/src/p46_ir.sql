SELECT v.voucher_id, v.voucher_type,
       DECODE(v.voucher_type, 'R', 'توريد شيكات', 'صرف شيكات') AS "النوع",
       v.voucher_no AS "الرقم", v.voucher_date AS "التاريخ",
       ca.account_code || ' - ' || ca.name_ar AS "الحساب المقابل",
       v.party_name AS "الاسم",
       (SELECT COUNT(*) FROM cheques c WHERE c.voucher_id = v.voucher_id) AS "عدد الشيكات",
       (SELECT TO_CHAR(MIN(c.due_date), 'DD/MM/YYYY') FROM cheques c WHERE c.voucher_id = v.voucher_id) AS "أقرب استحقاق",
       v.total_amount AS "المبلغ", v.description AS "البيان",
       DECODE(v.status, 'DRAFT', 'مسودة', 'RETURNED', 'معاد للمدخل', 'REVIEWED', 'مُراجَع',
              'APPROVED', 'معتمد', 'POSTED', 'مرحّل', 'REVERSED', 'معكوس') AS "الحالة",
       v.created_by AS "المدخل", v.reviewed_by AS "المراجع", v.approved_by AS "المعتمد"
FROM   vouchers v
LEFT JOIN accounts ca ON ca.account_id = v.counter_account_id
WHERE  v.voucher_kind = 'CHEQUE'
AND    (:P46_TYPE IS NULL OR v.voucher_type = :P46_TYPE)
AND    (:P46_STATUS IS NULL OR v.status = :P46_STATUS)
ORDER BY v.voucher_date DESC, v.voucher_no DESC
