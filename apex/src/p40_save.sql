DECLARE
  -- حفظ إذن التوريد / الصرف النقدي (الحساب المقابل والمبلغ والبيان في الرأس مباشرة)
  -- الترقيم: 11 توريد نقدي / 12 صرف نقدي + السنة + 5 خانات تسلسل
  l_id    NUMBER       := :P40_VOUCHER_ID;
  l_type  VARCHAR2(1)  := :P40_VOUCHER_TYPE;
  l_co    NUMBER       := NVL(:G_COMPANY_ID, :G_PARENT_ID);
  l_cash  NUMBER       := :P40_CASH_ACCOUNT_ID;
  l_acc   NUMBER       := :P40_COUNTER_ACCOUNT_ID;
  l_date  DATE;
  l_amt   NUMBER;
  l_st    VARCHAR2(10);
  l_no    VARCHAR2(30);
  l_code  VARCHAR2(2);
  l_seq   NUMBER;
  l_cnt   NUMBER;
  l_cur   VARCHAR2(3);
  PROCEDURE err (p VARCHAR2) IS
  BEGIN apex_error.add_error(p_message => p, p_display_location => apex_error.c_inline_in_notification); END;
BEGIN
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('إدخال الأذونات وتعديلها من صلاحية المدخل فقط'); RETURN; END IF;
  IF l_type NOT IN ('R','P') OR l_type IS NULL THEN err('نوع الإذن غير معروف'); RETURN; END IF;

  BEGIN l_date := TO_DATE(:P40_VOUCHER_DATE, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ الإذن غير صحيح'); END;
  IF l_date IS NULL THEN err('أدخل تاريخ الإذن'); END IF;

  BEGIN l_amt := TO_NUMBER(REPLACE(:P40_AMOUNT, ',', ''));
  EXCEPTION WHEN OTHERS THEN err('المبلغ غير صحيح'); END;
  IF NVL(l_amt, 0) <= 0 THEN err('أدخل مبلغاً أكبر من صفر'); END IF;

  IF l_cash IS NULL THEN err('اختر الخزينة');
  ELSE
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = l_cash AND cash_bank IN ('C','B') AND is_active = 'Y';
    IF l_cnt = 0 THEN err('حساب الخزينة غير صحيح'); END IF;
  END IF;

  IF l_acc IS NULL THEN err('اختر الحساب المقابل');
  ELSE
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = l_acc AND is_postable = 'Y' AND is_active = 'Y';
    IF l_cnt = 0 THEN err('الحساب المقابل يجب أن يكون حساباً تحليلياً فعّالاً');
    ELSIF l_acc = l_cash THEN err('الحساب المقابل لا يكون هو حساب الخزينة نفسه'); END IF;
  END IF;

  IF TRIM(:P40_DESCRIPTION) IS NULL THEN err('أدخل البيان'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, voucher_no INTO l_st, l_no FROM vouchers WHERE voucher_id = l_id FOR UPDATE;
      IF l_st NOT IN ('DRAFT','RETURNED') THEN err('الإذن ' || l_no || ' تمت مراجعته أو اعتماده ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('الإذن غير موجود');
    END;
  END IF;

  IF apex_error.have_errors_occurred THEN RETURN; END IF;

  SELECT currency_code INTO l_cur FROM currencies WHERE is_base = 'Y';

  IF l_id IS NULL THEN
    l_code := CASE l_type WHEN 'R' THEN '11' ELSE '12' END;
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE  company_id = l_co AND doc_type = l_code AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (l_co, l_code, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_code || EXTRACT(YEAR FROM l_date) || LPAD(l_seq, 5, '0');

    INSERT INTO vouchers (company_id, voucher_type, voucher_kind, voucher_no, voucher_date, cash_account_id,
                          counter_account_id, currency_code, exchange_rate, pay_method, party_name,
                          description, total_amount, status, created_by)
    VALUES (l_co, l_type, 'CASH', l_no, l_date, l_cash, l_acc, l_cur, 1, 'CASH', :P40_PARTY_NAME,
            :P40_DESCRIPTION, l_amt, 'DRAFT', :APP_USER)
    RETURNING voucher_id INTO l_id;
    :P40_VOUCHER_ID := l_id;
    l_st := NULL;
  ELSE
    UPDATE vouchers
    SET    voucher_date = l_date, cash_account_id = l_cash, counter_account_id = l_acc,
           party_name = :P40_PARTY_NAME, description = :P40_DESCRIPTION, total_amount = l_amt,
           status = 'DRAFT', return_note = NULL
    WHERE  voucher_id = l_id;
  END IF;

  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('VOUCHER', l_id, 'SAVE', l_st, 'DRAFT', :APP_USER);

  apex_application.g_print_success_message := 'تم حفظ الإذن ' || l_no || ' - بانتظار المراجعة';
END;
