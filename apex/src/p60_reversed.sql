SELECT o.journal_no AS "القيد الأصلي", o.journal_date AS "تاريخه",
       r.journal_no AS "القيد العكسي", r.journal_date AS "تاريخ العكس",
       o.total_debit AS "المبلغ", o.currency_code AS "العملة",
       o.reverse_reason AS "السبب", r.created_by AS "بواسطة"
FROM   journals o
JOIN   journals r ON r.journal_id = o.reversed_by_id
WHERE  (:G_USER_ROLE = 'GM' OR o.company_id = :G_COMPANY_ID)
ORDER  BY r.journal_date DESC
