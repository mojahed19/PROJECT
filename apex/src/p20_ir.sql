SELECT jt_code         AS "الرمز",
       name_ar         AS "النوع",
       prefix          AS "البادئة",
       DECODE(manual_allowed,'Y','يدوي','آلي من الشاشات') AS "طريقة الإدخال",
       DECODE(is_active,'Y','فعّال','موقوف')             AS "الحالة",
       (SELECT COUNT(*) FROM journals j WHERE j.jt_code = t.jt_code) AS "عدد القيود",
       sort_order
FROM   journal_types t
ORDER  BY sort_order
