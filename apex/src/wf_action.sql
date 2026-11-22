DECLARE
  -- دورة المستند: مسودة -> مُراجَع -> معتمد -> مرحّل ، والإعادة للمدخل مع السبب
  -- المراجع: مراجعة / إلغاء المراجعة / إعادة ، المعتمد: اعتماد / إلغاء الاعتماد / إعادة / ترحيل ، مدير النظام: الكل
  l_id    NUMBER        := :__ITEM__;
  l_req   VARCHAR2(20)  := :REQUEST;
  l_role  VARCHAR2(20)  := :G_USER_ROLE;
  l_note  VARCHAR2(500) := SUBSTR(TRIM(:__NOTE__), 1, 500);
  l_st    VARCHAR2(10);
  l_new   VARCHAR2(10);
  l_err   VARCHAR2(400);
  l_msg   VARCHAR2(200);
  FUNCTION has (p_roles VARCHAR2) RETURN BOOLEAN IS
  BEGIN RETURN l_role = 'ADMIN' OR INSTR(',' || p_roles || ',', ',' || l_role || ',') > 0; END;
BEGIN
  IF apex_error.have_errors_occurred THEN RETURN; END IF;
  IF l_id IS NULL THEN
    l_err := 'احفظ المستند أولاً';
  ELSE
    SELECT status INTO l_st FROM __TABLE__ WHERE __IDCOL__ = l_id FOR UPDATE;
    CASE l_req
      WHEN 'REVIEW' THEN
        IF NOT has('REVIEWER') THEN l_err := 'المراجعة من صلاحية المراجع';
        ELSIF l_st <> 'DRAFT' THEN l_err := 'لا يُراجع إلا المستند في حالة مسودة';
        ELSE l_new := 'REVIEWED'; l_msg := 'تمت المراجعة'; END IF;
      WHEN 'UNREVIEW' THEN
        IF NOT has('REVIEWER') THEN l_err := 'إلغاء المراجعة من صلاحية المراجع';
        ELSIF l_st <> 'REVIEWED' THEN l_err := 'المستند ليس في حالة مُراجَع (ربما تم اعتماده)';
        ELSE l_new := 'DRAFT'; l_msg := 'تم إلغاء المراجعة'; END IF;
      WHEN 'APPROVE' THEN
        IF NOT has('APPROVER') THEN l_err := 'الاعتماد من صلاحية المعتمد';
        ELSIF l_st <> 'REVIEWED' THEN l_err := 'لا يُعتمد إلا المستند المُراجَع';
        ELSE l_new := 'APPROVED'; l_msg := 'تم الاعتماد'; END IF;
      WHEN 'UNAPPROVE' THEN
        IF NOT has('APPROVER') THEN l_err := 'إلغاء الاعتماد من صلاحية المعتمد';
        ELSIF l_st <> 'APPROVED' THEN l_err := 'المستند ليس في حالة معتمد (ربما تم ترحيله)';
        ELSE l_new := 'REVIEWED'; l_msg := 'تم إلغاء الاعتماد'; END IF;
      WHEN 'RETURN' THEN
        IF NOT ((has('REVIEWER') AND l_st IN ('DRAFT','REVIEWED')) OR (has('APPROVER') AND l_st IN ('REVIEWED','APPROVED'))) THEN
          l_err := 'لا يمكنك إعادة هذا المستند في حالته الحالية';
        ELSIF l_note IS NULL THEN l_err := 'اكتب سبب الإعادة';
        ELSE l_new := 'RETURNED'; l_msg := 'تمت إعادة المستند للمدخل'; END IF;
      WHEN 'POST' THEN
        IF '__CANPOST__' <> 'Y' THEN l_err := 'هذا المستند لا يُرحّل';
        ELSIF NOT has('APPROVER') THEN l_err := 'الترحيل من صلاحية المعتمد';
        ELSIF l_st <> 'APPROVED' THEN l_err := 'لا يُرحّل إلا المستند المعتمد';
        ELSE l_new := 'POSTED'; l_msg := 'تم الترحيل'; END IF;
      ELSE l_err := 'إجراء غير معروف';
    END CASE;
  END IF;

  IF l_err IS NOT NULL THEN
    apex_error.add_error(p_message => l_err, p_display_location => apex_error.c_inline_in_notification);
    RETURN;
  END IF;

  IF l_req = 'POST' THEN
    __POST__
  END IF;

  UPDATE __TABLE__
  SET    status      = l_new,
         reviewed_by = CASE WHEN l_req = 'REVIEW' THEN :APP_USER WHEN l_req IN ('UNREVIEW','RETURN') THEN NULL ELSE reviewed_by END,
         reviewed_on = CASE WHEN l_req = 'REVIEW' THEN SYSDATE   WHEN l_req IN ('UNREVIEW','RETURN') THEN NULL ELSE reviewed_on END,
         approved_by = CASE WHEN l_req = 'APPROVE' THEN :APP_USER WHEN l_req IN ('UNAPPROVE','RETURN') THEN NULL ELSE approved_by END,
         approved_on = CASE WHEN l_req = 'APPROVE' THEN SYSDATE   WHEN l_req IN ('UNAPPROVE','RETURN') THEN NULL ELSE approved_on END,
         return_note = CASE WHEN l_req = 'RETURN' THEN l_note ELSE return_note END
  WHERE  __IDCOL__ = l_id;

  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, note, action_by)
  VALUES ('__DOC__', l_id, l_req, l_st, l_new, l_note, :APP_USER);

  :__NOTE__ := NULL;
  apex_application.g_print_success_message := l_msg;
END;
