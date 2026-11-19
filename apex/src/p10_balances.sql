SELECT LPAD(' ', (a.acc_level - 1) * 4, ' ') || a.account_code AS "رقم الحساب",
       a.name_ar                                               AS "اسم الحساب",
       a.acc_level                                             AS "المستوى",
       NVL(SUM(b.dr), 0)                                       AS "مدين",
       NVL(SUM(b.cr), 0)                                       AS "دائن",
       NVL(SUM(b.dr) - SUM(b.cr), 0)                           AS "الرصيد"
FROM   accounts a
LEFT JOIN (SELECT d.account_code, SUM(l.debit_base) dr, SUM(l.credit_base) cr
           FROM   journal_lines l
           JOIN   journals j ON j.journal_id = l.journal_id
                            AND j.status IN ('POSTED','REVERSED')
                            AND (:P10_FILTER_COMPANY IS NULL OR j.company_id = :P10_FILTER_COMPANY)
           JOIN   accounts d ON d.account_id = l.account_id
           GROUP  BY d.account_code) b
       ON b.account_code LIKE a.account_code || '%'
GROUP  BY a.account_code, a.name_ar, a.acc_level
ORDER  BY a.account_code
