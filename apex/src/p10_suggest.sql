DECLARE
  l_parent accounts%ROWTYPE;
  l_len    PLS_INTEGER;
  l_max    VARCHAR2(20);
BEGIN
  IF :P10_PARENT_ID IS NULL THEN
    :P10_ACC_LEVEL := 1;
    SELECT TO_CHAR(NVL(MAX(TO_NUMBER(account_code)), 0) + 1)
    INTO   :P10_ACCOUNT_CODE
    FROM   accounts WHERE acc_level = 1;
    RETURN;
  END IF;

  SELECT * INTO l_parent FROM accounts WHERE account_id = :P10_PARENT_ID;
  :P10_ACC_LEVEL := l_parent.acc_level + 1;
  :P10_ACC_TYPE  := l_parent.acc_type;
  :P10_NATURE    := l_parent.nature;

  -- طول الجزء الخاص بالمستوى: م2 = 1 خانة ، م3 = 2 خانة ، م4 = 3 خانات
  l_len := CASE :P10_ACC_LEVEL WHEN 2 THEN 1 WHEN 3 THEN 2 ELSE 3 END;

  SELECT MAX(account_code) INTO l_max
  FROM   accounts WHERE parent_id = l_parent.account_id;

  :P10_ACCOUNT_CODE := l_parent.account_code ||
       LPAD(NVL(TO_NUMBER(SUBSTR(l_max, -l_len)), 0) + 1, l_len, '0');
END;
