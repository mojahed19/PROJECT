DECLARE
  -- x01 = الفرع ، x02 = تاريخ الميزانية (DD/MM/YYYY)
  l_acc   CLOB;
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code, 'name' VALUE name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO   l_acc
  FROM   accounts WHERE is_postable = 'Y' AND is_active = 'Y';

  SELECT JSON_ARRAYAGG(JSON_OBJECT('ACCOUNT_ID' VALUE b.account_id, 'DEBIT' VALUE NULLIF(b.debit, 0),
                                   'CREDIT' VALUE NULLIF(b.credit, 0), 'NOTES' VALUE b.notes)
                       ORDER BY a.account_code RETURNING CLOB)
  INTO   l_lines
  FROM   branch_balances b JOIN accounts a ON a.account_id = b.account_id
  WHERE  b.company_id = TO_NUMBER(apex_application.g_x01)
  AND    b.as_of_date = TO_DATE(apex_application.g_x02, 'DD/MM/YYYY');

  apex_util.prn('{"accounts":' || COALESCE(l_acc, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
