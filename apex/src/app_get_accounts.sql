DECLARE
  l_json CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(
           JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code,
                       'name' VALUE name_ar, 'cash' VALUE cash_bank)
           ORDER BY account_code RETURNING CLOB)
  INTO   l_json
  FROM   accounts
  WHERE  is_postable = 'Y'
  AND    is_active   = 'Y'
  AND    (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  apex_util.prn(COALESCE(l_json, TO_CLOB('[]')), FALSE);
END;
