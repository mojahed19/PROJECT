DECLARE
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type VARCHAR2(10); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_sup_no VARCHAR2(50); l_pay VARCHAR2(10); l_method VARCHAR2(10); l_acc NUMBER; l_sup_name VARCHAR2(150);
  l_code VARCHAR2(1);
  l_wh NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_disc NUMBER; l_desc VARCHAR2(500);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER; l_lines NUMBER := 0;
  l_gross NUMBER := 0; l_net NUMBER; l_jt VARCHAR2(10); l_sign NUMBER;
  l_st NUMBER; l_jid NUMBER; l_inv NUMBER; l_base NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  l_action := 'DRAFT';   -- الترحيل يتم عند الاعتماد
  SELECT h.pinv_id, h.invoice_type, h.company_id, h.invoice_date, h.supplier_inv_no, h.pay_type, h.pay_method,
         h.supplier_account_id, h.supplier_name, h.warehouse_id, h.currency_code, h.exchange_rate,
         NVL(h.discount_amount, 0), h.description
  INTO   l_id, l_type, l_company, l_date_s, l_sup_no, l_pay, l_method, l_acc, l_sup_name, l_wh, l_cur, l_rate, l_disc, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           pinv_id             NUMBER        PATH '$.PINV_ID',
           invoice_type        VARCHAR2(10)  PATH '$.INVOICE_TYPE',
           company_id          NUMBER        PATH '$.COMPANY_ID',
           invoice_date        VARCHAR2(20)  PATH '$.INVOICE_DATE',
           supplier_inv_no     VARCHAR2(50)  PATH '$.SUPPLIER_INV_NO',
           pay_type            VARCHAR2(10)  PATH '$.PAY_TYPE',
           pay_method          VARCHAR2(10)  PATH '$.PAY_METHOD',
           supplier_account_id NUMBER        PATH '$.SUPPLIER_ACCOUNT_ID',
           supplier_name       VARCHAR2(150) PATH '$.SUPPLIER_NAME',
           warehouse_id        NUMBER        PATH '$.WAREHOUSE_ID',
           currency_code       VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate       NUMBER        PATH '$.EXCHANGE_RATE',
           discount_amount     NUMBER        PATH '$.DISCOUNT_AMOUNT',
           description         VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  l_jt   := CASE l_type WHEN 'PURCHASE' THEN 'PUR' WHEN 'RETURN' THEN 'PRT' END;
  l_sign := CASE l_type WHEN 'PURCHASE' THEN 1 ELSE -1 END;          -- أثر الكمية على المخزن
  IF l_jt IS NULL THEN err('نوع الفاتورة غير معروف'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;

  -- المشتريات للشركة الأم فقط
  l_company := :G_PARENT_ID;
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('ليس لديك صلاحية على فواتير المشتريات'); END IF;
  IF l_pay NOT IN ('CASH','CREDIT') OR l_pay IS NULL THEN err('اختر طريقة الدفع'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_wh AND company_id = l_company AND is_active = 'Y';
  IF l_cnt = 0 THEN err('اختر مخزناً تابعاً للشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM accounts
  WHERE account_id = l_acc AND is_postable = 'Y' AND is_active = 'Y'
  AND (company_id IS NULL OR company_id = l_company)
  AND (l_pay = 'CREDIT' AND cash_bank = 'N' OR l_pay = 'CASH' AND cash_bank IN ('C','B'));
  IF l_cnt = 0 THEN
    err(CASE WHEN l_pay = 'CREDIT' THEN 'اختر حساب المورد' ELSE 'اختر الخزينة أو الحساب البنكي' END);
  END IF;
  -- طريقة النقد تُستنتج من الحساب: بنك أو خزينة
  BEGIN
    SELECT CASE cash_bank WHEN 'B' THEN 'BANK' WHEN 'C' THEN 'CASH' END INTO l_method FROM accounts WHERE account_id = l_acc;
  EXCEPTION WHEN NO_DATA_FOUND THEN l_method := NULL;
  END;
  IF l_pay = 'CREDIT' THEN l_method := NULL; END IF;

  IF l_cur IS NULL OR NVL(l_rate, 0) <= 0 THEN err('العملة أو سعر الصرف غير صحيح'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  -- رقم فاتورة المورد لا يتكرر لنفس المورد
  IF l_sup_no IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM purchase_invoices
    WHERE company_id = l_company AND supplier_account_id = l_acc AND invoice_type = l_type
    AND UPPER(supplier_inv_no) = UPPER(l_sup_no) AND status <> 'REVERSED'
    AND pinv_id <> NVL(l_id, -1);
    IF l_cnt > 0 THEN err('رقم فاتورة المورد ' || l_sup_no || ' مسجل من قبل لنفس المورد'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, invoice_no INTO l_status, l_no FROM purchase_invoices WHERE pinv_id = l_id FOR UPDATE;
      IF l_status NOT IN ('DRAFT','RETURNED') THEN err('الفاتورة ' || l_no || ' تمت مراجعتها أو اعتمادها ولا يمكن تعديلها'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الفاتورة غير موجودة'); END;
  END IF;

  FOR r IN (SELECT j.line_no, j.item_id, j.unit_id, j.qty, j.price, NVL(j.discount, 0) discount, u.factor
            FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                   line_no NUMBER PATH '$.LINE_NO', item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
                   qty NUMBER PATH '$.QTY', price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT')) j
            LEFT JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id) LOOP
    l_lines := l_lines + 1;
    IF r.factor IS NULL THEN err('السطر ' || r.line_no || ': الصنف أو الوحدة غير صحيحة'); END IF;
    IF NVL(r.qty, 0) <= 0 THEN err('السطر ' || r.line_no || ': الكمية يجب أن تكون أكبر من صفر'); END IF;
    IF NVL(r.price, 0) <= 0 THEN err('السطر ' || r.line_no || ': أدخل سعر الشراء'); END IF;
    IF r.discount > NVL(r.qty, 0) * NVL(r.price, 0) THEN err('السطر ' || r.line_no || ': الخصم أكبر من قيمة السطر'); END IF;
    l_gross := l_gross + NVL(r.qty, 0) * NVL(r.price, 0) - r.discount;
  END LOOP;
  IF l_lines = 0 THEN err('أدخل صنفاً واحداً على الأقل'); END IF;
  l_net := l_gross - l_disc;
  IF l_net <= 0 THEN err('صافي الفاتورة يجب أن يكون أكبر من صفر'); END IF;

  -- مرتجع المشتريات: الرصيد يجب أن يكفي
  IF l_type = 'RETURN' AND l_action = 'POST' THEN
    FOR r IN (SELECT i.item_code, SUM(j.qty * u.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                     item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY')) j
              JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
              JOIN items i ON i.item_id = j.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
              GROUP BY i.item_code) LOOP
      IF r.need > r.bal THEN err('الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي'); END IF;
    END LOOP;
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ------------------------------------------------------------------ الحفظ
  -- الرقم أرقام فقط: 3 مشتريات نقدية ، 4 مشتريات آجلة ، 7 مرتجع نقدي ، 8 مرتجع آجل + السنة + متسلسل 5 أرقام
  l_code := CASE WHEN l_type = 'PURCHASE' AND l_pay = 'CASH' THEN '3' WHEN l_type = 'PURCHASE' THEN '4'
                 WHEN l_pay = 'CASH' THEN '7' ELSE '8' END;
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

    INSERT INTO purchase_invoices (company_id, invoice_type, invoice_no, supplier_inv_no, invoice_date, pay_type, pay_method,
                                   supplier_account_id, supplier_name, warehouse_id, currency_code, exchange_rate,
                                   description, created_by)
    VALUES (l_company, l_type, l_no, l_sup_no, l_date, l_pay, l_method, l_acc, l_sup_name, l_wh, l_cur, l_rate, l_desc, :APP_USER)
    RETURNING pinv_id INTO l_id;
  ELSE
    UPDATE purchase_invoices
    SET company_id = l_company, invoice_no = l_no, supplier_inv_no = l_sup_no, invoice_date = l_date, pay_type = l_pay, pay_method = l_method,
        supplier_account_id = l_acc, supplier_name = l_sup_name, warehouse_id = l_wh,
        currency_code = l_cur, exchange_rate = l_rate, description = l_desc
    WHERE pinv_id = l_id;
    DELETE FROM purchase_invoice_lines WHERE pinv_id = l_id;
  END IF;

  INSERT INTO purchase_invoice_lines (pinv_id, line_no, item_id, unit_id, factor, qty, price, discount, line_total)
  SELECT l_id, ROWNUM, j.item_id, j.unit_id, u.factor, j.qty, j.price, NVL(j.discount, 0),
         ROUND(j.qty * j.price - NVL(j.discount, 0), 4)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
           qty NUMBER PATH '$.QTY', price NUMBER PATH '$.PRICE', discount NUMBER PATH '$.DISCOUNT')) j
  JOIN   item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id;

  -- سعر الشراء من بيانات الصنف ولا يُعدَّل يدوياً
  UPDATE purchase_invoice_lines il
  SET    price = (SELECT CASE WHEN u.unit_id = i.big_unit_id AND i.big_purchase_price > 0 THEN i.big_purchase_price ELSE NULLIF(i.purchase_price, 0) * u.factor END
                  FROM items i JOIN item_units u ON u.item_id = i.item_id AND u.unit_id = il.unit_id
                  WHERE i.item_id = il.item_id)
  WHERE  il.pinv_id = l_id;
  SELECT COUNT(*) INTO l_cnt FROM purchase_invoice_lines WHERE pinv_id = l_id AND NVL(price, 0) <= 0;
  IF l_cnt > 0 THEN raise_application_error(-20031, 'يوجد صنف بدون سعر شراء في صفحة الأصناف وأسعارها'); END IF;
  UPDATE purchase_invoice_lines SET line_total = ROUND(qty * price - NVL(discount, 0), 4) WHERE pinv_id = l_id;
  SELECT SUM(line_total) INTO l_gross FROM purchase_invoice_lines WHERE pinv_id = l_id;
  l_net := l_gross - l_disc;

  UPDATE purchase_invoices SET gross_amount = l_gross, discount_amount = l_disc, net_amount = l_net,
         status = 'DRAFT', return_note = NULL
  WHERE pinv_id = l_id;

  ------------------------------------------------------------------ الترحيل: المخزون + القيد
  IF l_action = 'POST' THEN
    -- حركة المخزون: تكلفة الوحدة الأساسية = (إجمالي السطر بعد توزيع خصم الفاتورة) × سعر الصرف ÷ الكمية الأساسية
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, counter_account_id,
                             currency_code, exchange_rate, description, source_type, source_id, status, created_by)
    VALUES (l_company, 'PURCHASE', l_no, l_date, l_wh, l_acc, l_cur, l_rate,
            NVL(l_desc, l_no), 'PURCHASE', l_id, 'POSTED', :APP_USER)
    RETURNING trans_id INTO l_st;

    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT l_st, l.line_no, l_wh, l.item_id, l.unit_id, l.factor, l.qty,
           l_sign * l.qty * l.factor, l.price,
           l.line_total * (l_net / l_gross) * l_rate / (l.qty * l.factor),
           ROUND(l_sign * l.line_total * (l_net / l_gross) * l_rate, 4)
    FROM purchase_invoice_lines l WHERE l.pinv_id = l_id;

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
            l_sup_no, 'POSTED', 'PURCHASE', l_id, l_net, l_net, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_jid;

    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 1, CASE l_type WHEN 'PURCHASE' THEN l_inv ELSE l_acc END, l_net, 0, l_base, 0, l_sup_name);
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 2, CASE l_type WHEN 'PURCHASE' THEN l_acc ELSE l_inv END, 0, l_net, 0, l_base, l_sup_name);

    UPDATE purchase_invoices SET status = 'POSTED', journal_id = l_jid, stock_trans_id = l_st WHERE pinv_id = l_id;
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
