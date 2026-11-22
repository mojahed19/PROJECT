DECLARE
  c cheques%ROWTYPE;
  v vouchers%ROWTYPE;
  l_bank VARCHAR2(200);
BEGIN
  SELECT * INTO c FROM cheques  WHERE cheque_id  = :P47_CHEQUE_ID;
  SELECT * INTO v FROM vouchers WHERE voucher_id = c.voucher_id;
  SELECT MAX(name_ar) INTO l_bank FROM accounts WHERE account_id = c.bank_account_id;

  :P47_KIND        := v.voucher_type;
  :P47_CHQ_STATUS  := c.status;
  :P47_JOURNAL_ID  := c.settle_journal_id;
  SELECT MAX(status) INTO :P47_JNL_STATUS FROM journals WHERE journal_id = c.settle_journal_id;
  :P47_CLEAR_LABEL := CASE v.voucher_type WHEN 'R' THEN 'تم التحصيل' ELSE 'تم الصرف' END;
  SELECT MAX(name_ar) INTO l_bank FROM accounts WHERE account_id = NVL(c.bank_account_id, v.bank_account_id);
  IF :P47_SETTLE_BANK_ID IS NULL THEN :P47_SETTLE_BANK_ID := v.bank_account_id; END IF;
  :P47_INFO := CASE v.voucher_type WHEN 'R' THEN 'شيك وارد' ELSE 'شيك صادر' END
            || ' مسلسل ' || c.cheque_serial || ' - رقم ' || c.cheque_no || ' - ' || l_bank
            || ' - المبلغ ' || TO_CHAR(c.amount, 'FM999G999G999G990D00')
            || ' - الاستحقاق ' || TO_CHAR(c.due_date, 'DD/MM/YYYY')
            || ' - الإذن ' || v.voucher_no
            || CASE WHEN v.status <> 'POSTED' THEN ' (الإذن لم يُرحّل بعد: لا يمكن التسوية قبل الترحيل)' END
            || CASE c.status WHEN 'CLEARED' THEN ' - تمت التسوية في ' || TO_CHAR(c.settle_date, 'DD/MM/YYYY')
                             WHEN 'BOUNCED' THEN ' - مرتد في ' || TO_CHAR(c.settle_date, 'DD/MM/YYYY') END;
  IF :P47_SETTLE_DATE IS NULL THEN
    :P47_SETTLE_DATE := TO_CHAR(GREATEST(TRUNC(SYSDATE), c.due_date), 'DD/MM/YYYY');
  END IF;
EXCEPTION WHEN NO_DATA_FOUND THEN
  :P47_CHEQUE_ID := NULL;
END;
