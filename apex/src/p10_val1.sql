DECLARE l_lvl NUMBER;
BEGIN
  IF :P10_PARENT_ID IS NULL THEN RETURN NULL; END IF;
  SELECT acc_level INTO l_lvl FROM accounts WHERE account_id = :P10_PARENT_ID;
  IF l_lvl >= 4 THEN
    RETURN 'لا يمكن إضافة حساب تحت حساب تحليلي (مستوى 4)';
  END IF;
  IF :P10_ACCOUNT_ID = :P10_PARENT_ID THEN
    RETURN 'الحساب لا يكون أباً لنفسه';
  END IF;
  RETURN NULL;
END;
