DECLARE
  -- فتح وردية جديدة للمستخدم (رقمها 17 + السنة + 5 خانات)
  l_cnt NUMBER; l_seq NUMBER; l_co NUMBER := NVL(:G_COMPANY_ID, :G_PARENT_ID); l_y NUMBER := EXTRACT(YEAR FROM SYSDATE);
BEGIN
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN
    apex_error.add_error(p_message => 'فتح الوردية من صلاحية المدخل (البائع)', p_display_location => apex_error.c_inline_in_notification);
    RETURN;
  END IF;
  SELECT COUNT(*) INTO l_cnt FROM sales_shifts WHERE user_name = :APP_USER AND status IN ('OPEN','RETURNED');
  IF l_cnt > 0 THEN
    apex_error.add_error(p_message => 'لديك وردية مفتوحة أو معادة لم تُغلق بعد', p_display_location => apex_error.c_inline_in_notification);
    RETURN;
  END IF;
  UPDATE doc_sequences SET last_no = last_no + 1 WHERE company_id = l_co AND doc_type = '17' AND fy_year = l_y
  RETURNING last_no INTO l_seq;
  IF SQL%ROWCOUNT = 0 THEN
    INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (l_co, '17', l_y, 1); l_seq := 1;
  END IF;
  INSERT INTO sales_shifts (company_id, shift_no, user_name, status)
  VALUES (l_co, '17' || l_y || LPAD(l_seq, 5, '0'), :APP_USER, 'OPEN')
  RETURNING shift_id INTO :P58_SHIFT_ID;
  INSERT INTO doc_actions (doc_type, doc_id, action, to_status, action_by) VALUES ('SHIFT', :P58_SHIFT_ID, 'OPEN', 'OPEN', :APP_USER);
  apex_application.g_print_success_message := 'تم فتح الوردية';
END;
