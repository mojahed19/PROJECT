SELECT DECODE(item_kind,'BASIC','الأساسي','ALLOWANCE','علاوة','INCENTIVE','حافز','DIFF','فرق','DEDUCTION','خصم') "النوع",
       description "البند",
       CASE WHEN amount > 0 THEN amount END "استحقاق",
       CASE WHEN amount < 0 THEN -amount END "استقطاع"
FROM payroll_line_details WHERE pline_id = :P101_PLINE_ID
ORDER BY DECODE(item_kind,'BASIC',1,'ALLOWANCE',2,'INCENTIVE',3,'DIFF',4,5)
