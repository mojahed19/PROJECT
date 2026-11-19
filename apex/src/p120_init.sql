DECLARE l_acc CLOB; l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE account_id, 'code' VALUE account_code, 'name' VALUE name_ar)
                       ORDER BY account_code RETURNING CLOB)
  INTO l_acc FROM accounts
  WHERE is_postable = 'Y' AND is_active = 'Y'
  AND (company_id IS NULL OR company_id = TO_NUMBER(apex_application.g_x01));

  -- x02 = الموازنة الحالية ، x03 = 'PREV_BUDGET' أو 'PREV_ACTUAL' للنسخ
  IF apex_application.g_x03 = 'PREV_ACTUAL' THEN
    SELECT JSON_ARRAYAGG(JSON_OBJECT('ACCOUNT_ID' VALUE account_id,
             'M01' VALUE m01,'M02' VALUE m02,'M03' VALUE m03,'M04' VALUE m04,'M05' VALUE m05,'M06' VALUE m06,
             'M07' VALUE m07,'M08' VALUE m08,'M09' VALUE m09,'M10' VALUE m10,'M11' VALUE m11,'M12' VALUE m12)
           RETURNING CLOB)
    INTO l_lines FROM (
      SELECT l.account_id,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 1  THEN x.amt END), 2) m01,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 2  THEN x.amt END), 2) m02,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 3  THEN x.amt END), 2) m03,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 4  THEN x.amt END), 2) m04,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 5  THEN x.amt END), 2) m05,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 6  THEN x.amt END), 2) m06,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 7  THEN x.amt END), 2) m07,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 8  THEN x.amt END), 2) m08,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 9  THEN x.amt END), 2) m09,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 10 THEN x.amt END), 2) m10,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 11 THEN x.amt END), 2) m11,
             ROUND(SUM(CASE EXTRACT(MONTH FROM j.journal_date) WHEN 12 THEN x.amt END), 2) m12
      FROM journals j JOIN journal_lines l ON l.journal_id = j.journal_id
      JOIN accounts a ON a.account_id = l.account_id AND a.acc_type IN ('REV','EXP')
      CROSS APPLY (SELECT CASE a.acc_type WHEN 'REV' THEN l.credit_base - l.debit_base
                                          ELSE l.debit_base - l.credit_base END amt FROM dual) x
      WHERE j.status IN ('POSTED','REVERSED') AND j.company_id = TO_NUMBER(apex_application.g_x01)
      AND EXTRACT(YEAR FROM j.journal_date) = TO_NUMBER(apex_application.g_x04) - 1
      GROUP BY l.account_id);
  ELSE
    SELECT JSON_ARRAYAGG(JSON_OBJECT('ACCOUNT_ID' VALUE bl.account_id,
             'M01' VALUE m01,'M02' VALUE m02,'M03' VALUE m03,'M04' VALUE m04,'M05' VALUE m05,'M06' VALUE m06,
             'M07' VALUE m07,'M08' VALUE m08,'M09' VALUE m09,'M10' VALUE m10,'M11' VALUE m11,'M12' VALUE m12)
           RETURNING CLOB)
    INTO l_lines FROM budget_lines bl
    WHERE bl.budget_id = CASE WHEN apex_application.g_x03 = 'PREV_BUDGET'
                              THEN (SELECT budget_id FROM budgets
                                    WHERE company_id = TO_NUMBER(apex_application.g_x01)
                                    AND fy_year = TO_NUMBER(apex_application.g_x04) - 1)
                              ELSE TO_NUMBER(apex_application.g_x02) END;
  END IF;

  apex_util.prn('{"accounts":' || COALESCE(l_acc, TO_CLOB('[]')) ||
                ',"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
