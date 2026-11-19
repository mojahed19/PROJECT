DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM journal_lines WHERE account_id = :P10_PARENT_ID;
  RETURN CASE WHEN l_cnt > 0 THEN 'الحساب الأب عليه قيود، ولا يمكن أن يكون له حسابات فرعية' END;
END;
