DECLARE
  r vouchers%ROWTYPE;
BEGIN
  SELECT * INTO r FROM vouchers WHERE voucher_id = :P45_VOUCHER_ID;
  :P45_VOUCHER_TYPE       := r.voucher_type;
  :P45_VOUCHER_NO         := r.voucher_no;
  :P45_VOUCHER_DATE       := TO_CHAR(r.voucher_date, 'DD/MM/YYYY');
  :P45_COUNTER_ACCOUNT_ID := r.counter_account_id;
  :P45_BANK_ACCOUNT_ID    := r.bank_account_id;
  :P45_PARTY_NAME         := r.party_name;
  :P45_DESCRIPTION        := r.description;
  :P45_STATUS             := r.status;
  :P45_JOURNAL_ID         := r.journal_id;
  :P45_TOTAL              := TO_CHAR(r.total_amount, 'FM999G999G999G990D00');
  SELECT COUNT(*) INTO :P45_CHQ_COUNT FROM cheques WHERE voucher_id = r.voucher_id;
  __WF__
END;
