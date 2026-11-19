-- =====================================================================
--  set_password.sql : create an app user (or reset a password)
--  Run as the application schema (e.g. MOSS) from the project folder:
--     sqlplus MOSS@localhost:1521/orclpdb @install/set_password.sql
--  The password is typed hidden and stored only as a SHA-256 hash.
-- =====================================================================
SET VERIFY OFF FEEDBACK OFF SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

ACCEPT app_user CHAR DEFAULT 'ADMIN' PROMPT 'App username [ADMIN]: '
ACCEPT app_pass CHAR HIDE PROMPT 'New password: '
ACCEPT app_role CHAR DEFAULT 'GM' PROMPT 'Role GM/ACCOUNTANT/HR/STORE/CASHIER/USER [GM]: '

-- add the password column on databases installed before this change
DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tab_columns
  WHERE table_name = 'APP_USERS' AND column_name = 'PASSWORD_HASH';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE app_users ADD (password_hash VARCHAR2(64))';
  END IF;
END;
/

DECLARE
  l_user VARCHAR2(100) := UPPER(TRIM('&app_user'));
  l_hash VARCHAR2(64);
  l_parent NUMBER;
BEGIN
  IF LENGTH(q'~&app_pass~') < 6 THEN
    raise_application_error(-20001, 'Password must be at least 6 characters');
  END IF;
  SELECT RAWTOHEX(STANDARD_HASH(l_user || ':' || q'~&app_pass~', 'SHA256')) INTO l_hash FROM dual;
  SELECT company_id INTO l_parent FROM companies WHERE is_parent = 'Y';

  MERGE INTO app_users u
  USING (SELECT l_user user_name FROM dual) s
  ON (u.user_name = s.user_name)
  WHEN MATCHED THEN UPDATE SET u.password_hash = l_hash, u.is_active = 'Y'
  WHEN NOT MATCHED THEN
    INSERT (user_name, full_name, company_id, user_role, is_active, password_hash)
    VALUES (l_user, l_user, l_parent, UPPER('&app_role'), 'Y', l_hash);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('OK - user ' || l_user || ' can now sign in to the app.');
END;
/
UNDEFINE app_pass
EXIT
