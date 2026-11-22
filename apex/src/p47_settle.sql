DECLARE
  -- تسوية شيك: ينشئ قيد تسوية (مسودة) يمر بالمراجعة والاعتماد ثم الترحيل من شاشة القيد
  --   صادر  + تم الصرف    : من ح/ شيكات تحت الصرف     إلى ح/ البنك المسحوب عليه
  --   وارد  + تم التحصيل  : من ح/ البنك المودع فيه     إلى ح/ شيكات تحت التحصيل
  --   وارد  + مرتد        : من ح/ الحساب المقابل (العميل) إلى ح/ شيكات تحت التحصيل
  --   صادر  + مرتد/ملغى   : من ح/ شيكات تحت الصرف     إلى ح/ الحساب المقابل (المورد)
  l_req  VARCHAR2(20) := :REQUEST;
  c      cheques%ROWTYPE;
  v      vouchers%ROWTYPE;
  l_date DATE;
  l_mid  NUMBER;
  l_dr   NUMBER;
  l_cr   NUMBER;
  l_jid  NUMBER;
  l_seq  NUMBER;
  l_no   VARCHAR2(30);
  l_cnt  NUMBER;
  l_jst  VARCHAR2(10);
  l_desc VARCHAR2(500);
  PROCEDURE err (p VARCHAR2) IS
  BEGIN apex_error.add_error(p_message => p, p_display_location => apex_error.c_inline_in_notification); END;
BEGIN
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('تسوية الشيكات من صلاحية المدخل'); RETURN; END IF;

  SELECT * INTO c FROM cheques WHERE cheque_id = :P47_CHEQUE_ID FOR UPDATE;
  SELECT * INTO v FROM vouchers WHERE voucher_id = c.voucher_id;

  ------------------------------------------------------------ إلغاء التسوية (قبل مراجعة القيد)
  IF l_req = 'UNSETTLE' THEN
    SELECT MAX(status) INTO l_jst FROM journals WHERE journal_id = c.settle_journal_id;
    IF c.status = 'PENDING' OR NVL(l_jst, 'DRAFT') NOT IN ('DRAFT','RETURNED') THEN
      err('لا يمكن إلغاء التسوية بعد مراجعة قيدها'); RETURN;
    END IF;
    UPDATE cheques SET status = 'PENDING', settle_date = NULL, settle_bank_id = NULL, settle_journal_id = NULL, settled_by = NULL
    WHERE  cheque_id = c.cheque_id;
    IF c.settle_journal_id IS NOT NULL THEN
      DELETE FROM journal_lines WHERE journal_id = c.settle_journal_id;
      DELETE FROM journals      WHERE journal_id = c.settle_journal_id;
    END IF;
    apex_application.g_print_success_message := 'تم إلغاء تسوية الشيك ' || c.cheque_no;
    RETURN;
  END IF;

  ------------------------------------------------------------ التحقق
  IF v.status <> 'POSTED' THEN err('لا تُسوّى الشيكات قبل ترحيل الإذن ' || v.voucher_no); END IF;
  IF c.status <> 'PENDING' THEN err('الشيك تمت تسويته من قبل'); END IF;
  BEGIN l_date := TO_DATE(:P47_SETTLE_DATE, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ التسوية غير صحيح'); END;
  IF l_date IS NULL THEN err('أدخل تاريخ التسوية');
  ELSE
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;
  IF l_req = 'CLEAR' AND v.voucher_type = 'R' THEN
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_id = :P47_SETTLE_BANK_ID AND cash_bank = 'B';
    IF l_cnt = 0 THEN err('اختر البنك الذي أودع فيه الشيك'); END IF;
  END IF;

  BEGIN
    SELECT account_id INTO l_mid FROM account_settings
    WHERE  company_id = v.company_id AND setting_code = CASE v.voucher_type WHEN 'R' THEN 'CHEQUES_IN' ELSE 'CHEQUES_OUT' END;
  EXCEPTION WHEN NO_DATA_FOUND THEN err('حدد حساب الشيكات في الحسابات الافتراضية');
  END;
  IF apex_error.have_errors_occurred THEN RETURN; END IF;

  IF v.voucher_type = 'P' THEN
    l_dr := l_mid;
    l_cr := CASE l_req WHEN 'CLEAR' THEN c.bank_account_id ELSE v.counter_account_id END;
  ELSE
    l_cr := l_mid;
    l_dr := CASE l_req WHEN 'CLEAR' THEN TO_NUMBER(:P47_SETTLE_BANK_ID) ELSE v.counter_account_id END;
  END IF;

  l_desc := CASE WHEN l_req = 'BOUNCE' THEN 'ارتداد شيك ' WHEN v.voucher_type = 'R' THEN 'تحصيل شيك ' ELSE 'صرف شيك ' END
            || c.cheque_no || ' - إذن ' || v.voucher_no || CASE WHEN c.payee_name IS NOT NULL THEN ' - ' || c.payee_name END;

  ------------------------------------------------------------ قيد التسوية (مسودة) - الترقيم 15 + السنة + تسلسل
  UPDATE doc_sequences SET last_no = last_no + 1
  WHERE  company_id = v.company_id AND doc_type = '15' AND fy_year = EXTRACT(YEAR FROM l_date)
  RETURNING last_no INTO l_seq;
  IF SQL%ROWCOUNT = 0 THEN
    INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (v.company_id, '15', EXTRACT(YEAR FROM l_date), 1);
    l_seq := 1;
  END IF;
  l_no := '15' || EXTRACT(YEAR FROM l_date) || LPAD(l_seq, 5, '0');

  INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate, description,
                        ref_no, status, source_type, source_id, total_debit, total_credit, created_by)
  VALUES (v.company_id, 'CQ', l_no, l_date, v.currency_code, v.exchange_rate, l_desc,
          c.cheque_no, 'DRAFT', 'CHEQUE', c.cheque_id, c.amount, c.amount, :APP_USER)
  RETURNING journal_id INTO l_jid;

  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
  VALUES (l_jid, 1, l_dr, c.amount, 0, ROUND(c.amount * v.exchange_rate, 2), 0, l_desc);
  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
  VALUES (l_jid, 2, l_cr, 0, c.amount, 0, ROUND(c.amount * v.exchange_rate, 2), l_desc);

  UPDATE cheques
  SET    status = CASE l_req WHEN 'CLEAR' THEN 'CLEARED' ELSE 'BOUNCED' END,
         settle_date = l_date,
         settle_bank_id = CASE WHEN l_req = 'CLEAR' AND v.voucher_type = 'R' THEN TO_NUMBER(:P47_SETTLE_BANK_ID) END,
         settle_journal_id = l_jid, settled_by = :APP_USER
  WHERE  cheque_id = c.cheque_id;

  INSERT INTO doc_actions (doc_type, doc_id, action, to_status, note, action_by)
  VALUES ('JOURNAL', l_jid, 'SAVE', 'DRAFT', l_desc, :APP_USER);

  apex_application.g_print_success_message := 'تم إنشاء قيد التسوية ' || l_no || ' - بانتظار المراجعة والاعتماد';
END;
