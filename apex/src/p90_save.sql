DECLARE
  l_clob   CLOB := apex_application.g_clob_01;
  l_action VARCHAR2(10) := apex_application.g_x01;
  l_errs   apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type VARCHAR2(10); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_wh NUMBER; l_to_wh NUMBER; l_counter NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_desc VARCHAR2(500);
  l_base_cur VARCHAR2(3);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER; l_lines NUMBER := 0;
  l_jid NUMBER; l_val NUMBER; l_inv NUMBER; l_adj NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;

  FUNCTION setting (p_code VARCHAR2) RETURN NUMBER IS l NUMBER;
  BEGIN
    SELECT account_id INTO l FROM account_settings WHERE company_id = l_company AND setting_code = p_code;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20010, 'لم يُعرَّف الحساب الافتراضي ' || p_code);
  END;

  PROCEDURE jline (p_no NUMBER, p_acc NUMBER, p_amount NUMBER) IS   -- موجب = مدين ، سالب = دائن
  BEGIN
    IF ROUND(p_amount, 2) = 0 THEN RETURN; END IF;
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, p_no, p_acc,
            GREATEST(ROUND(p_amount, 2), 0), GREATEST(-ROUND(p_amount, 2), 0),
            GREATEST(ROUND(p_amount, 2), 0), GREATEST(-ROUND(p_amount, 2), 0), l_desc);
  END;
