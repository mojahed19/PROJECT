WITH ln AS (
  -- سطور الفواتير المرحّلة: صافي القيمة بالعملة الأساسية بعد توزيع خصم الفاتورة على سطورها بالنسبة
  SELECT i.invoice_id, i.invoice_type, i.stock_out_id, l.item_id,
         CASE WHEN i.pay_type = 'CREDIT' OR i.customer_type = 'BRANCH' THEN a.name_ar
              ELSE NVL(i.customer_name, 'عملاء نقدي') END AS customer,
         SUM(l.qty * l.factor) AS qty_base,
         SUM(l.line_total) * CASE WHEN i.gross_amount > 0 THEN i.net_amount / i.gross_amount ELSE 1 END * i.exchange_rate AS amt
  FROM   invoices i
  JOIN   invoice_lines l ON l.invoice_id = i.invoice_id
  JOIN   accounts a ON a.account_id = i.account_id
  WHERE  i.status = 'POSTED'
  AND    i.invoice_date BETWEEN TO_DATE(:P89_FROM, 'DD/MM/YYYY') AND TO_DATE(:P89_TO, 'DD/MM/YYYY')
  AND    (:P89_WAREHOUSE_ID IS NULL OR i.warehouse_id = :P89_WAREHOUSE_ID)
  AND    (:P89_PAY IS NULL OR i.pay_type = :P89_PAY)
  GROUP  BY i.invoice_id, i.invoice_type, i.stock_out_id, l.item_id, i.pay_type, i.customer_type, a.name_ar, i.customer_name,
            i.gross_amount, i.net_amount, i.exchange_rate
),
cost AS (
  -- تكلفة كل صنف في حركة المخزون الناتجة عن الفاتورة (البيع صادر بقيمة سالبة ، المرتجع وارد بقيمة موجبة)
  SELECT trans_id, item_id, -SUM(value_base) AS cost FROM stock_trans_lines GROUP BY trans_id, item_id
),
x AS (
  SELECT CASE WHEN :P89_GROUP IN ('ITEM', 'ITEM_CUSTOMER') THEN it.item_code || ' - ' || it.name_ar END AS item,
         CASE WHEN :P89_GROUP IN ('CUSTOMER', 'ITEM_CUSTOMER') THEN ln.customer END AS customer,
         CASE WHEN :P89_GROUP IN ('ITEM', 'ITEM_CUSTOMER') THEN u.name_ar END AS unit,
         ln.invoice_id, ln.invoice_type,
         CASE ln.invoice_type WHEN 'SALE' THEN ln.qty_base ELSE -ln.qty_base END AS qty,
         CASE ln.invoice_type WHEN 'SALE' THEN ln.amt ELSE 0 END AS sales,
         CASE ln.invoice_type WHEN 'RETURN' THEN ln.amt ELSE 0 END AS returns,
         NVL(c.cost, 0) AS cost
  FROM   ln
  JOIN   items it ON it.item_id = ln.item_id
  JOIN   units u ON u.unit_id = it.base_unit_id
  LEFT JOIN cost c ON c.trans_id = ln.stock_out_id AND c.item_id = ln.item_id
),
g AS (
  SELECT item, customer, unit,
         COUNT(DISTINCT invoice_id) AS docs,
         SUM(qty) AS qty, SUM(sales) AS sales, SUM(returns) AS returns,
         SUM(sales) - SUM(returns) AS net, SUM(cost) AS cost,
         SUM(sales) - SUM(returns) - SUM(cost) AS profit
  FROM   x
  GROUP  BY item, customer, unit
)
SELECT '1' || NVL(item, ' ') || NVL(customer, ' ') AS sort_key,
       item AS "الصنف", customer AS "العميل",
       docs AS "عدد الفواتير", qty AS "الكمية", unit AS "الوحدة الصغرى",
       ROUND(sales, 2) AS "المبيعات", ROUND(returns, 2) AS "المرتجعات", ROUND(net, 2) AS "صافي المبيعات",
       ROUND(cost, 2) AS "التكلفة", ROUND(profit, 2) AS "الربح",
       CASE WHEN net <> 0 THEN ROUND(100 * profit / net, 1) END AS "هامش الربح %"
FROM   g
UNION ALL
SELECT '2', 'الإجمالي', NULL, NULL, NULL, NULL,
       ROUND(SUM(sales), 2), ROUND(SUM(returns), 2), ROUND(SUM(net), 2), ROUND(SUM(cost), 2), ROUND(SUM(profit), 2),
       CASE WHEN SUM(net) <> 0 THEN ROUND(100 * SUM(profit) / SUM(net), 1) END
FROM   g
HAVING COUNT(*) > 0
ORDER  BY 1
