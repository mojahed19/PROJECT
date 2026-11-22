DECLARE
  r vouchers%ROWTYPE;
BEGIN
  SELECT * INTO r FROM vouchers WHERE voucher_id = :P40_VOUCHER_ID;
  :P40_VOUCHER_TYPE       := r.voucher_type;
  :P40_VOUCHER_NO         := r.voucher_no;
  :P40_VOUCHER_DATE       := TO_CHAR(r.voucher_date, 'DD/MM/YYYY');
  :P40_CASH_ACCOUNT_ID    := r.cash_account_id;
  :P40_COUNTER_ACCOUNT_ID := r.counter_account_id;
  :P40_AMOUNT             := TO_CHAR(r.total_amount, 'FM999G999G999G990D00');
  :P40_PARTY_NAME         := r.party_name;
  :P40_DESCRIPTION        := r.description;
  :P40_STATUS             := r.status;
  :P40_JOURNAL_ID         := r.journal_id;
  __WF__
END;
