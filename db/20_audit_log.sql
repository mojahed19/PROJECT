-- =====================================================================
--  20_audit_log.sql  -  سجل التدقيق: من أضاف / عدّل / حذف ماذا ومتى
--   جدول audit_log + Trigger على كل جدول رئيسي يُنشأ آلياً من القاموس:
--     إضافة: رقم المستند فقط ، تعديل: الحقول التي تغيّرت (القيمة القديمة ← الجديدة) ،
--     حذف: كل قيم السجل المحذوف (لإمكان الرجوع إليها)
--   آمن لإعادة التشغيل (CREATE OR REPLACE) ، ويتجاهل الجدول غير الموجود
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'AUDIT_LOG';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE audit_log (
        audit_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        changed_on  DATE           DEFAULT SYSDATE NOT NULL,
        changed_by  VARCHAR2(255),
        page_id     NUMBER,
        table_name  VARCHAR2(128)  NOT NULL,
        action      VARCHAR2(1)    NOT NULL CHECK (action IN ('I','U','D')),
        row_key     VARCHAR2(100),
        doc_ref     VARCHAR2(100),
        details     VARCHAR2(4000)
      )]';
    EXECUTE IMMEDIATE 'CREATE INDEX ix_audit_log_on  ON audit_log (changed_on)';
    EXECUTE IMMEDIATE 'CREATE INDEX ix_audit_log_tab ON audit_log (table_name, row_key)';
  END IF;
END;
/

