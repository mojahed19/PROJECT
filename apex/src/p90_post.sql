DECLARE
  t stock_trans%ROWTYPE;

  l_tid NUMBER; l_type VARCHAR2(10); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_wh NUMBER; l_to_wh NUMBER; l_counter NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_desc VARCHAR2(500);
  l_base_cur VARCHAR2(3);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER; l_lines NUMBER := 0;
  l_jid NUMBER; l_val NUMBER; l_inv NUMBER; l_adj NUMBER;


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
  -- ترحيل حركة المخزون عند اعتمادها (إشعار الإضافة بدون قيد)
  SELECT * INTO t FROM stock_trans WHERE trans_id = l_id;
  l_tid := t.trans_id; l_type := t.trans_type; l_company := t.company_id; l_no := t.trans_no; l_date := t.trans_date;
  l_wh := t.warehouse_id; l_counter := t.counter_account_id; l_desc := t.description;
  SELECT currency_code INTO l_base_cur FROM currencies WHERE is_base = 'Y';
  IF l_type IN ('ISSUE','TRANSFER') THEN
    FOR r IN (SELECT i.item_code, -SUM(l.qty_base) need, NVL(MAX(b.qty_base), 0) bal
              FROM stock_trans_lines l JOIN items i ON i.item_id = l.item_id
              LEFT JOIN v_stock_balance b ON b.item_id = l.item_id AND b.warehouse_id = l_wh
              WHERE l.trans_id = l_tid AND l.warehouse_id = l_wh GROUP BY i.item_code) LOOP
      IF r.need > r.bal THEN raise_application_error(-20033, 'الصنف ' || r.item_code || ': الرصيد ' || r.bal || ' لا يكفي للكمية ' || r.need); END IF;
    END LOOP;
  END IF;
    SELECT SUM(value_base) INTO l_val FROM stock_trans_lines WHERE trans_id = l_tid AND warehouse_id = l_wh;

    -- إشعار الإضافة (بضاعة أول المدة) لا يُنشئ قيداً
    IF l_type NOT IN ('TRANSFER','OPENING') AND ROUND(NVL(l_val, 0), 2) <> 0 THEN
      INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                            description, status, source_type, source_id, created_by, posted_by, posted_on)
      VALUES (l_company, 'ADJ', l_no, l_date, l_base_cur, 1, NVL(l_desc, l_no), 'POSTED', 'MANUAL', l_tid,
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

    UPDATE stock_trans SET status = 'POSTED', journal_id = l_jid WHERE trans_id = l_tid;
END;
