WITH p AS (
  SELECT TO_DATE(:P92_FROM, 'DD/MM/YYYY') d1, TO_DATE(:P92_TO, 'DD/MM/YYYY') d2, TO_NUMBER(:P92_WAREHOUSE_ID) wh FROM dual
),
mv AS (
  -- حركات المخزن المعتمدة بالوحدة الصغرى: المرحل قبل الفترة ، ثم الوارد والمنصرف والتالف خلالها
  SELECT l.item_id,
         SUM(CASE WHEN t.trans_date < p.d1 THEN l.qty_base ELSE 0 END) op,
         SUM(CASE WHEN t.trans_date >= p.d1 AND t.trans_type <> 'DAMAGE' AND l.qty_base > 0 THEN l.qty_base ELSE 0 END) qin,
         SUM(CASE WHEN t.trans_date >= p.d1 AND t.trans_type <> 'DAMAGE' AND l.qty_base < 0 THEN -l.qty_base ELSE 0 END) qout,
         SUM(CASE WHEN t.trans_date >= p.d1 AND t.trans_type = 'DAMAGE' THEN -l.qty_base ELSE 0 END) qdmg
  FROM   stock_trans_lines l
  JOIN   stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED'
  CROSS JOIN p
  WHERE  l.warehouse_id = p.wh
  AND    t.trans_date < p.d2 + 1
  GROUP  BY l.item_id
),
r AS (
  SELECT i.item_code, i.name_ar, ub.name_ar small_name, bu.name_ar big_name,
         i.base_unit_id, i.big_unit_id, i.big_factor, NVL(i.purchase_price, 0) price,
         m.op, m.qin, m.qout, m.qdmg, m.op + m.qin - m.qout - m.qdmg cur
  FROM   mv m
  JOIN   items i  ON i.item_id  = m.item_id
  JOIN   units ub ON ub.unit_id = i.base_unit_id
  LEFT JOIN units bu ON bu.unit_id = i.big_unit_id
  WHERE  m.op <> 0 OR m.qin <> 0 OR m.qout <> 0 OR m.qdmg <> 0
)
SELECT LPAD(item_code, 20, '0') AS sort_key,
       item_code   AS "الكود",
       name_ar     AS "الصنف",
       small_name  AS "الوحدة الصغرى",
       op          AS "الرصيد المرحل",
       qin         AS "الوارد",
       qout        AS "المنصرف",
       qdmg        AS "التالف",
       cur         AS "الحالي",
       CASE WHEN big_unit_id IS NOT NULL AND big_unit_id <> base_unit_id AND big_factor > 1 THEN
              CASE WHEN TRUNC(cur / big_factor) <> 0 THEN TRUNC(cur / big_factor) || ' ' || big_name END
           || CASE WHEN TRUNC(cur / big_factor) <> 0 AND MOD(cur, big_factor) <> 0 THEN ' و ' END
           || CASE WHEN MOD(cur, big_factor) <> 0 OR TRUNC(cur / big_factor) = 0 THEN MOD(cur, big_factor) || ' ' || small_name END
            ELSE cur || ' ' || small_name END AS "الحالي بالعبوات الكبيرة",
       price       AS "سعر شراء الصغرى",
       ROUND(cur * price, 2) AS "الإجمالي"
FROM   r
UNION ALL
SELECT 'zzzzzzzzzzzzzzzzzzzzz', NULL, 'إجمالي الموجود بالمخزن', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NVL(SUM(ROUND(cur * price, 2)), 0)
FROM   r
ORDER  BY 1
