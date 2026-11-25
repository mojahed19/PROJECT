-- كرت العهدة: حركة الصنف في المخزن بين تاريخين بالوحدة الصغرى
--   رصيد أول المدة ، ثم كل حركة معتمدة بالرصيد التراكمي ، ثم الإجمالي والرصيد الختامي
WITH p AS (
  SELECT TO_DATE(:P93_FROM, 'DD/MM/YYYY') d1, TO_DATE(:P93_TO, 'DD/MM/YYYY') d2 FROM dual
),
rows_ AS (
  SELECT t.trans_date, t.trans_no, t.trans_id, l.line_id, t.trans_type, t.description, l.qty_base
  FROM   stock_trans_lines l
  JOIN   stock_trans t ON t.trans_id = l.trans_id AND t.status = 'POSTED'
  CROSS JOIN p
  WHERE  l.item_id = TO_NUMBER(:P93_ITEM_ID)
  AND    l.warehouse_id = TO_NUMBER(:P93_WAREHOUSE_ID)
  AND    l.qty_base <> 0                                   -- تصفير التوالف لا يغيّر الكمية
  AND    t.trans_date < p.d2 + 1
),
op AS (
  SELECT NVL(SUM(r.qty_base), 0) bal FROM rows_ r CROSS JOIN p WHERE r.trans_date < p.d1
),
per AS (
  SELECT r.*,
         (SELECT bal FROM op) + SUM(r.qty_base) OVER (ORDER BY r.trans_date, r.trans_id, r.line_id ROWS UNBOUNDED PRECEDING) run_bal,
         ROW_NUMBER() OVER (ORDER BY r.trans_date, r.trans_id, r.line_id) rn
  FROM   rows_ r CROSS JOIN p
  WHERE  r.trans_date >= p.d1
)
SELECT 0 AS sort_key, TO_CHAR(p.d1, 'DD/MM/YYYY') AS "التاريخ", NULL AS "رقم الحركة", 'رصيد أول المدة' AS "النوع",
       NULL AS "البيان", NULL AS "وارد", NULL AS "صادر", op.bal AS "الرصيد"
FROM   op CROSS JOIN p
UNION ALL
SELECT rn, TO_CHAR(trans_date, 'DD/MM/YYYY'), trans_no,
       DECODE(trans_type, 'RECEIPT','استلام', 'ISSUE','صرف داخلي', 'TRANSFER','تحويل', 'COUNT','تسوية جرد',
                          'INV_OUT','مبيعات', 'INV_IN','مرتجع مبيعات', 'POS','مبيعات', 'OPENING','إشعار إضافة',
                          'PURCHASE','مشتريات', 'DAMAGE','صرف توالف', trans_type),
       description,
       CASE WHEN qty_base > 0 THEN qty_base END,
       CASE WHEN qty_base < 0 THEN -qty_base END,
       run_bal
FROM   per
UNION ALL
SELECT 999999999, TO_CHAR(p.d2, 'DD/MM/YYYY'), NULL, 'الإجمالي والرصيد الختامي', NULL,
       NVL((SELECT SUM(qty_base) FROM per WHERE qty_base > 0), 0),
       NVL((SELECT -SUM(qty_base) FROM per WHERE qty_base < 0), 0),
       op.bal + NVL((SELECT SUM(qty_base) FROM per), 0)
FROM   op CROSS JOIN p
ORDER  BY 1
