SELECT DECODE(v.voucher_type, 'R', 'شيكات واردة للتحصيل', 'شيكات صادرة للصرف') AS "النوع",
       SUM(CASE WHEN c.due_date < TRUNC(SYSDATE) THEN 1 ELSE 0 END) AS "عدد المتأخرة",
       SUM(CASE WHEN c.due_date < TRUNC(SYSDATE) THEN c.amount ELSE 0 END) AS "مبلغ المتأخرة",
       SUM(CASE WHEN c.due_date = TRUNC(SYSDATE) THEN 1 ELSE 0 END) AS "عدد المستحقة اليوم",
       SUM(CASE WHEN c.due_date = TRUNC(SYSDATE) THEN c.amount ELSE 0 END) AS "مبلغ المستحقة اليوم",
       SUM(CASE WHEN c.due_date > TRUNC(SYSDATE) AND c.due_date <= TRUNC(SYSDATE) + 7 THEN c.amount ELSE 0 END) AS "مبلغ الأسبوع القادم",
       SUM(c.amount) AS "إجمالي القائمة"
FROM   cheques c
JOIN   vouchers v ON v.voucher_id = c.voucher_id
WHERE  c.status = 'PENDING' AND v.status IN ('APPROVED','POSTED')
GROUP BY v.voucher_type
