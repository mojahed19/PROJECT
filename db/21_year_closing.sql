-- =====================================================================
--  21_year_closing.sql  -  إقفال السنة المالية
--   fy_close  : قيد إقفال (نوع CL ، مصدر CLOSING) بتاريخ آخر يوم في السنة يصفّر حسابات الإيرادات والمصروفات
--               والفرق (صافي الربح أو الخسارة) إلى الأرباح المرحّلة (إعداد RETAINED_EARNINGS) ، ثم تُقفل السنة
--               وتُنشأ السنة التالية إن لم تكن موجودة. الإدخال في السنة المقفلة ممنوع (فحص is_closed في كل الشاشات)
--   fy_reopen : يحذف قيد الإقفال ويفتح السنة (للمدير ، إن لم تكن السنة التالية مقفلة)
--   التقارير التي تعرض نتيجة الفترة (قائمة الدخل ، الإيضاحات ، الموازنة ، لوحة المدير) تتجاهل قيد الإقفال
-- =====================================================================
SET DEFINE OFF

-- مصدر القيد الجديد CLOSING
DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_constraints WHERE constraint_name = 'JOURNALS_SOURCE_CK';
  IF l_cnt > 0 THEN EXECUTE IMMEDIATE 'ALTER TABLE journals DROP CONSTRAINT journals_source_ck'; END IF;
  EXECUTE IMMEDIATE q'[ALTER TABLE journals ADD CONSTRAINT journals_source_ck
      CHECK (source_type IN ('MANUAL','VOUCHER','INVOICE','PAYROLL','REVERSAL','OPENING','PURCHASE','CHEQUE','CLOSING'))]';
END;
/

-- حساب الأرباح المرحّلة 32 / 3201 / 3201001 (إن لم يوجد) وربطه بالإعداد RETAINED_EARNINGS
DECLARE
  l_hq NUMBER;
  PROCEDURE acc (p_code VARCHAR2, p_name VARCHAR2) IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt FROM accounts WHERE account_code = p_code;
    IF l_cnt > 0 THEN RETURN; END IF;
    INSERT INTO accounts (account_code, name_ar, parent_id, acc_level, acc_type, nature, cash_bank, is_active)
    VALUES (p_code, p_name,
            (SELECT account_id FROM accounts WHERE account_code = SUBSTR(p_code, 1, CASE LENGTH(p_code) WHEN 2 THEN 1 WHEN 4 THEN 2 ELSE 4 END)),
            CASE LENGTH(p_code) WHEN 2 THEN 2 WHEN 4 THEN 3 ELSE 4 END, 'EQUITY', 'C', 'N', 'Y');
    DBMS_OUTPUT.PUT_LINE('ADDED ' || p_code || ' ' || p_name);
  END;
BEGIN
  SELECT company_id INTO l_hq FROM companies WHERE is_parent = 'Y';
  acc('32',      'الأرباح المحتجزة');
  acc('3201',    'أرباح وخسائر مرحلة');
  acc('3201001', 'أرباح وخسائر مرحلة');
  MERGE INTO account_settings s
  USING (SELECT l_hq company_id, 'RETAINED_EARNINGS' setting_code,
                (SELECT account_id FROM accounts WHERE account_code = '3201001') account_id FROM dual) x
  ON (s.company_id = x.company_id AND s.setting_code = x.setting_code)
  WHEN NOT MATCHED THEN INSERT (company_id, setting_code, account_id) VALUES (x.company_id, x.setting_code, x.account_id);
  COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE fy_close (p_year IN NUMBER, p_user IN VARCHAR2, p_msg OUT VARCHAR2) IS
  fy        fiscal_years%ROWTYPE;
  l_cnt     NUMBER;
  l_base    VARCHAR2(3);
  l_ret     NUMBER;
  l_jid     NUMBER;
  l_seq     NUMBER;
  l_no      VARCHAR2(30);
  l_line    NUMBER;
  l_sum     NUMBER;
  l_dr      NUMBER;
  l_cr      NUMBER;
  l_msg     VARCHAR2(4000);
