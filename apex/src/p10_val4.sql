DECLARE l_ch NUMBER; l_mv NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_ch FROM accounts      WHERE parent_id  = :P10_ACCOUNT_ID;
  SELECT COUNT(*) INTO l_mv FROM journal_lines WHERE account_id = :P10_ACCOUNT_ID;
  IF l_ch > 0 THEN RETURN 'لا يمكن حذف حساب له حسابات فرعية'; END IF;
  IF l_mv > 0 THEN RETURN 'لا يمكن حذف حساب عليه قيود. يمكنك إيقافه بدلاً من الحذف'; END IF;
  RETURN NULL;
END;