DECLARE
  -- الجداول المراقبة (رؤوس المستندات والبيانات الأساسية ؛ سطور المستندات تنعكس في إجماليات رؤوسها)
  TYPE t_list IS TABLE OF VARCHAR2(128);
  l_tables t_list := t_list(
    'ACCOUNTS','ACCOUNT_SETTINGS','JOURNALS','VOUCHERS','CHEQUES','INVOICES','PURCHASE_INVOICES',
    'STOCK_TRANS','ITEMS','ITEM_UNITS','WAREHOUSES','APP_USERS','COMPANIES','FISCAL_YEARS',
    'EMPLOYEES','PAYROLL_RUNS','PAYROLL_ADJ','ANNUAL_INCENTIVES','EXCHANGE_RATES');
  l_pk   VARCHAR2(4000);
  l_ref  VARCHAR2(128);
  l_upd  CLOB;
  l_del  CLOB;
  l_sql  CLOB;
  l_cnt  NUMBER;
  FUNCTION v (p_side VARCHAR2, p_col VARCHAR2, p_type VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN p_type = 'DATE' THEN 'TO_CHAR(:' || p_side || '.' || p_col || ', ''DD/MM/YYYY HH24:MI'')'
                WHEN p_type LIKE 'TIMESTAMP%' THEN 'TO_CHAR(:' || p_side || '.' || p_col || ', ''DD/MM/YYYY HH24:MI'')'
                WHEN p_type IN ('VARCHAR2','CHAR','NVARCHAR2','NCHAR') THEN 'SUBSTR(:' || p_side || '.' || p_col || ', 1, 200)'
                ELSE 'TO_CHAR(:' || p_side || '.' || p_col || ')' END;
  END;
BEGIN
  FOR i IN 1 .. l_tables.COUNT LOOP
    SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = l_tables(i);
    CONTINUE WHEN l_cnt = 0;

    -- المفتاح الأساسي (قد يكون مركّباً)
    SELECT LISTAGG(':R.' || cc.column_name, ' || ''/'' || ') WITHIN GROUP (ORDER BY cc.position) INTO l_pk
    FROM   user_constraints c JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
    WHERE  c.table_name = l_tables(i) AND c.constraint_type = 'P';
    -- رقم المستند للعرض: أول عمود ينتهي بـ _NO أو CODE
    SELECT MAX(column_name) KEEP (DENSE_RANK FIRST ORDER BY CASE WHEN column_name LIKE '%\_NO' ESCAPE '\' THEN 1 ELSE 2 END, column_id)
    INTO   l_ref FROM user_tab_columns
    WHERE  table_name = l_tables(i) AND (column_name LIKE '%\_NO' ESCAPE '\' OR column_name LIKE '%\_CODE' ESCAPE '\');

    l_upd := NULL; l_del := NULL;
    FOR c IN (SELECT column_name, data_type FROM user_tab_columns
              WHERE  table_name = l_tables(i)
              AND    data_type NOT IN ('CLOB','BLOB','NCLOB','LONG','RAW','LONG RAW','BFILE')
              AND    column_name NOT IN ('UPDATED_ON','UPDATED_BY','LAST_UPDATED','LAST_UPDATED_ON','LAST_UPDATED_BY')
              ORDER  BY column_id) LOOP
      -- تغيّر الحقل (مع مراعاة القيم الفارغة)
      l_upd := l_upd || '    IF :OLD.' || c.column_name || ' <> :NEW.' || c.column_name
               || ' OR (:OLD.' || c.column_name || ' IS NULL AND :NEW.' || c.column_name || ' IS NOT NULL)'
               || ' OR (:OLD.' || c.column_name || ' IS NOT NULL AND :NEW.' || c.column_name || ' IS NULL) THEN l_d := l_d || ''' || c.column_name
               || ': '' || NVL(' || v('OLD', c.column_name, c.data_type) || ', ''-'') || '' ← '' || NVL(' || v('NEW', c.column_name, c.data_type) || ', ''-'') || ''; ''; END IF;' || CHR(10);
      l_del := l_del || '    IF :OLD.' || c.column_name || ' IS NOT NULL THEN l_d := l_d || ''' || c.column_name || ': '' || '
               || v('OLD', c.column_name, c.data_type) || ' || ''; ''; END IF;' || CHR(10);
    END LOOP;

    l_sql := 'CREATE OR REPLACE TRIGGER trg_aud_' || LOWER(SUBSTR(l_tables(i), 1, 20)) || CHR(10)
          || 'AFTER INSERT OR UPDATE OR DELETE ON ' || l_tables(i) || ' FOR EACH ROW' || CHR(10)
          || 'DECLARE' || CHR(10)
          || '  l_d VARCHAR2(32767); l_a VARCHAR2(1); l_key VARCHAR2(100); l_ref VARCHAR2(100); l_user VARCHAR2(255); l_page NUMBER;' || CHR(10)
          || 'BEGIN' || CHR(10)
          || '  IF INSERTING THEN l_a := ''I''; ELSIF UPDATING THEN l_a := ''U''; ELSE l_a := ''D''; END IF;' || CHR(10)
          || '  IF DELETING THEN' || CHR(10)
          || '    l_key := SUBSTR(' || NVL(REPLACE(l_pk, ':R.', ':OLD.'), 'NULL') || ', 1, 100);' || CHR(10)
          || CASE WHEN l_ref IS NOT NULL THEN '    l_ref := SUBSTR(:OLD.' || l_ref || ', 1, 100);' || CHR(10) END
          || l_del
          || '  ELSE' || CHR(10)
          || '    l_key := SUBSTR(' || NVL(REPLACE(l_pk, ':R.', ':NEW.'), 'NULL') || ', 1, 100);' || CHR(10)
          || CASE WHEN l_ref IS NOT NULL THEN '    l_ref := SUBSTR(:NEW.' || l_ref || ', 1, 100);' || CHR(10) END
          || '    IF UPDATING THEN' || CHR(10)
          || l_upd
          || '      IF l_d IS NULL THEN RETURN; END IF;' || CHR(10)
          || '    END IF;' || CHR(10)
          || '  END IF;' || CHR(10)
          || '  BEGIN' || CHR(10)
          || '    l_user := SYS_CONTEXT(''APEX$SESSION'', ''APP_USER'');' || CHR(10)
          || '    l_page := TO_NUMBER(V(''APP_PAGE_ID''));' || CHR(10)
          || '  EXCEPTION WHEN OTHERS THEN NULL;' || CHR(10)
          || '  END;' || CHR(10)
          || '  INSERT INTO audit_log (changed_by, page_id, table_name, action, row_key, doc_ref, details)' || CHR(10)
          || '  VALUES (NVL(l_user, SYS_CONTEXT(''USERENV'', ''SESSION_USER'')), l_page, ''' || l_tables(i) || ''', l_a, l_key, l_ref, SUBSTR(l_d, 1, 4000));' || CHR(10)
          || 'END;';
    EXECUTE IMMEDIATE l_sql;
    DBMS_OUTPUT.PUT_LINE('TRIGGER trg_aud_' || LOWER(SUBSTR(l_tables(i), 1, 20)) || ' (' || l_tables(i) || ')');
  END LOOP;
END;
/