BEGIN
  SELECT * INTO fy FROM fiscal_years WHERE fy_year = p_year FOR UPDATE;
  IF fy.is_closed = 'Y' THEN raise_application_error(-20101, 'السنة ' || p_year || ' مقفلة بالفعل'); END IF;

  -- السنة السابقة يجب أن تكون مقفلة أولاً
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE fy_year < p_year AND is_closed = 'N';
  IF l_cnt > 0 THEN raise_application_error(-20102, 'أقفل السنوات السابقة أولاً'); END IF;

  -- لا مستندات معلّقة في السنة (غير مرحّلة)
  SELECT COUNT(*) INTO l_cnt FROM journals
  WHERE  journal_date BETWEEN fy.start_date AND fy.end_date AND status IN ('DRAFT','RETURNED','REVIEWED','APPROVED');
  IF l_cnt > 0 THEN raise_application_error(-20103, 'يوجد ' || l_cnt || ' قيد غير مرحّل في السنة: رحّله أو احذفه قبل الإقفال'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM vouchers
  WHERE  voucher_date BETWEEN fy.start_date AND fy.end_date AND status IN ('DRAFT','RETURNED','REVIEWED','APPROVED');
  IF l_cnt > 0 THEN raise_application_error(-20104, 'يوجد ' || l_cnt || ' إذن غير مرحّل في السنة: رحّله أو احذفه قبل الإقفال'); END IF;

  SELECT currency_code INTO l_base FROM currencies WHERE is_base = 'Y';

  FOR c IN (SELECT DISTINCT j.company_id FROM journals j
            WHERE j.journal_date BETWEEN fy.start_date AND fy.end_date AND j.status IN ('POSTED','REVERSED')) LOOP
    SELECT MAX(s.account_id) INTO l_ret FROM account_settings s
    WHERE  s.setting_code = 'RETAINED_EARNINGS'
    AND    s.company_id IN (c.company_id, (SELECT company_id FROM companies WHERE is_parent = 'Y'));
    IF l_ret IS NULL THEN raise_application_error(-20105, 'حدد حساب الأرباح المرحّلة (RETAINED_EARNINGS) في الحسابات الافتراضية'); END IF;

    l_jid := NULL; l_line := 0; l_sum := 0; l_dr := 0; l_cr := 0;
    FOR a IN (SELECT jl.account_id, SUM(jl.debit_base - jl.credit_base) bal
              FROM   journal_lines jl
              JOIN   journals j ON j.journal_id = jl.journal_id
              JOIN   accounts ac ON ac.account_id = jl.account_id
              WHERE  j.company_id = c.company_id
              AND    j.journal_date BETWEEN fy.start_date AND fy.end_date
              AND    j.status IN ('POSTED','REVERSED') AND j.source_type <> 'CLOSING'
              AND    ac.acc_type IN ('REV','EXP')
              GROUP  BY jl.account_id
              HAVING ROUND(SUM(jl.debit_base - jl.credit_base), 4) <> 0
              ORDER  BY MIN(ac.account_code)) LOOP
      IF l_jid IS NULL THEN
        UPDATE doc_sequences SET last_no = last_no + 1
        WHERE  company_id = c.company_id AND doc_type = 'CL' AND fy_year = p_year
        RETURNING last_no INTO l_seq;
        IF SQL%ROWCOUNT = 0 THEN
          INSERT INTO doc_sequences VALUES (c.company_id, 'CL', p_year, 1);
          l_seq := 1;
        END IF;
        l_no := 'CL-' || p_year || '-' || LPAD(l_seq, 5, '0');
        INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                              description, status, source_type, source_id, total_debit, total_credit,
                              created_by, posted_by, posted_on)
        VALUES (c.company_id, 'CL', l_no, fy.end_date, l_base, 1,
                'قيد إقفال السنة المالية ' || p_year || ' (ترحيل الإيرادات والمصروفات إلى الأرباح المرحّلة)',
                'POSTED', 'CLOSING', fy.fy_id, 0, 0, p_user, p_user, SYSDATE)
        RETURNING journal_id INTO l_jid;
      END IF;
      l_line := l_line + 1;
      -- عكس رصيد الحساب حتى يصبح صفراً
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
      VALUES (l_jid, l_line, a.account_id,
              GREATEST(-a.bal, 0), GREATEST(a.bal, 0), GREATEST(-a.bal, 0), GREATEST(a.bal, 0),
              'إقفال ' || p_year);
      l_sum := l_sum + a.bal;
      l_dr := l_dr + GREATEST(-a.bal, 0); l_cr := l_cr + GREATEST(a.bal, 0);
    END LOOP;

    IF l_jid IS NOT NULL THEN
      -- الفرق إلى الأرباح المرحّلة: l_sum > 0 خسارة (مدين) ، l_sum < 0 ربح (دائن)
      IF ROUND(l_sum, 4) <> 0 THEN
        l_line := l_line + 1;
        INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
        VALUES (l_jid, l_line, l_ret, GREATEST(l_sum, 0), GREATEST(-l_sum, 0), GREATEST(l_sum, 0), GREATEST(-l_sum, 0),
                CASE WHEN l_sum < 0 THEN 'صافي ربح ' ELSE 'صافي خسارة ' END || p_year);
        l_dr := l_dr + GREATEST(l_sum, 0); l_cr := l_cr + GREATEST(-l_sum, 0);
      END IF;
      UPDATE journals SET total_debit = l_dr, total_credit = l_cr WHERE journal_id = l_jid;
      l_msg := l_msg || CASE WHEN l_msg IS NOT NULL THEN ' ، ' END || 'قيد الإقفال ' || l_no
               || CASE WHEN l_sum < 0 THEN ' (صافي ربح ' ELSE ' (صافي خسارة ' END
               || TO_CHAR(ABS(l_sum), 'FM999G999G999G990D00') || ')';
    END IF;
  END LOOP;

  UPDATE fiscal_years SET is_closed = 'Y' WHERE fy_id = fy.fy_id;

  -- السنة التالية (مفتوحة) إن لم تكن موجودة
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE fy_year = p_year + 1;
  IF l_cnt = 0 THEN
    INSERT INTO fiscal_years (fy_year, start_date, end_date) VALUES (p_year + 1, fy.end_date + 1, ADD_MONTHS(fy.end_date, 12));
    l_msg := l_msg || CASE WHEN l_msg IS NOT NULL THEN ' ، ' END || 'وأُنشئت السنة ' || (p_year + 1);
  END IF;

  p_msg := 'أُقفلت السنة ' || p_year || CASE WHEN l_msg IS NOT NULL THEN ': ' || l_msg END;
