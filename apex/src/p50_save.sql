DECLARE
  -- فاتورة مبيعات / مرتجع مبيعات للشركة الأم
  -- العميل: فرع من الشركة (آجل على حساب الفرع) أو عميل خارجي (نقدي: خزينة / تحويل بنكي ، أو آجل على حساب)
  -- رقم الفاتورة أرقام فقط: رمز النوع + السنة + متسلسل 5 أرقام
  --   1 مبيعات نقدية ، 2 مبيعات آجلة ، 5 مرتجع مبيعات نقدي ، 6 مرتجع مبيعات آجل
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();
  l_company NUMBER := :G_PARENT_ID;

  l_id NUMBER; l_type VARCHAR2(10); l_ctype VARCHAR2(10); l_cust NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_pay VARCHAR2(10); l_method VARCHAR2(10); l_acc NUMBER; l_cname VARCHAR2(150);
  l_wh NUMBER; l_pl NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_disc NUMBER; l_desc VARCHAR2(500);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_code VARCHAR2(1); l_seq NUMBER; l_cnt NUMBER;
  l_cb VARCHAR2(1); l_branch VARCHAR2(150);
  l_gross NUMBER := 0; l_net NUMBER; l_lines NUMBER := 0; l_jt VARCHAR2(10); l_sign NUMBER;
  l_jid NUMBER; l_so NUMBER; l_cogs NUMBER; l_base NUMBER; l_line NUMBER := 0;
  l_sales_acc NUMBER; l_ret_acc NUMBER; l_cogs_acc NUMBER; l_inv_acc NUMBER;
  l_shift NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;

  FUNCTION setting (p_code VARCHAR2) RETURN NUMBER IS l NUMBER;
  BEGIN
    SELECT account_id INTO l FROM account_settings WHERE company_id = l_company AND setting_code = p_code;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20010, 'لم يُعرَّف الحساب الافتراضي ' || p_code || ' للشركة الأم');
  END;

  PROCEDURE jline (p_acc NUMBER, p_amt NUMBER, p_base NUMBER, p_partner NUMBER DEFAULT NULL) IS   -- موجب مدين / سالب دائن
  BEGIN
    IF ROUND(NVL(p_base, 0), 2) = 0 THEN RETURN; END IF;
    l_line := l_line + 1;
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, description)
    VALUES (l_jid, l_line, p_acc,
            GREATEST(ROUND(p_amt, 4), 0), GREATEST(-ROUND(p_amt, 4), 0),
            GREATEST(ROUND(p_base, 2), 0), GREATEST(-ROUND(p_base, 2), 0),
            p_partner, l_cname);
  END;
