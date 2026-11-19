DECLARE l_old NUMBER; l_ch NUMBER;
BEGIN
  IF :P10_ACCOUNT_ID IS NULL THEN RETURN NULL; END IF;
  SELECT parent_id INTO l_old FROM accounts WHERE account_id = :P10_ACCOUNT_ID;
  SELECT COUNT(*) INTO l_ch FROM accounts WHERE parent_id = :P10_ACCOUNT_ID;
  IF l_ch > 0 AND NVL(TO_CHAR(l_old), '#') <> NVL(:P10_PARENT_ID, '#') THEN
    RETURN 'لا يمكن نقل حساب له حسابات فرعية';
  END IF;
  RETURN NULL;
END;
