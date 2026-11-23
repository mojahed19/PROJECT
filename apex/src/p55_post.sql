DECLARE
  -- ترحيل فاتورة المشتريات عند اعتمادها: فحص الرصيد للمرتجع ثم حركة المخزون والقيد
  p purchase_invoices%ROWTYPE;
  l_pid NUMBER; l_type VARCHAR2(10); l_company NUMBER; l_date DATE; l_sup_no VARCHAR2(50); l_acc NUMBER;
  l_sup_name VARCHAR2(150); l_wh NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_desc VARCHAR2(500);
  l_no VARCHAR2(30); l_net NUMBER; l_gross NUMBER; l_jt VARCHAR2(10); l_sign NUMBER;
  l_st NUMBER; l_jid NUMBER; l_inv NUMBER; l_base NUMBER;
BEGIN
  SELECT * INTO p FROM purchase_invoices WHERE pinv_id = l_id;
  l_pid := p.pinv_id; l_type := p.invoice_type; l_company := p.company_id; l_date := p.invoice_date;
  l_sup_no := p.supplier_inv_no; l_acc := p.supplier_account_id; l_sup_name := p.supplier_name;
  l_wh := p.warehouse_id; l_cur := p.currency_code; l_rate := p.exchange_rate; l_desc := p.description;
  l_no := p.invoice_no; l_net := p.net_amount; l_gross := p.gross_amount;
  l_jt := CASE l_type WHEN 'PURCHASE' THEN 'PUR' ELSE 'PRT' END;
  l_sign := CASE l_type WHEN 'PURCHASE' THEN 1 ELSE -1 END;
  IF l_type = 'RETURN' THEN
    FOR r IN (SELECT i.item_code, SUM(l.qty * l.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM purchase_invoice_lines l JOIN items i ON i.item_id = l.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = l.item_id AND b.warehouse_id = l_wh
              WHERE l.pinv_id = l_pid GROUP BY i.item_code) LOOP
      IF r.need > r.bal THEN raise_application_error(-20032, 'الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي للمرتجع'); END IF;
    END LOOP;
  END IF;
    -- حركة المخزون: تكلفة الوحدة الأساسية = (إجمالي السطر بعد توزيع خصم الفاتورة) × سعر الصرف ÷ الكمية الأساسية
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, counter_account_id,
                             currency_code, exchange_rate, description, source_type, source_id, status, created_by)
    VALUES (l_company, 'PURCHASE', l_no, l_date, l_wh, l_acc, l_cur, l_rate,
            NVL(l_desc, l_no), 'PURCHASE', l_pid, 'POSTED', :APP_USER)
    RETURNING trans_id INTO l_st;

    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT l_st, l.line_no, l_wh, l.item_id, l.unit_id, l.factor, l.qty,
           l_sign * l.qty * l.factor, l.price,
           l.line_total * (l_net / l_gross) * l_rate / (l.qty * l.factor),
           ROUND(l_sign * l.line_total * (l_net / l_gross) * l_rate, 4)
    FROM purchase_invoice_lines l WHERE l.pinv_id = l_pid;

    -- القيد: مشتريات = مدين المخزون / دائن المورد ، والمرتجع بالعكس
    BEGIN
      SELECT account_id INTO l_inv FROM account_settings WHERE company_id = l_company AND setting_code = 'INVENTORY';
    EXCEPTION WHEN NO_DATA_FOUND THEN
      raise_application_error(-20060, 'لم يُعرَّف حساب المخزون (INVENTORY) لهذه الشركة');
    END;
    l_base := ROUND(l_net * l_rate, 2);

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, source_id, total_debit, total_credit,
                          created_by, posted_by, posted_on)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate,
            NVL(l_desc, CASE l_type WHEN 'PURCHASE' THEN 'فاتورة مشتريات ' ELSE 'مرتجع مشتريات ' END || l_no || ' - ' || l_sup_name),
            l_sup_no, 'POSTED', 'PURCHASE', l_pid, l_net, l_net, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_jid;

    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 1, CASE l_type WHEN 'PURCHASE' THEN l_inv ELSE l_acc END, l_net, 0, l_base, 0, l_sup_name);
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 2, CASE l_type WHEN 'PURCHASE' THEN l_acc ELSE l_inv END, 0, l_net, 0, l_base, l_sup_name);

    UPDATE purchase_invoices SET status = 'POSTED', journal_id = l_jid, stock_trans_id = l_st WHERE pinv_id = l_pid;
END;
