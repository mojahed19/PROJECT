DECLARE
  v vouchers%ROWTYPE; l_cnt NUMBER;
BEGIN
  SELECT * INTO v FROM vouchers WHERE voucher_id = :P40_VOUCHER_ID;
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'GM' OR v.company_id = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = v.company_id);
  IF l_cnt = 0 THEN raise_application_error(-20001, 'ليس لديك صلاحية على هذه الشركة'); END IF;

  :P40_VOUCHER_TYPE    := v.voucher_type;
  :P40_COMPANY_ID      := v.company_id;
  :P40_VOUCHER_NO      := v.voucher_no;
  :P40_VOUCHER_DATE    := TO_CHAR(v.voucher_date, 'DD/MM/YYYY');
  :P40_CASH_ACCOUNT_ID := v.cash_account_id;
  :P40_CURRENCY_CODE   := v.currency_code;
  :P40_EXCHANGE_RATE   := v.exchange_rate;
  :P40_PAY_METHOD      := v.pay_method;
  :P40_CHEQUE_NO       := v.cheque_no;
  :P40_CHEQUE_DATE     := TO_CHAR(v.cheque_date, 'DD/MM/YYYY');
  :P40_BANK_NAME       := v.bank_name;
  :P40_PARTY_NAME      := v.party_name;
  :P40_DESCRIPTION     := v.description;
  :P40_STATUS          := v.status;
  :P40_JOURNAL_ID      := v.journal_id;
END;
