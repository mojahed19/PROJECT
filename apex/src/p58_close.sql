DECLARE
  -- إغلاق الوردية: تصبح بانتظار المراجعة والاعتماد
  s sales_shifts%ROWTYPE; l_cnt NUMBER;
BEGIN
  SELECT * INTO s FROM sales_shifts WHERE shift_id = :P58_SHIFT_ID FOR UPDATE;
  IF s.status NOT IN ('OPEN','RETURNED') THEN
    apex_error.add_error(p_message => 'الوردية مغلقة من قبل', p_display_location => apex_error.c_inline_in_notification); RETURN;
  END IF;
  IF s.user_name <> :APP_USER AND :G_USER_ROLE <> 'ADMIN' THEN
    apex_error.add_error(p_message => 'يغلق الوردية صاحبها فقط', p_display_location => apex_error.c_inline_in_notification); RETURN;
  END IF;
  SELECT COUNT(*) INTO l_cnt FROM invoices WHERE shift_id = s.shift_id AND status = 'DRAFT';
  IF l_cnt > 0 THEN
    apex_error.add_error(p_message => 'في الوردية ' || l_cnt || ' فاتورة مسودة: احفظها نهائياً أو احذفها قبل الإغلاق',
                         p_display_location => apex_error.c_inline_in_notification); RETURN;
  END IF;
  UPDATE sales_shifts SET status = 'DRAFT', closed_on = SYSDATE, notes = :P58_NOTES, return_note = NULL WHERE shift_id = s.shift_id;
  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('SHIFT', s.shift_id, 'CLOSE', s.status, 'DRAFT', :APP_USER);
  apex_application.g_print_success_message := 'تم إغلاق الوردية - بانتظار المراجعة والاعتماد';
END;