EXCEPTION WHEN NO_DATA_FOUND THEN
  raise_application_error(-20100, 'السنة ' || p_year || ' غير موجودة في السنوات المالية');
END;
/

CREATE OR REPLACE PROCEDURE fy_reopen (p_year IN NUMBER, p_user IN VARCHAR2, p_msg OUT VARCHAR2) IS
  fy    fiscal_years%ROWTYPE;
  l_cnt NUMBER;
BEGIN
  SELECT * INTO fy FROM fiscal_years WHERE fy_year = p_year FOR UPDATE;
  IF fy.is_closed = 'N' THEN raise_application_error(-20111, 'السنة ' || p_year || ' مفتوحة بالفعل'); END IF;
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years WHERE fy_year > p_year AND is_closed = 'Y';
  IF l_cnt > 0 THEN raise_application_error(-20112, 'افتح السنوات اللاحقة المقفلة أولاً'); END IF;

  DELETE FROM journals WHERE source_type = 'CLOSING' AND source_id = fy.fy_id;
  l_cnt := SQL%ROWCOUNT;
  UPDATE fiscal_years SET is_closed = 'N' WHERE fy_id = fy.fy_id;
  p_msg := 'فُتحت السنة ' || p_year || CASE WHEN l_cnt > 0 THEN ' وحُذف قيد الإقفال' END || ' (بواسطة ' || p_user || ')';
EXCEPTION WHEN NO_DATA_FOUND THEN
  raise_application_error(-20100, 'السنة ' || p_year || ' غير موجودة في السنوات المالية');
END;
/
