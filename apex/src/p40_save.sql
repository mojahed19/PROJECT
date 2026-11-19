DECLARE
  l_clob    CLOB := apex_application.g_clob_01;
  l_action  VARCHAR2(10) := apex_application.g_x01;
  l_errs    apex_t_varchar2 := apex_t_varchar2();

  l_id NUMBER; l_type CHAR(1); l_company NUMBER; l_date_s VARCHAR2(20); l_date DATE;
  l_cash NUMBER; l_cur VARCHAR2(3); l_rate NUMBER; l_method VARCHAR2(10);
  l_chq_no VARCHAR2(30); l_chq_date_s VARCHAR2(20); l_bank VARCHAR2(100);
  l_party VARCHAR2(150); l_desc VARCHAR2(500);

  l_status VARCHAR2(10); l_no VARCHAR2(30); l_seq NUMBER; l_cnt NUMBER;
  l_total  NUMBER := 0; l_lines NUMBER := 0; l_jid NUMBER; l_jt VARCHAR2(10);
  l_drb NUMBER; l_crb NUMBER; l_last NUMBER;

  PROCEDURE err (p VARCHAR2) IS BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  SELECT h.voucher_id, h.voucher_type, h.company_id, h.voucher_date, h.cash_account_id,
         h.currency_code, h.exchange_rate, h.pay_method, h.cheque_no, h.cheque_date,
         h.bank_name, h.party_name, h.description
  INTO   l_id, l_type, l_company, l_date_s, l_cash, l_cur, l_rate, l_method,
         l_chq_no, l_chq_date_s, l_bank, l_party, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           voucher_id      NUMBER        PATH '$.VOUCHER_ID',
           voucher_type    VARCHAR2(1)   PATH '$.VOUCHER_TYPE',
           company_id      NUMBER        PATH '$.COMPANY_ID',
           voucher_date    VARCHAR2(20)  PATH '$.VOUCHER_DATE',
           cash_account_id NUMBER        PATH '$.CASH_ACCOUNT_ID',
           currency_code   VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate   NUMBER        PATH '$.EXCHANGE_RATE',
           pay_method      VARCHAR2(10)  PATH '$.PAY_METHOD',
           cheque_no       VARCHAR2(30)  PATH '$.CHEQUE_NO',
           cheque_date     VARCHAR2(20)  PATH '$.CHEQUE_DATE',
           bank_name       VARCHAR2(100) PATH '$.BANK_NAME',
           party_name      VARCHAR2(150) PATH '$.PARTY_NAME',
           description     VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  l_jt := CASE l_type WHEN 'R' THEN 'RV' WHEN 'P' THEN 'PV' END;
  IF l_jt IS NULL THEN err('نوع الإذن غير معروف'); END IF;

  BEGIN l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ الإذن غير صحيح'); END;

  IF l_company IS NULL THEN err('اختر الشركة'); END IF;
  IF l_cash    IS NULL THEN err('اختر الصندوق أو البنك'); END IF;
  IF l_cur     IS NULL THEN err('اختر العملة'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;
  IF l_method IN ('CHEQUE') AND l_chq_no IS NULL THEN err('أدخل رقم الشيك'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR l_company = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM accounts
  WHERE account_id = l_cash AND cash_bank IN ('C','B') AND is_active = 'Y'
  AND (company_id IS NULL OR company_id = l_company);
  IF l_cnt = 0 THEN err('حساب الصندوق/البنك غير صحيح'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years
    WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, voucher_no INTO l_status, l_no FROM vouchers WHERE voucher_id = l_id FOR UPDATE;
      IF l_status <> 'DRAFT' THEN err('الإذن مرحّل ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الإذن غير موجود'); END;
  END IF;

  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
               line_no NUMBER PATH '$.LINE_NO', account_id NUMBER PATH '$.ACCOUNT_ID',
               amount  NUMBER PATH '$.AMOUNT'))) LOOP
    l_lines := l_lines + 1;
    SELECT COUNT(*) INTO l_cnt FROM accounts
    WHERE account_id = r.account_id AND is_postable = 'Y' AND is_active = 'Y'
    AND (company_id IS NULL OR company_id = l_company);
    IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الحساب غير صحيح'); END IF;
    IF r.account_id = l_cash THEN err('السطر ' || r.line_no || ': لا يكون الحساب المقابل هو الصندوق نفسه'); END IF;
    IF NVL(r.amount, 0) <= 0 THEN err('السطر ' || r.line_no || ': المبلغ يجب أن يكون أكبر من صفر'); END IF;
    l_total := l_total + NVL(r.amount, 0);
  END LOOP;
  IF l_lines = 0 THEN err('أدخل سطراً واحداً على الأقل'); END IF;

  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('errors', l_errs); apex_json.close_object;
    RETURN;
  END IF;

  ------------------------------------------------------------------ حفظ الإذن
  IF l_id IS NULL THEN
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = l_company AND doc_type = l_jt AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (l_company, l_jt, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_jt || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO vouchers (company_id, voucher_type, voucher_no, voucher_date, cash_account_id,
                          currency_code, exchange_rate, pay_method, cheque_no, cheque_date,
                          bank_name, party_name, description, created_by)
    VALUES (l_company, l_type, l_no, l_date, l_cash, l_cur, l_rate, l_method, l_chq_no,
            TO_DATE(l_chq_date_s, 'DD/MM/YYYY'), l_bank, l_party, l_desc, :APP_USER)
    RETURNING voucher_id INTO l_id;
  ELSE
    UPDATE vouchers
    SET company_id = l_company, voucher_date = l_date, cash_account_id = l_cash,
        currency_code = l_cur, exchange_rate = l_rate, pay_method = l_method,
        cheque_no = l_chq_no, cheque_date = TO_DATE(l_chq_date_s, 'DD/MM/YYYY'),
        bank_name = l_bank, party_name = l_party, description = l_desc
    WHERE voucher_id = l_id;
    DELETE FROM voucher_lines WHERE voucher_id = l_id;
  END IF;

  INSERT INTO voucher_lines (voucher_id, line_no, account_id, amount, partner_company_id, description)
  SELECT l_id, ROWNUM, account_id, amount, partner_company_id, description
  FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
         account_id NUMBER PATH '$.ACCOUNT_ID', amount NUMBER PATH '$.AMOUNT',
         partner_company_id NUMBER PATH '$.PARTNER_COMPANY_ID',
         description VARCHAR2(500) PATH '$.DESCRIPTION'));

  UPDATE vouchers SET total_amount = l_total WHERE voucher_id = l_id;

  ------------------------------------------------------------------ الترحيل = إنشاء القيد
  IF l_action = 'POST' THEN
    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, source_id,
                          total_debit, total_credit, created_by, posted_by, posted_on)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate,
            NVL(l_desc, CASE l_type WHEN 'R' THEN 'إذن توريد ' ELSE 'إذن صرف ' END || l_no),
            l_chq_no, 'POSTED', 'VOUCHER', l_id, l_total, l_total, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_jid;

    -- سطر الصندوق
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
    VALUES (l_jid, 1, l_cash,
            CASE l_type WHEN 'R' THEN l_total ELSE 0 END,
            CASE l_type WHEN 'P' THEN l_total ELSE 0 END,
            CASE l_type WHEN 'R' THEN ROUND(l_total * l_rate, 2) ELSE 0 END,
            CASE l_type WHEN 'P' THEN ROUND(l_total * l_rate, 2) ELSE 0 END,
            l_party);

    -- السطور المقابلة
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, description)
    SELECT l_jid, line_no + 1, account_id,
           CASE l_type WHEN 'P' THEN amount ELSE 0 END,
           CASE l_type WHEN 'R' THEN amount ELSE 0 END,
           CASE l_type WHEN 'P' THEN ROUND(amount * l_rate, 2) ELSE 0 END,
           CASE l_type WHEN 'R' THEN ROUND(amount * l_rate, 2) ELSE 0 END,
           partner_company_id, NVL(description, l_desc)
    FROM voucher_lines WHERE voucher_id = l_id;

    -- فرق التقريب
    SELECT SUM(debit_base), SUM(credit_base) INTO l_drb, l_crb FROM journal_lines WHERE journal_id = l_jid;
    IF l_drb <> l_crb THEN
      SELECT MAX(line_id) INTO l_last FROM journal_lines WHERE journal_id = l_jid AND line_no > 1;
      UPDATE journal_lines
      SET debit_base  = debit_base  + CASE WHEN debit  > 0 THEN l_crb - l_drb ELSE 0 END,
          credit_base = credit_base + CASE WHEN credit > 0 THEN l_drb - l_crb ELSE 0 END
      WHERE line_id = l_last;
    END IF;

    UPDATE vouchers SET status = 'POSTED', journal_id = l_jid WHERE voucher_id = l_id;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('no', l_no);
  apex_json.write('message', CASE WHEN l_action = 'POST' THEN 'تم ترحيل الإذن ' ELSE 'تم حفظ الإذن ' END || l_no);
  apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_json.open_object; apex_json.write('ok', FALSE);
  apex_json.open_array('errors'); apex_json.write(SQLERRM); apex_json.close_array;
  apex_json.close_object;
END;
