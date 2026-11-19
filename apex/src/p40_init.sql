DECLARE
  l_acc   CLOB;
  l_comp  CLOB;
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code, 'name' VALUE name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO   l_acc
  FROM   accounts
  WHERE  is_postable = 'Y' AND is_active = 'Y' AND cash_bank = 'N'
  AND    (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  SELECT JSON_ARRAYAGG(JSON_OBJECT('v' VALUE company_id, 't' VALUE name_ar)
                       ORDER BY company_code RETURNING CLOB)
  INTO   l_comp
  FROM   companies WHERE is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT(
             'ACCOUNT_ID' VALUE account_id, 'AMOUNT' VALUE amount,
             'PARTNER_COMPANY_ID' VALUE partner_company_id, 'DESCRIPTION' VALUE description)
           ORDER BY line_no RETURNING CLOB)
  INTO   l_lines
  FROM   voucher_lines WHERE voucher_id = TO_NUMBER(apex_application.g_x02);

  apex_util.prn('{"accounts":'  || COALESCE(l_acc,   TO_CLOB('[]')) ||
                ',"companies":' || COALESCE(l_comp,  TO_CLOB('[]')) ||
                ',"lines":'     || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
