BEGIN
  SELECT u.company_id, u.user_role
  INTO   :G_COMPANY_ID, :G_USER_ROLE
  FROM   app_users u
  WHERE  u.user_name = UPPER(:APP_USER)
  AND    u.is_active = 'Y';

  SELECT company_id INTO :G_PARENT_ID FROM companies WHERE is_parent = 'Y';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    raise_application_error(-20000, 'المستخدم غير معرّف في جدول المستخدمين أو غير فعّال');
END;
