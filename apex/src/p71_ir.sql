SELECT a.adj_id,
       DECODE(a.adj_type,'DED','خصم','DIFF','فرق مبلغ','INC','حافز') AS "النوع",
       a.adj_no AS "الرقم", a.adj_date AS "التاريخ",
       SUBSTR(a.pay_period,1,4) || '-' || SUBSTR(a.pay_period,5,2) AS "شهر الراتب",
       t.name_ar AS "البند", a.total_amount AS "الإجمالي", a.currency_code AS "العملة",
       a.reason AS "السبب",
       DECODE(a.status,'DRAFT','مسودة','APPROVED','معتمد','APPLIED','مطبَّق','CANCELLED','ملغى') AS "الحالة",
       a.created_by AS "أنشأه", a.approved_by AS "اعتمده"
FROM   payroll_adj a
LEFT JOIN allowance_types t ON t.allowance_id = a.allowance_id
