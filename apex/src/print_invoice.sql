DECLARE
  -- طباعة فاتورة أو حركة مخزون: __KIND__ = SALE أو PURCHASE أو STOCK ، __SIZE__ = A4 أو 80
  l_kind  VARCHAR2(10) := '__KIND__';
  l_small BOOLEAN      := '__SIZE__' = '80';
  l_id    NUMBER       := :__ITEM__;
  l_title VARCHAR2(100); l_no VARCHAR2(30); l_date DATE; l_party VARCHAR2(300); l_pay VARCHAR2(100);
  l_cur VARCHAR2(3); l_gross NUMBER; l_disc NUMBER; l_net NUMBER; l_status VARCHAR2(10);
  l_ref VARCHAR2(50); l_desc VARCHAR2(500); l_user VARCHAR2(100); l_wh VARCHAR2(100);
  l_party_lbl VARCHAR2(50); l_wh_id NUMBER;

  FUNCTION fn (n NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN TO_CHAR(NVL(n, 0), 'FM999G999G999G990D00'); END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
  -- كمية بدون أصفار زائدة: 5 ، 2.5
  FUNCTION fq (n NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN n = TRUNC(n) THEN TO_CHAR(n, 'FM999G999G999G990')
                ELSE RTRIM(TO_CHAR(n, 'FM999G999G999G990D9999'), '0') END;
  END;
  -- الكمية بالعبوة الكبرى والصغرى: 2 كرتونة و 5 قطعة
  FUNCTION pk (p_item NUMBER, p_unit NUMBER, p_qty NUMBER) RETURN VARCHAR2 IS
    l_base NUMBER; l_bf NUMBER; l_bu NUMBER; l_su NUMBER; l_bn VARCHAR2(100); l_sn VARCHAR2(100); l_b NUMBER; l_s NUMBER;
  BEGIN
    SELECT p_qty * NVL((SELECT u.factor FROM item_units u WHERE u.item_id = p_item AND u.unit_id = p_unit), 1),
           i.big_factor, i.big_unit_id, i.base_unit_id,
           (SELECT name_ar FROM units WHERE unit_id = i.big_unit_id), (SELECT name_ar FROM units WHERE unit_id = i.base_unit_id)
    INTO   l_base, l_bf, l_bu, l_su, l_bn, l_sn
    FROM   items i WHERE i.item_id = p_item;
    IF l_bu IS NULL OR l_bu = l_su OR NVL(l_bf, 1) <= 1 THEN
      RETURN fq(l_base) || ' ' || l_sn;
    END IF;
    l_b := TRUNC(l_base / l_bf);
    l_s := l_base - l_b * l_bf;
    RETURN CASE WHEN l_b <> 0 THEN fq(l_b) || ' ' || l_bn END
        || CASE WHEN l_b <> 0 AND l_s <> 0 THEN ' و ' END
        || CASE WHEN l_s <> 0 OR l_b = 0 THEN fq(l_s) || ' ' || l_sn END;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;
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
    l_party_lbl := 'العميل';
  ELSIF l_kind = 'PURCHASE' THEN
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
    l_party_lbl := 'المورد';
  ELSE
    -- حركة مخزون (إشعار إضافة ، استلام ، صرف ، تحويل ، جرد): القيمة = الكمية × التكلفة
    SELECT CASE t.trans_type WHEN 'OPENING' THEN 'إشعار إضافة - بضاعة أول المدة' WHEN 'RECEIPT' THEN 'استلام بضاعة'
                             WHEN 'ISSUE' THEN 'صرف داخلي' WHEN 'TRANSFER' THEN 'تحويل بين المخازن'
                             WHEN 'COUNT' THEN 'تسوية جرد' WHEN 'DAMAGE' THEN 'فاتورة صرف توالف'
                             WHEN 'DAMAGE_WO' THEN 'تصفير التوالف - قرار المدير' ELSE 'حركة مخزون' END,
           t.trans_no, t.trans_date,
           CASE WHEN t.trans_type = 'TRANSFER' THEN tw.name_ar ELSE a.name_ar END,
           CASE WHEN t.trans_type = 'TRANSFER' THEN 'إلى مخزن' ELSE 'الحساب المقابل' END,
           t.currency_code, t.status, t.description, t.created_by, w.name_ar, t.warehouse_id
    INTO   l_title, l_no, l_date, l_party, l_party_lbl, l_cur, l_status, l_desc, l_user, l_wh, l_wh_id
    FROM   stock_trans t
    JOIN   warehouses w  ON w.warehouse_id  = t.warehouse_id
    LEFT JOIN warehouses tw ON tw.warehouse_id = t.to_warehouse_id
    LEFT JOIN accounts a ON a.account_id = t.counter_account_id
    WHERE  t.trans_id = l_id;
    SELECT NVL(SUM(qty * unit_cost), 0) INTO l_gross FROM stock_trans_lines WHERE trans_id = l_id AND warehouse_id = l_wh_id;
    l_disc := 0; l_net := l_gross;
  END IF;

  htp.p('<div class="inv ' || CASE WHEN l_small THEN 'inv-80' ELSE 'inv-a4' END || '">');
  htp.p('<div class="inv-title">' || e(l_title) || CASE l_status WHEN 'DRAFT' THEN ' <span class="inv-draft">(مسودة)</span>'
                                                               WHEN 'REVERSED' THEN ' <span class="inv-draft">(ملغاة بقيد عكسي)</span>' END || '</div>');

  -- بيانات المستند
  htp.p('<table class="inv-head">');
  htp.p('<tr><th>' || CASE l_kind WHEN 'STOCK' THEN 'الرقم' ELSE 'رقم الفاتورة' END || '</th><td class="inv-no">' || e(l_no) || '</td>'
        || CASE WHEN NOT l_small THEN '<th>التاريخ</th><td>' || TO_CHAR(l_date, 'DD/MM/YYYY') || '</td>' END || '</tr>');
  IF l_small THEN htp.p('<tr><th>التاريخ</th><td>' || TO_CHAR(l_date, 'DD/MM/YYYY') || '</td></tr>'); END IF;
  IF l_party IS NOT NULL THEN
    htp.p('<tr><th>' || e(l_party_lbl) || '</th><td' || CASE WHEN NOT l_small THEN ' colspan="3"' END || '>' || e(l_party) || '</td></tr>');
  END IF;
  IF l_kind <> 'STOCK' THEN
    htp.p('<tr><th>الدفع</th><td' || CASE WHEN NOT l_small THEN '>' || e(l_pay) || '</td><th>العملة</th><td>' || e(l_cur)
                                           ELSE '>' || e(l_pay) END || '</td></tr>');
  END IF;
  IF l_ref IS NOT NULL THEN
    htp.p('<tr><th>رقم فاتورة المورد</th><td' || CASE WHEN NOT l_small THEN ' colspan="3"' END || '>' || e(l_ref) || '</td></tr>');
  END IF;
  IF NOT l_small THEN htp.p('<tr><th>المخزن</th><td colspan="3">' || e(l_wh) || '</td></tr>'); END IF;
  htp.p('</table>');

  -- الأصناف (A4: الكمية بالوحدة المختارة ثم بالعبوة الكبرى والصغرى)
  htp.p('<table class="inv-lines"><thead><tr>');
  IF l_small THEN
    htp.p('<th>الصنف</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th>');
  ELSE
    htp.p('<th>#</th><th>الكود</th><th>الصنف</th><th>الوحدة</th><th>الكمية</th><th>الكمية بالعبوة الكبرى والصغرى</th><th>'
          || CASE l_kind WHEN 'STOCK' THEN 'التكلفة' ELSE 'السعر' END || '</th>'
          || CASE WHEN l_kind <> 'STOCK' THEN '<th>الخصم</th>' END || '<th>الإجمالي</th>');
  END IF;
  htp.p('</tr></thead><tbody>');
  FOR r IN (SELECT l.line_no, l.item_id, l.unit_id, it.item_code, it.name_ar item_name, u.name_ar unit_name,
                   l.qty, l.price, l.discount, l.line_total
            FROM   invoice_lines l JOIN items it ON it.item_id = l.item_id JOIN units u ON u.unit_id = l.unit_id
            WHERE  l_kind = 'SALE' AND l.invoice_id = l_id
            UNION ALL
            SELECT l.line_no, l.item_id, l.unit_id, it.item_code, it.name_ar, u.name_ar, l.qty, l.price, l.discount, l.line_total
            FROM   purchase_invoice_lines l JOIN items it ON it.item_id = l.item_id JOIN units u ON u.unit_id = l.unit_id
            WHERE  l_kind = 'PURCHASE' AND l.pinv_id = l_id
            UNION ALL
            SELECT l.line_no, l.item_id, l.unit_id, it.item_code, it.name_ar, u.name_ar, l.qty, l.unit_cost, 0, l.qty * l.unit_cost
            FROM   stock_trans_lines l JOIN items it ON it.item_id = l.item_id JOIN units u ON u.unit_id = l.unit_id
            WHERE  l_kind = 'STOCK' AND l.trans_id = l_id AND l.warehouse_id = l_wh_id
            ORDER BY 1) LOOP
    IF l_small THEN
      htp.p('<tr><td>' || e(r.item_name) || '<br><small>' || e(r.unit_name) || '</small></td><td class="n">'
            || fn(r.qty) || '</td><td class="n">' || fn(r.price) || '</td><td class="n">' || fn(r.line_total) || '</td></tr>');
    ELSE
      htp.p('<tr><td class="c">' || r.line_no || '</td><td>' || e(r.item_code) || '</td><td>' || e(r.item_name) || '</td><td>'
            || e(r.unit_name) || '</td><td class="n">' || fq(r.qty) || '</td><td>' || e(pk(r.item_id, r.unit_id, r.qty))
            || '</td><td class="n">' || fn(r.price) || '</td>'
            || CASE WHEN l_kind <> 'STOCK' THEN '<td class="n">' || CASE WHEN r.discount <> 0 THEN fn(r.discount) END || '</td>' END
            || '<td class="n">' || fn(r.line_total) || '</td></tr>');
    END IF;
  END LOOP;
  htp.p('</tbody></table>');

  -- الإجماليات
  htp.p('<table class="inv-totals">');
  IF l_kind = 'STOCK' THEN
    htp.p('<tr class="inv-net"><th>إجمالي القيمة</th><td class="n">' || fn(l_net) || ' ' || e(l_cur) || '</td></tr>');
  ELSE
    htp.p('<tr><th>الإجمالي</th><td class="n">' || fn(l_gross) || '</td></tr>');
    IF NVL(l_disc, 0) <> 0 THEN htp.p('<tr><th>الخصم</th><td class="n">' || fn(l_disc) || '</td></tr>'); END IF;
    htp.p('<tr class="inv-net"><th>الصافي</th><td class="n">' || fn(l_net) || ' ' || e(l_cur) || '</td></tr>');
  END IF;
  htp.p('</table>');

  IF l_desc IS NOT NULL THEN htp.p('<div class="inv-desc">البيان: ' || e(l_desc) || '</div>'); END IF;

  IF l_small THEN
    htp.p('<div class="inv-foot">المستخدم: ' || e(l_user) || '<br>' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '<br>شكراً لتعاملكم معنا</div>');
  ELSE
    htp.p('<table class="inv-sign"><tr><td>المحاسب<br><br>..................</td><td>أمين المخزن<br><br>..................</td><td>'
          || CASE l_kind WHEN 'SALE' THEN 'المستلم' WHEN 'PURCHASE' THEN 'المورد' ELSE 'المعتمد' END || '<br><br>..................</td></tr></table>');
    htp.p('<div class="inv-foot">طُبعت بواسطة ' || e(:APP_USER) || ' في ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '</div>');
  END IF;
  htp.p('</div>');
EXCEPTION WHEN NO_DATA_FOUND THEN
  htp.p('<p>المستند غير موجود</p>');
END;
