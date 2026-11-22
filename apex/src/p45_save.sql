DECLARE
  -- حفظ إذن توريد / صرف شيكات (Ajax: p_clob_01 = {header, lines})
  -- الترقيم: 13 توريد شيكات / 14 صرف شيكات + السنة + 5 خانات تسلسل
  l_clob  CLOB := apex_application.g_clob_01;
  l_errs  apex_t_varchar2 := apex_t_varchar2();
  l_co    NUMBER := NVL(:G_COMPANY_ID, :G_PARENT_ID);

  l_id NUMBER; l_type VARCHAR2(1); l_date_s VARCHAR2(20); l_date DATE; l_acc NUMBER;
  l_party VARCHAR2(150); l_desc VARCHAR2(500);
  l_st VARCHAR2(10); l_no VARCHAR2(30); l_code VARCHAR2(2); l_seq NUMBER; l_cnt NUMBER;
  l_total NUMBER := 0; l_lines NUMBER := 0; l_due DATE; l_cur VARCHAR2(3);

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT h.voucher_id, h.voucher_type, h.voucher_date, h.counter_account_id, h.party_name, h.description
  INTO   l_id, l_type, l_date_s, l_acc, l_party, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           voucher_id         NUMBER        PATH '$.VOUCHER_ID',
           voucher_type       VARCHAR2(1)   PATH '$.VOUCHER_TYPE',
           voucher_date       VARCHAR2(20)  PATH '$.VOUCHER_DATE',
           counter_account_id NUMBER        PATH '$.COUNTER_ACCOUNT_ID',
           party_name         VARCHAR2(150) PATH '$.PARTY_NAME',
           description        VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('إدخال الأذونات وتعديلها من صلاحية المدخل فقط'); END IF;
  IF l_type IS NULL OR l_type NOT IN ('R','P') THEN err('نوع الإذن غير معروف'); END IF;

  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ الإذن غير صحيح'); END;
  IF l_date IS NULL THEN err('أدخل تاريخ الإذن'); END IF;
  IF TRIM(l_desc) IS NULL THEN err('أدخل البيان'); END IF;

  IF l_acc IS NULL THEN err('اختر الحساب المقابل');
  ELSE
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = l_acc AND is_postable = 'Y' AND is_active = 'Y' AND cash_bank = 'N';
    IF l_cnt = 0 THEN err('الحساب المقابل يجب أن يكون حساباً تحليلياً فعّالاً (غير الخزينة والبنوك)'); END IF;
  END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, voucher_no INTO l_st, l_no FROM vouchers WHERE voucher_id = l_id AND voucher_kind = 'CHEQUE' FOR UPDATE;
      IF l_st NOT IN ('DRAFT','RETURNED') THEN err('الإذن ' || l_no || ' تمت مراجعته أو اعتماده ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الإذن غير موجود');
    END;
  END IF;

  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
               line_no         NUMBER        PATH '$.LINE_NO',
               cheque_no       VARCHAR2(30)  PATH '$.CHEQUE_NO',
               bank_account_id NUMBER        PATH '$.BANK_ACCOUNT_ID',
               bank_name       VARCHAR2(100) PATH '$.BANK_NAME',
               due_date        VARCHAR2(20)  PATH '$.DUE_DATE',
               amount          NUMBER        PATH '$.AMOUNT'))) LOOP
    l_lines := l_lines + 1;
    IF r.cheque_no IS NULL THEN err('الشيك ' || r.line_no || ': أدخل رقم الشيك'); END IF;
    IF l_type = 'P' THEN
      SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = r.bank_account_id AND cash_bank = 'B' AND is_active = 'Y';
      IF l_cnt = 0 THEN err('الشيك ' || r.line_no || ': اختر البنك المسحوب عليه'); END IF;
    ELSIF r.bank_name IS NULL THEN err('الشيك ' || r.line_no || ': أدخل بنك الساحب');
    END IF;
    BEGIN
      l_due := TO_DATE(r.due_date, 'DD/MM/YYYY');
      IF l_due IS NULL THEN err('الشيك ' || r.line_no || ': أدخل تاريخ الاستحقاق'); END IF;
    EXCEPTION WHEN OTHERS THEN err('الشيك ' || r.line_no || ': تاريخ الاستحقاق غير صحيح');
    END;
    IF NVL(r.amount, 0) <= 0 THEN err('الشيك ' || r.line_no || ': المبلغ يجب أن يكون أكبر من صفر'); END IF;
    l_total := l_total + NVL(r.amount, 0);
  END LOOP;
  IF l_lines = 0 THEN err('أدخل شيكاً واحداً على الأقل'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  SELECT currency_code INTO l_cur FROM currencies WHERE is_base = 'Y';

  IF l_id IS NULL THEN
    l_code := CASE l_type WHEN 'R' THEN '13' ELSE '14' END;
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE  company_id = l_co AND doc_type = l_code AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (l_co, l_code, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_code || EXTRACT(YEAR FROM l_date) || LPAD(l_seq, 5, '0');

    INSERT INTO vouchers (company_id, voucher_type, voucher_kind, voucher_no, voucher_date, counter_account_id,
                          currency_code, exchange_rate, pay_method, party_name, description, total_amount, status, created_by)
    VALUES (l_co, l_type, 'CHEQUE', l_no, l_date, l_acc, l_cur, 1, 'CHEQUE', l_party, l_desc, l_total, 'DRAFT', :APP_USER)
    RETURNING voucher_id INTO l_id;
    l_st := NULL;
  ELSE
    UPDATE vouchers
    SET    voucher_date = l_date, counter_account_id = l_acc, party_name = l_party, description = l_desc,
           total_amount = l_total, status = 'DRAFT', return_note = NULL
    WHERE  voucher_id = l_id;
    DELETE FROM cheques WHERE voucher_id = l_id;
  END IF;

  INSERT INTO cheques (voucher_id, line_no, cheque_no, bank_account_id, bank_name, due_date, amount, payee_name)
  SELECT l_id, ROWNUM, cheque_no,
         CASE WHEN l_type = 'P' THEN bank_account_id END,
         CASE WHEN l_type = 'R' THEN bank_name END,
         TO_DATE(due_date, 'DD/MM/YYYY'), amount, NVL(payee_name, l_party)
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           cheque_no       VARCHAR2(30)  PATH '$.CHEQUE_NO',
           bank_account_id NUMBER        PATH '$.BANK_ACCOUNT_ID',
           bank_name       VARCHAR2(100) PATH '$.BANK_NAME',
           due_date        VARCHAR2(20)  PATH '$.DUE_DATE',
           amount          NUMBER        PATH '$.AMOUNT',
           payee_name      VARCHAR2(150) PATH '$.PAYEE_NAME'));

  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('VOUCHER', l_id, 'SAVE', l_st, 'DRAFT', :APP_USER);

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('no', l_no);
  apex_json.write('message', 'تم حفظ الإذن ' || l_no || ' - بانتظار المراجعة');
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