BEGIN
  l_action := 'DRAFT';   -- الترحيل يتم عند الاعتماد
  SELECT h.trans_id, h.trans_type, h.company_id, h.trans_date, h.warehouse_id, h.to_warehouse_id,
         h.counter_account_id, h.currency_code, h.exchange_rate, h.description
  INTO   l_id, l_type, l_company, l_date_s, l_wh, l_to_wh, l_counter, l_cur, l_rate, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           trans_id NUMBER PATH '$.TRANS_ID', trans_type VARCHAR2(10) PATH '$.TRANS_TYPE',
           company_id NUMBER PATH '$.COMPANY_ID', trans_date VARCHAR2(20) PATH '$.TRANS_DATE',
           warehouse_id NUMBER PATH '$.WAREHOUSE_ID', to_warehouse_id NUMBER PATH '$.TO_WAREHOUSE_ID',
           counter_account_id NUMBER PATH '$.COUNTER_ACCOUNT_ID',
           currency_code VARCHAR2(3) PATH '$.CURRENCY_CODE', exchange_rate NUMBER PATH '$.EXCHANGE_RATE',
           description VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  SELECT currency_code INTO l_base_cur FROM currencies WHERE is_base = 'Y';
  IF l_type NOT IN ('RECEIPT','OPENING') OR l_cur IS NULL THEN l_cur := l_base_cur; l_rate := 1; END IF;
  IF l_cur = l_base_cur THEN l_rate := 1; END IF;

  IF l_type NOT IN ('RECEIPT','ISSUE','TRANSFER','COUNT','OPENING') OR l_type IS NULL THEN err('نوع الحركة غير صحيح'); END IF;
  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY'); EXCEPTION WHEN OTHERS THEN err('التاريخ غير صحيح'); END;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'ADMIN' OR l_company = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_wh AND company_id = l_company;
  IF l_cnt = 0 THEN err('اختر مخزناً تابعاً للشركة'); END IF;
  IF l_type = 'TRANSFER' THEN
    SELECT COUNT(*) INTO l_cnt FROM warehouses WHERE warehouse_id = l_to_wh AND company_id = l_company;
    IF l_cnt = 0 OR l_to_wh = l_wh THEN err('اختر مخزن الوجهة (مختلف عن المصدر)'); END IF;
  END IF;
  IF l_type IN ('RECEIPT','ISSUE') AND l_counter IS NULL THEN err('اختر الحساب المقابل'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, trans_no INTO l_status, l_no FROM stock_trans WHERE trans_id = l_id FOR UPDATE;
      IF l_status NOT IN ('DRAFT','RETURNED') THEN err('الحركة ' || l_no || ' تمت مراجعتها أو اعتمادها ولا يمكن تعديلها'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الحركة غير موجودة'); END;
  END IF;

  -- التحقق من السطور + كفاية الرصيد للصادر (مجمّع حسب الصنف)
  FOR r IN (SELECT j.line_no, j.item_id, j.unit_id, j.qty, j.unit_cost, u.factor
            FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                   line_no NUMBER PATH '$.LINE_NO', item_id NUMBER PATH '$.ITEM_ID',
                   unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY',
                   unit_cost NUMBER PATH '$.UNIT_COST')) j
            LEFT JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id) LOOP
    l_lines := l_lines + 1;
    IF r.factor IS NULL THEN err('السطر ' || r.line_no || ': الصنف أو الوحدة غير صحيحة'); END IF;
    IF r.qty IS NULL OR r.qty < 0 OR (r.qty = 0 AND l_type <> 'COUNT') THEN
      err('السطر ' || r.line_no || ': الكمية غير صحيحة');
    END IF;
    IF l_type IN ('RECEIPT','OPENING') AND NVL(r.unit_cost, 0) <= 0 THEN err('السطر ' || r.line_no || ': أدخل تكلفة الوحدة'); END IF;
  END LOOP;
  IF l_lines = 0 THEN err('أدخل صنفاً واحداً على الأقل'); END IF;

  IF l_type IN ('ISSUE','TRANSFER') AND l_action = 'POST' THEN
    FOR r IN (SELECT j.item_id, i.item_code, SUM(j.qty * u.factor) need, NVL(MAX(b.qty_base), 0) bal
              FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                     item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID', qty NUMBER PATH '$.QTY')) j
              JOIN item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
              JOIN items i ON i.item_id = j.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
              GROUP BY j.item_id, i.item_code) LOOP
      IF r.need > r.bal THEN
        err('الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي للكمية ' || r.need);
      END IF;
    END LOOP;
  END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ---------------------------------------------------------------- الحفظ
  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_company AND doc_type = SUBSTR(l_type, 1, 10) AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_company, l_type, EXTRACT(YEAR FROM l_date), 1); l_seq := 1;
    END IF;
    l_no := l_type || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');
    INSERT INTO stock_trans (company_id, trans_type, trans_no, trans_date, warehouse_id, to_warehouse_id,
                             counter_account_id, currency_code, exchange_rate, description, created_by)
    VALUES (l_company, l_type, l_no, l_date, l_wh, l_to_wh, l_counter, l_cur, l_rate, l_desc, :APP_USER)
    RETURNING trans_id INTO l_id;
  ELSE
    UPDATE stock_trans SET company_id = l_company, trans_date = l_date, warehouse_id = l_wh,
           to_warehouse_id = l_to_wh, counter_account_id = l_counter, currency_code = l_cur,
           exchange_rate = l_rate, description = l_desc
    WHERE trans_id = l_id;
    DELETE FROM stock_trans_lines WHERE trans_id = l_id;
  END IF;

  -- سطور المصدر (أو الوجهة في الاستلام)
  --  RECEIPT : + بالتكلفة المدخلة  |  ISSUE/TRANSFER : − بمتوسط التكلفة  |  COUNT : الفعلي − الرصيد
  INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                 qty_base, unit_cost, cost_base, value_base)
  SELECT l_id, ROWNUM, l_wh, j.item_id, j.unit_id, u.factor, j.qty,
         x.qty_base, NVL(j.unit_cost, 0), x.cost_base, ROUND(x.qty_base * x.cost_base, 4)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           item_id NUMBER PATH '$.ITEM_ID', unit_id NUMBER PATH '$.UNIT_ID',
           qty NUMBER PATH '$.QTY', unit_cost NUMBER PATH '$.UNIT_COST')) j
  JOIN   item_units u ON u.item_id = j.item_id AND u.unit_id = j.unit_id
  LEFT JOIN v_stock_balance b ON b.item_id = j.item_id AND b.warehouse_id = l_wh
  CROSS APPLY (SELECT
         CASE WHEN l_type IN ('RECEIPT','OPENING') THEN j.qty * u.factor
                     WHEN l_type = 'COUNT' THEN j.qty * u.factor - NVL(b.qty_base, 0)
                     ELSE -(j.qty * u.factor) END AS qty_base,
         CASE WHEN l_type IN ('RECEIPT','OPENING') THEN NVL(j.unit_cost, 0) * l_rate / u.factor
                     ELSE NVL(b.avg_cost, 0) END AS cost_base
         FROM dual) x;

  -- إشعار الإضافة: التكلفة = سعر شراء الصنف ولا تُعدَّل يدوياً
  IF l_type = 'OPENING' THEN
    UPDATE stock_trans_lines sl
    SET    unit_cost = (SELECT CASE WHEN u.unit_id = i.big_unit_id AND i.big_purchase_price > 0 THEN i.big_purchase_price ELSE NULLIF(i.purchase_price, 0) * u.factor END FROM items i JOIN item_units u ON u.item_id = i.item_id AND u.unit_id = sl.unit_id WHERE i.item_id = sl.item_id)
    WHERE  sl.trans_id = l_id;
    UPDATE stock_trans_lines SET cost_base = NVL(unit_cost, 0) * l_rate / factor, value_base = ROUND(qty_base * NVL(unit_cost, 0) * l_rate / factor, 4)
    WHERE  trans_id = l_id;
  END IF;
  UPDATE stock_trans SET status = 'DRAFT', return_note = NULL WHERE trans_id = l_id;

  -- التحويل: سطور الوجهة بنفس التكلفة
  IF l_type = 'TRANSFER' THEN
    INSERT INTO stock_trans_lines (trans_id, line_no, warehouse_id, item_id, unit_id, factor, qty,
                                   qty_base, unit_cost, cost_base, value_base)
    SELECT trans_id, line_no + 1000, l_to_wh, item_id, unit_id, factor, qty,
           -qty_base, unit_cost, cost_base, -value_base
    FROM   stock_trans_lines WHERE trans_id = l_id AND warehouse_id = l_wh;
  END IF;

  ---------------------------------------------------------------- الترحيل
  IF l_action = 'POST' THEN
    SELECT SUM(value_base) INTO l_val FROM stock_trans_lines WHERE trans_id = l_id AND warehouse_id = l_wh;

    -- إشعار الإضافة (بضاعة أول المدة) لا يُنشئ قيداً
    IF l_type NOT IN ('TRANSFER','OPENING') AND ROUND(NVL(l_val, 0), 2) <> 0 THEN
      INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                            description, status, source_type, source_id, created_by, posted_by, posted_on)
      VALUES (l_company, 'ADJ', l_no, l_date, l_base_cur, 1, NVL(l_desc, l_no), 'POSTED', 'MANUAL', l_id,
              :APP_USER, :APP_USER, SYSDATE)
      RETURNING journal_id INTO l_jid;

      l_inv := setting('INVENTORY');
      jline(1, l_inv, l_val);                                       -- المخزون: + وارد / − صادر
      IF l_type = 'COUNT' THEN
        jline(2, setting('INVENTORY_ADJ'), -l_val);                 -- فروقات الجرد
      ELSE
        jline(2, l_counter, -l_val);                                -- المورد أو المصروف
      END IF;

      UPDATE journals SET total_debit  = (SELECT SUM(debit)  FROM journal_lines WHERE journal_id = l_jid),
                          total_credit = (SELECT SUM(credit) FROM journal_lines WHERE journal_id = l_jid)
      WHERE journal_id = l_jid;
    END IF;

    UPDATE stock_trans SET status = 'POSTED', journal_id = l_jid WHERE trans_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE); apex_json.write('id', l_id); apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل الحركة ' ELSE 'تم حفظ الحركة ' END || l_no);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
