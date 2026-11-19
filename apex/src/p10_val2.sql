DECLARE l_pcode VARCHAR2(20); l_lvl NUMBER;
BEGIN
  IF :P10_PARENT_ID IS NULL THEN
    l_lvl := 1;
  ELSE
    SELECT account_code, acc_level + 1 INTO l_pcode, l_lvl
    FROM accounts WHERE account_id = :P10_PARENT_ID;
  END IF;

  IF LENGTH(:P10_ACCOUNT_CODE) <> CASE l_lvl WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 4 ELSE 7 END THEN
    RETURN 'طول رقم الحساب في المستوى ' || l_lvl || ' يجب أن يكون '
           || CASE l_lvl WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 4 ELSE 7 END || ' خانات';
  END IF;
  IF l_pcode IS NOT NULL AND :P10_ACCOUNT_CODE NOT LIKE l_pcode || '%' THEN
    RETURN 'رقم الحساب يجب أن يبدأ برقم الحساب الأب ' || l_pcode;
  END IF;
  IF NOT REGEXP_LIKE(:P10_ACCOUNT_CODE, '^[0-9]+$') THEN
    RETURN 'رقم الحساب أرقام فقط';
  END IF;
  RETURN NULL;
END;
