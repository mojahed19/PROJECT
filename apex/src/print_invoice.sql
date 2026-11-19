DECLARE
  -- طباعة فاتورة: __KIND__ = SALE أو PURCHASE ، __SIZE__ = A4 أو 80
  l_kind  VARCHAR2(10) := '__KIND__';
  l_small BOOLEAN      := '__SIZE__' = '80';
  l_id    NUMBER       := :__ITEM__;
  l_title VARCHAR2(100); l_no VARCHAR2(30); l_date DATE; l_party VARCHAR2(300); l_pay VARCHAR2(100);
  l_cur VARCHAR2(3); l_gross NUMBER; l_disc NUMBER; l_net NUMBER; l_status VARCHAR2(10);
  l_ref VARCHAR2(50); l_desc VARCHAR2(500); l_user VARCHAR2(100); l_wh VARCHAR2(100);

  FUNCTION fn (n NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN TO_CHAR(NVL(n, 0), 'FM999G999G999G990D00'); END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
BEGIN
  IF l_kind = 'SALE' THEN
    SELECT DECODE(i.invoice_type, 'SALE', 'فاتورة مبيعات', 'مرتجع مبيعات')
           || CASE WHEN i.pay_type = 'CASH' THEN ' نقدية' ELSE ' آجلة' END,
           i.invoice_no, i.invoice_date,
           CASE i.customer_type WHEN 'BRANCH' THEN c.name_ar ELSE NVL(i.customer_name, a.name_ar) END,
           CASE WHEN i.pay_type = 'CREDIT' THEN 'آجل - ' || a.name_ar
                WHEN i.pay_method = 'BANK' THEN 'تحويل بنكي - ' || a.name_ar ELSE 'نقداً' END,
           i.currency_code, i.gross_amount, i.discount_amount, i.net_amount, i.status, NULL, i.description,
           i.created_by, w.name_ar
    INTO   l_title, l_no, l_date, l_party, l_pay, l_cur, l_gross, l_disc, l_net, l_status, l_ref, l_desc, l_user, l_wh
    FROM   invoices i
    LEFT JOIN companies c ON c.company_id = i.customer_company_id
    LEFT JOIN accounts  a ON a.account_id = i.account_id
    JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
    WHERE  i.invoice_id = l_id;
  ELSE
    SELECT DECODE(p.invoice_type, 'PURCHASE', 'فاتورة مشتريات', 'مرتجع مشتريات')
           || CASE WHEN p.pay_type = 'CASH' THEN ' نقدية' ELSE ' آجلة' END,
           p.invoice_no, p.invoice_date, NVL(p.supplier_name, a.name_ar),
           CASE WHEN p.pay_type = 'CREDIT' THEN 'آجل - ' || a.name_ar
                WHEN p.pay_method = 'BANK' THEN 'تحويل بنكي - ' || a.name_ar ELSE 'نقداً' END,
           p.currency_code, p.gross_amount, p.discount_amount, p.net_amount, p.status, p.supplier_inv_no,
           p.description, p.created_by, w.name_ar
    INTO   l_title, l_no, l_date, l_party, l_pay, l_cur, l_gross, l_disc, l_net, l_status, l_ref, l_desc, l_user, l_wh
    FROM   purchase_invoices p
    JOIN   accounts a ON a.account_id = p.supplier_account_id
    JOIN   warehouses w ON w.warehouse_id = p.warehouse_id
    WHERE  p.pinv_id = l_id;
  END IF;

  htp.p('<div class="inv ' || CASE WHEN l_small THEN 'inv-80' ELSE 'inv-a4' END || '">');
  htp.p('<div class="inv-title">' || e(l_title) || CASE l_status WHEN 'DRAFT' THEN ' <span class="inv-draft">(مسودة)</span>'
                                                               WHEN 'REVERSED' THEN ' <span class="inv-draft">(ملغاة بقيد عكسي)</span>' END || '</div>');

  -- بيانات الفاتورة
  htp.p('<table class="inv-head">');
  htp.p('<tr><th>رقم الفاتورة</th><td class="inv-no">' || e(l_no) || '</td>'
        || CASE WHEN NOT l_small THEN '<th>التاريخ</th><td>' || TO_CHAR(l_date, 'DD/MM/YYYY') || '</td>' END || '</tr>');
  IF l_small THEN htp.p('<tr><th>التاريخ</th><td>' || TO_CHAR(l_date, 'DD/MM/YYYY') || '</td></tr>'); END IF;
  htp.p('<tr><th>' || CASE l_kind WHEN 'SALE' THEN 'العميل' ELSE 'المورد' END || '</th><td'
        || CASE WHEN NOT l_small THEN ' colspan="3"' END || '>' || e(l_party) || '</td></tr>');
  htp.p('<tr><th>الدفع</th><td' || CASE WHEN NOT l_small THEN '>' || e(l_pay) || '</td><th>العملة</th><td>' || e(l_cur)
                                         ELSE '>' || e(l_pay) END || '</td></tr>');
  IF l_ref IS NOT NULL THEN
    htp.p('<tr><th>رقم فاتورة المورد</th><td' || CASE WHEN NOT l_small THEN ' colspan="3"' END || '>' || e(l_ref) || '</td></tr>');
  END IF;
  IF NOT l_small THEN htp.p('<tr><th>المخزن</th><td colspan="3">' || e(l_wh) || '</td></tr>'); END IF;
  htp.p('</table>');

  -- الأصناف
  htp.p('<table class="inv-lines"><thead><tr>');
  IF l_small THEN
    htp.p('<th>الصنف</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th>');
  ELSE
    htp.p('<th>#</th><th>الكود</th><th>الصنف</th><th>الوحدة</th><th>الكمية</th><th>السعر</th><th>الخصم</th><th>الإجمالي</th>');
  END IF;
  htp.p('</tr></thead><tbody>');
  FOR r IN (SELECT l.line_no, it.item_code, it.name_ar item_name, u.name_ar unit_name, l.qty, l.price, l.discount, l.line_total
            FROM   invoice_lines l JOIN items it ON it.item_id = l.item_id JOIN units u ON u.unit_id = l.unit_id
            WHERE  l_kind = 'SALE' AND l.invoice_id = l_id
            UNION ALL
            SELECT l.line_no, it.item_code, it.name_ar, u.name_ar, l.qty, l.price, l.discount, l.line_total
            FROM   purchase_invoice_lines l JOIN items it ON it.item_id = l.item_id JOIN units u ON u.unit_id = l.unit_id
            WHERE  l_kind = 'PURCHASE' AND l.pinv_id = l_id
            ORDER BY 1) LOOP
    IF l_small THEN
      htp.p('<tr><td>' || e(r.item_name) || '<br><small>' || e(r.unit_name) || '</small></td><td class="n">'
            || fn(r.qty) || '</td><td class="n">' || fn(r.price) || '</td><td class="n">' || fn(r.line_total) || '</td></tr>');
    ELSE
      htp.p('<tr><td class="c">' || r.line_no || '</td><td>' || e(r.item_code) || '</td><td>' || e(r.item_name) || '</td><td>'
            || e(r.unit_name) || '</td><td class="n">' || fn(r.qty) || '</td><td class="n">' || fn(r.price)
            || '</td><td class="n">' || CASE WHEN r.discount <> 0 THEN fn(r.discount) END || '</td><td class="n">'
            || fn(r.line_total) || '</td></tr>');
    END IF;
  END LOOP;
  htp.p('</tbody></table>');

  -- الإجماليات
  htp.p('<table class="inv-totals">');
  htp.p('<tr><th>الإجمالي</th><td class="n">' || fn(l_gross) || '</td></tr>');
  IF NVL(l_disc, 0) <> 0 THEN htp.p('<tr><th>الخصم</th><td class="n">' || fn(l_disc) || '</td></tr>'); END IF;
  htp.p('<tr class="inv-net"><th>الصافي</th><td class="n">' || fn(l_net) || ' ' || e(l_cur) || '</td></tr>');
  htp.p('</table>');

  IF l_desc IS NOT NULL THEN htp.p('<div class="inv-desc">البيان: ' || e(l_desc) || '</div>'); END IF;

  IF l_small THEN
    htp.p('<div class="inv-foot">المستخدم: ' || e(l_user) || '<br>' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '<br>شكراً لتعاملكم معنا</div>');
  ELSE
    htp.p('<table class="inv-sign"><tr><td>المحاسب<br><br>..................</td><td>أمين المخزن<br><br>..................</td><td>'
          || CASE l_kind WHEN 'SALE' THEN 'المستلم' ELSE 'المورد' END || '<br><br>..................</td></tr></table>');
    htp.p('<div class="inv-foot">طُبعت بواسطة ' || e(l_user) || ' في ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '</div>');
  END IF;
  htp.p('</div>');
EXCEPTION WHEN NO_DATA_FOUND THEN
  htp.p('<p>الفاتورة غير موجودة</p>');
END;
