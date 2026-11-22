DECLARE
  -- x01 = رقم الإذن: حسابات البنوك + شيكات الإذن
  l_banks CLOB;
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('v' VALUE account_id, 't' VALUE account_code || ' - ' || name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO   l_banks
  FROM   accounts WHERE cash_bank = 'B' AND is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'CHEQUE_NO'       VALUE cheque_no,
           'BANK_ACCOUNT_ID' VALUE bank_account_id,
           'BANK_NAME'       VALUE bank_name,
           'DUE_DATE'        VALUE TO_CHAR(due_date, 'DD/MM/YYYY'),
           'AMOUNT'          VALUE amount,
           'PAYEE_NAME'      VALUE payee_name,
           'STATUS_T'        VALUE DECODE(status, 'PENDING', 'قائم', 'CLEARED', 'تم الصرف / التحصيل', 'BOUNCED', 'مرتد'))
         ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   cheques WHERE voucher_id = TO_NUMBER(apex_application.g_x01);

  apex_util.prn('{"banks":' || COALESCE(l_banks, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
