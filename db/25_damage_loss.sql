-- =====================================================================
--  25_damage_loss.sql  -  قيد خسائر التوالف عند التصفير (اختياري)
--   صرف التوالف (DAMAGE) يُنقص كمية المخزن وقيمته في دفتر الأصناف بدون قيد ، فيبقى حساب المخزون في الدفاتر
--   أكبر من المخزون الفعلي حتى قرار التصفير. عند ترحيل التصفير (DAMAGE_WO) يُنشأ قيد:
--       من ح/ خسائر التوالف (إعداد DAMAGE_LOSS)   إلى ح/ المخزون (إعداد INVENTORY)
--   بقيمة الكمية المصفّاة × متوسط تكلفة التوالف المصروفة لنفس الصنف في نفس المخزن.
--   اختياري: يُنشأ القيد فقط إذا كان الإعداد DAMAGE_LOSS معرّفاً (يُحذف من الحسابات الافتراضية لإيقافه)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_hq NUMBER;
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2) IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_code = p_code;
    IF l_cnt > 0 THEN RETURN; END IF;
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature, cash_bank, is_active)
    VALUES (p_code, p_name, (SELECT account_id FROM accounts WHERE account_code = SUBSTR(p_code, 1, CASE LENGTH(p_code) WHEN 4 THEN 2 ELSE 4 END)),
            CASE LENGTH(p_code) WHEN 4 THEN 3 ELSE 4 END, 'EXP', 'D', 'N', 'Y');
    DBMS_OUTPUT.PUT_LINE('ADDED ' || p_code || ' ' || p_name);
  END;
BEGIN
  SELECT company_id INTO l_hq FROM companies WHERE is_parent = 'Y';
  acc('5202',    'خسائر المخزون');
  acc('5202001', 'خسائر التوالف');
  MERGE INTO account_settings s
  USING (SELECT l_hq company_id, 'DAMAGE_LOSS' setting_code, (SELECT account_id FROM accounts WHERE account_code = '5202001') account_id FROM dual) x
  ON (s.company_id = x.company_id AND s.setting_code = x.setting_code)
  WHEN NOT MATCHED THEN INSERT (company_id, setting_code, account_id) VALUES (x.company_id, x.setting_code, x.account_id);
  DBMS_OUTPUT.PUT_LINE('SETTING DAMAGE_LOSS ' || SQL%ROWCOUNT);
  COMMIT;
END;
/

-- يُستدعى من ترحيل حركة المخزون (صفحة 90) عند التصفير ، ويرجع رقم القيد أو NULL (بدون إعداد أو بدون قيمة)
CREATE OR REPLACE FUNCTION damage_wo_journal (p_trans_id IN NUMBER, p_user IN VARCHAR2) RETURN NUMBER IS
  t       stock_trans%ROWTYPE;
  l_loss  NUMBER;
  l_inv   NUMBER;
  l_acc   NUMBER;
  l_base  VARCHAR2(3);
  l_jid   NUMBER;
  l_desc  VARCHAR2(500);
BEGIN
  SELECT * INTO t FROM stock_trans WHERE trans_id = p_trans_id;
  IF t.trans_type <> 'DAMAGE_WO' THEN RETURN NULL; END IF;

  SELECT MAX(account_id) INTO l_acc FROM account_settings WHERE company_id = t.company_id AND setting_code = 'DAMAGE_LOSS';
  IF l_acc IS NULL THEN RETURN NULL; END IF;                     -- القيد اختياري
  SELECT MAX(account_id) INTO l_inv FROM account_settings WHERE company_id = t.company_id AND setting_code = 'INVENTORY';
  IF l_inv IS NULL THEN raise_application_error(-20010, 'لم يُعرَّف الحساب الافتراضي INVENTORY'); END IF;

  -- القيمة: الكمية المصفّاة بالوحدة الصغرى × متوسط تكلفة التوالف المصروفة (وإلا تكلفة السطر)
  SELECT ROUND(NVL(SUM(l.qty * l.factor * NVL(
           (SELECT SUM(-dl.value_base) / NULLIF(SUM(-dl.qty_base), 0)
            FROM   stock_trans_lines dl
            JOIN   stock_trans dt ON dt.trans_id = dl.trans_id AND dt.trans_type = 'DAMAGE' AND dt.status = 'POSTED'
            WHERE  dl.item_id = l.item_id AND dl.warehouse_id = l.warehouse_id), l.cost_base)), 0), 2)
  INTO   l_loss
  FROM   stock_trans_lines l
  WHERE  l.trans_id = p_trans_id;
  IF l_loss <= 0 THEN RETURN NULL; END IF;

  SELECT currency_code INTO l_base FROM currencies WHERE is_base = 'Y';
  l_desc := SUBSTR('خسائر توالف - تصفير ' || t.trans_no || CASE WHEN t.description IS NOT NULL THEN ' - ' || t.description END, 1, 500);
  INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate, description,
                        status, source_type, source_id, total_debit, total_credit, created_by, posted_by, posted_on)
  VALUES (t.company_id, 'ADJ', t.trans_no, t.trans_date, l_base, 1, l_desc,
          'POSTED', 'MANUAL', t.trans_id, l_loss, l_loss, p_user, p_user, SYSDATE)
  RETURNING journal_id INTO l_jid;
  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
  VALUES (l_jid, 1, l_acc, l_loss, 0, l_loss, 0, l_desc);
  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
  VALUES (l_jid, 2, l_inv, 0, l_loss, 0, l_loss, l_desc);
  RETURN l_jid;
END;
/
