SELECT name_ar d, allowance_id r
FROM   allowance_types
WHERE  kind = CASE :P70_ADJ_TYPE WHEN 'DED' THEN 'DEDUCTION'
                                 WHEN 'INC' THEN 'INCENTIVE'
                                 ELSE kind END
ORDER  BY name_ar
