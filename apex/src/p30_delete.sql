BEGIN
  DELETE FROM journals
  WHERE  journal_id = TO_NUMBER(apex_application.g_x01)
  AND    status = 'DRAFT' AND source_type = 'MANUAL'
  AND    (:G_USER_ROLE = 'GM' OR company_id = :G_COMPANY_ID);
  apex_json.open_object;
  apex_json.write('ok', SQL%ROWCOUNT = 1);
  apex_json.close_object;
END;