BEGIN
  SELECT h.invoice_id, h.invoice_type, h.customer_type, h.customer_company_id, h.invoice_date,
         h.pay_type, h.pay_method, h.account_id, h.customer_name, h.warehouse_id, h.price_list_id,
         h.currency_code, h.exchange_rate, NVL(h.discount_amount, 0), h.description
  INTO   l_id, l_type, l_ctype, l_cust, l_date_s, l_pay, l_method, l_acc, l_cname, l_wh, l_pl,
         l_cur, l_rate, l_disc, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           invoice_id          NUMBER        PATH '$.INVOICE_ID',
           invoice_type        VARCHAR2(10)  PATH '$.INVOICE_TYPE',
           customer_type       VARCHAR2(10)  PATH '$.CUSTOMER_TYPE',
           customer_company_id NUMBER        PATH '$.CUSTOMER_COMPANY_ID',
           invoice_date        VARCHAR2(20)  PATH '$.INVOICE_DATE',
           pay_type            VARCHAR2(10)  PATH '$.PAY_TYPE',
           pay_method          VARCHAR2(10)  PATH '$.PAY_METHOD',
           account_id          NUMBER        PATH '$.ACCOUNT_ID',
           customer_name       VARCHAR2(150) PATH '$.CUSTOMER_NAME',
           warehouse_id        NUMBER        PATH '$.WAREHOUSE_ID',
           price_list_id       NUMBER        PATH '$.PRICE_LIST_ID',
           currency_code       VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate       NUMBER        PATH '$.EXCHANGE_RATE',
           discount_amount     NUMBER        PATH '$.DISCOUNT_AMOUNT',
           description         VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  ------------------------------------------------------------------ التحقق من الرأس
  IF l_type NOT IN ('SALE','RETURN') OR l_type IS NULL THEN err('نوع الفاتورة غير معروف'); END IF;
  l_jt   := CASE l_type WHEN 'SALE' THEN 'INV' ELSE 'RET' END;
  l_sign := CASE l_type WHEN 'SALE' THEN -1 ELSE 1 END;           -- أثر الكمية على المخزن
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;

  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('ليس لديك صلاحية على فواتير المبيعات'); END IF;
  -- البيع داخل وردية مفتوحة للمستخدم
  SELECT MAX(shift_id) INTO l_shift FROM sales_shifts WHERE user_name = :APP_USER AND status = 'OPEN';
  IF l_shift IS NULL THEN err('افتح وردية أولاً من صفحة الوردية'); END IF;

  -- طريقة الدفع والحساب: نقدي = خزينة أو بنك ، آجل = حساب العميل (خارجي أو فرع)
  -- نوع العميل وطريقة النقد تُستنتج من الحساب المختار
  IF l_pay NOT IN ('CASH','CREDIT') OR l_pay IS NULL THEN err('اختر طريقة الدفع: نقدي أو آجل'); END IF;
  l_cust := NULL;
  BEGIN
    SELECT a.cash_bank, ca.company_id, c.name_ar
    INTO   l_cb, l_cust, l_branch
    FROM   accounts a
    LEFT JOIN company_accounts ca ON ca.ar_account_id = a.account_id
    LEFT JOIN companies c ON c.company_id = ca.company_id
    WHERE  a.account_id = l_acc AND a.is_postable = 'Y' AND a.is_active = 'Y'
    AND    (a.company_id IS NULL OR a.company_id = l_company);
    IF l_pay = 'CASH'   AND l_cb NOT IN ('C','B') THEN err('اختر خزينةاً أو حساباً بنكياً'); END IF;
    IF l_pay = 'CREDIT' AND l_cb <> 'N'           THEN err('اختر حساب العميل'); END IF;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    err(CASE l_pay WHEN 'CASH' THEN 'اختر الخزينة أو الحساب البنكي' ELSE 'اختر حساب العميل' END);
  END;
  l_method := CASE WHEN l_pay = 'CASH' THEN CASE l_cb WHEN 'B' THEN 'BANK' ELSE 'CASH' END END;
  l_ctype  := CASE WHEN l_pay = 'CREDIT' AND l_cust IS NOT NULL THEN 'BRANCH' ELSE 'EXTERNAL' END;
  IF l_ctype = 'EXTERNAL' THEN l_cust := NULL; END IF;
  IF l_ctype = 'BRANCH' AND l_cname IS NULL THEN l_cname := l_branch; END IF;

  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_wh AND company_id = l_company AND is_active = 'Y';
  IF l_cnt = 0 THEN err('اختر مخزناً من مخازن الشركة الأم'); END IF;
  IF l_cur IS NULL OR NVL(l_rate, 0) <= 0 THEN err('العملة أو سعر الصرف غير صحيح'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, invoice_no INTO l_status, l_no FROM invoices WHERE invoice_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('الفاتورة مرحّلة ولا يمكن تعديلها'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الفاتورة غير موجودة'); END;
  END IF;

  ------------------------------------------------------------------ السطور
  FOR r IN (SELECT j.line_no, j.qty, j.price, NVL(j.discount, 0) discount, u.factor
            FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                   line_no NUMBER PATH '$.LINE_NO', item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
                   qty NUMBER PATH '$.QTY', price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT')) j
            LEFT JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id) LOOP
    l_lines := l_lines + 1;
    IF r.factor IS NULL THEN err('السطر ' || r.line_no || ': الصنف أو الوحدة غير صحيحة'); END IF;
    IF NVL(r.qty, 0) <= 0 THEN err('السطر ' || r.line_no || ': الكمية يجب أن تكون أكبر من صفر'); END IF;
    IF NVL(r.price, 0) <= 0 THEN err('السطر ' || r.line_no || ': أدخل سعر البيع'); END IF;
    IF r.discount > NVL(r.qty, 0) * NVL(r.price, 0) THEN err('السطر ' || r.line_no || ': الخصم أكبر من قيمة السطر'); END IF;
    l_gross := l_gross + NVL(r.qty, 0) * NVL(r.price, 0) - r.discount;
  END LOOP;
  IF l_lines = 0 THEN err('أدخل صنفاً واحداً على الأقل'); END IF;
  l_net := l_gross - l_disc;
  IF l_net <= 0 THEN err('صافي الفاتورة يجب أن يكون أكبر من صفر'); END IF;

  -- البيع: الرصيد يجب أن يكفي
  IF l_type = 'SALE' AND l_action = 'POST' THEN
    FOR r IN (SELECT i.item_code, SUM(j.qty * u.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                     item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY')) j
              JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
              JOIN items i ON i.item_id = j.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
              GROUP BY i.item_code) LOOP
      IF r.need > r.bal THEN err('الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي للكمية ' || r.need); END IF;
    END LOOP;
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ------------------------------------------------------------------ الرقم والحفظ
  l_code := CASE WHEN l_type = 'SALE' AND l_pay = 'CASH' THEN '1' WHEN l_type = 'SALE' THEN '2'
                 WHEN l_pay = 'CASH' THEN '5' ELSE '6' END;
  -- إذا تغيّر نوع الدفع في مسودة محفوظة يُعطى رقم جديد من التسلسل الصحيح
  IF l_id IS NULL OR SUBSTR(l_no, 1, 1) <> l_code THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_company AND doc_type = l_code AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_company, l_code, EXTRACT(YEAR FROM l_date), 1); l_seq := 1;
    END IF;
    l_no := l_code || EXTRACT(YEAR FROM l_date) || LPAD(l_seq, 5, '0');
  END IF;

  IF l_id IS NULL THEN
    INSERT INTO invoices (company_id, customer_type, customer_company_id, invoice_type, invoice_no, invoice_date,
                          pay_type, pay_method, account_id, customer_name, warehouse_id, price_list_id,
                          currency_code, exchange_rate, description, created_by, shift_id)
    VALUES (l_company, l_ctype, l_cust, l_type, l_no, l_date, l_pay, l_method, l_acc, l_cname, l_wh, l_pl,
            l_cur, l_rate, l_desc, :APP_USER, l_shift)
    RETURNING invoice_id INTO l_id;
  ELSE
    UPDATE invoices
    SET customer_type = l_ctype, customer_company_id = l_cust, invoice_no = l_no, invoice_date = l_date,
        pay_type = l_pay, pay_method = l_method, account_id = l_acc, customer_name = l_cname,
        warehouse_id = l_wh, price_list_id = l_pl, currency_code = l_cur, exchange_rate = l_rate,
        description = l_desc, shift_id = l_shift
    WHERE invoice_id = l_id;
    DELETE FROM invoice_lines WHERE invoice_id = l_id;
  END IF;

  INSERT INTO invoice_lines (invoice_id, line_no, item_id, unit_id, factor, qty, price, discount, line_total)
  SELECT l_id, ROWNUM, j.item_id, j.unit_id, u.factor, j.qty, j.price, NVL(j.discount, 0),
         ROUND(j.qty * j.price - NVL(j.discount, 0), 4)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
           qty NUMBER PATH '$.QTY', price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT')) j
  JOIN   item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id;

  -- السعر من بيانات الصنف (أو قائمة الأسعار) ولا يُعدَّل يدوياً
  UPDATE invoice_lines il
  SET    price = (SELECT NVL(p.price, CASE WHEN u.unit_id = i.big_unit_id AND i.big_sale_price > 0 THEN i.big_sale_price ELSE NULLIF(i.sale_price, 0) * u.factor END)
                  FROM items i JOIN item_units u ON u.item_id = i.item_id AND u.unit_id = il.unit_id
                  LEFT JOIN price_list_items p ON p.price_list_id = l_pl AND p.item_id = i.item_id AND p.unit_id = il.unit_id
                  WHERE i.item_id = il.item_id)
  WHERE  il.invoice_id = l_id;
  SELECT COUNT(*) INTO l_cnt FROM invoice_lines WHERE invoice_id = l_id AND NVL(price, 0) <= 0;
  IF l_cnt > 0 THEN raise_application_error(-20031, 'يوجد صنف بدون سعر بيع في صفحة الأصناف وأسعارها'); END IF;
  UPDATE invoice_lines SET line_total = ROUND(qty * price - NVL(discount, 0), 4) WHERE invoice_id = l_id;
  SELECT SUM(line_total) INTO l_gross FROM invoice_lines WHERE invoice_id = l_id;
  l_net := l_gross - l_disc;

  UPDATE invoices SET gross_amount = l_gross, discount_amount = l_disc, net_amount = l_net WHERE invoice_id = l_id;

  ------------------------------------------------------------------ الترحيل: المخزون + القيد
  IF l_action = 'POST' THEN
    -- حركة المخزن بمتوسط التكلفة: البيع صادر ، المرتجع وارد
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, counter_account_id,
                             currency_code, exchange_rate, description, source_type, source_id, status, created_by)
    VALUES (l_company, 'INV_OUT', l_no, l_date, l_wh, l_acc, l_cur, 1, l_no, 'INVOICE', l_id, 'POSTED', :APP_USER)
    RETURNING trans_id INTO l_so;

    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT l_so, il.line_no, l_wh, il.item_id, il.unit_id, il.factor, il.qty,
           l_sign * il.qty * il.factor, 0, NVL(b.avg_cost, 0),
           ROUND(l_sign * il.qty * il.factor * NVL(b.avg_cost, 0), 4)
    FROM invoice_lines il
    LEFT JOIN v_stock_balance b ON b.item_id = il.item_id AND b.warehouse_id = l_wh
    WHERE il.invoice_id = l_id;

    SELECT -SUM(value_base) INTO l_cogs FROM stock_trans_lines WHERE trans_id = l_so;   -- موجب في البيع
    -- إيراد المبيعات: الآجلة في SALES_CREDIT ، والنقدية (خزينة أو بنك) في SALES_EXT
    l_sales_acc := setting(CASE WHEN l_ctype = 'BRANCH' THEN 'SALES' WHEN l_pay = 'CREDIT' THEN 'SALES_CREDIT' ELSE 'SALES_EXT' END);
    l_ret_acc   := setting('SALES_RETURN');
    l_cogs_acc  := setting('COGS');
    l_inv_acc   := setting('INVENTORY');
    l_base      := ROUND(l_net * l_rate, 2);

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, status, source_type, source_id, created_by)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate,
            NVL(l_desc, CASE l_type WHEN 'SALE' THEN 'فاتورة مبيعات ' ELSE 'مرتجع مبيعات ' END || l_no || ' - ' || l_cname),
            'DRAFT', 'INVOICE', l_id, :APP_USER)   -- يُرحّل عند اعتماد الوردية
    RETURNING journal_id INTO l_jid;

    IF l_type = 'SALE' THEN
      jline(l_acc,       l_net,  l_base, l_cust);          -- العميل / الخزينة / البنك / ذمة الفرع
      jline(l_sales_acc, -l_net, -l_base, l_cust);         -- المبيعات
      jline(l_cogs_acc,  l_cogs / l_rate,  l_cogs);        -- تكلفة البضاعة المباعة
      jline(l_inv_acc,   -l_cogs / l_rate, -l_cogs);       -- المخزون
    ELSE
      jline(l_ret_acc,   l_net,  l_base, l_cust);          -- مردودات المبيعات
      jline(l_acc,       -l_net, -l_base, l_cust);
      jline(l_inv_acc,   -l_cogs / l_rate, -l_cogs);       -- عودة البضاعة للمخزون (l_cogs سالب هنا)
      jline(l_cogs_acc,  l_cogs / l_rate,  l_cogs);
    END IF;

    UPDATE journals SET total_debit  = (SELECT SUM(debit)  FROM journal_lines WHERE journal_id = l_jid),
                        total_credit = (SELECT SUM(credit) FROM journal_lines WHERE journal_id = l_jid)
    WHERE journal_id = l_jid;

    UPDATE invoices SET status = 'POSTED', journal_id = l_jid, stock_out_id = l_so WHERE invoice_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE); apex_json.write('id', l_id); apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل الفاتورة ' ELSE 'تم حفظ الفاتورة ' END || l_no);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
