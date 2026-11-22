DECLARE
  -- x01 = رقم الإذن: شيكات الإذن
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'CHEQUE_SERIAL' VALUE cheque_serial,
           'CHEQUE_NO'     VALUE cheque_no,
           'BANK_NAME'     VALUE bank_name,
           'DUE_DATE'      VALUE TO_CHAR(due_date, 'DD/MM/YYYY'),
           'AMOUNT'        VALUE amount,
           'STATUS_T'      VALUE DECODE(status, 'PENDING', 'قائم', 'CLEARED', 'تم الصرف / التحصيل', 'BOUNCED', 'مرتد'))
         ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   cheques WHERE voucher_id = TO_NUMBER(apex_application.g_x01);

  apex_util.prn('{"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
