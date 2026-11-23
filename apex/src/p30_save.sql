DECLARE
  l_clob     CLOB := apex_application.g_clob_01;
  l_action   VARCHAR2(10) := apex_application.g_x01;
  l_errs     apex_t_varchar2 := apex_t_varchar2();

  l_id       NUMBER;
  l_company  NUMBER;
  l_jt       VARCHAR2(10);
  l_date_s   VARCHAR2(20);
  l_date     DATE;
  l_cur      VARCHAR2(3);
  l_rate     NUMBER;
  l_ref      VARCHAR2(50);
  l_desc     VARCHAR2(500);

  l_status   VARCHAR2(10);
  l_no       VARCHAR2(30);
  l_src      VARCHAR2(10);
  l_prefix   VARCHAR2(10);
  l_seq      NUMBER;
  l_cnt      NUMBER;
  l_dr       NUMBER := 0;
  l_cr       NUMBER := 0;
  l_drb      NUMBER := 0;
  l_crb      NUMBER := 0;
  l_lines    NUMBER := 0;
  l_last     NUMBER;

  PROCEDURE err (p VARCHAR2) IS
  BEGIN l_errs.EXTEND; l_errs(l_errs.COUNT) := p; END;
BEGIN
  ---------------------------------------------------------------- قراءة الرأس
  SELECT h.journal_id, h.company_id, h.jt_code, h.journal_date,
         h.currency_code, h.exchange_rate, h.ref_no, h.description
  INTO   l_id, l_company, l_jt, l_date_s, l_cur, l_rate, l_ref, l_desc
  FROM   JSON_TABLE(l_clob, '$.header' COLUMNS (
           journal_id    NUMBER        PATH '$.JOURNAL_ID',
           company_id    NUMBER        PATH '$.COMPANY_ID',
           jt_code       VARCHAR2(10)  PATH '$.JT_CODE',
           journal_date  VARCHAR2(20)  PATH '$.JOURNAL_DATE',
           currency_code VARCHAR2(3)   PATH '$.CURRENCY_CODE',
           exchange_rate NUMBER        PATH '$.EXCHANGE_RATE',
           ref_no        VARCHAR2(50)  PATH '$.REF_NO',
           description   VARCHAR2(500) PATH '$.DESCRIPTION')) h;

  BEGIN
    l_date := TO_DATE(l_date_s, 'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN err('تاريخ القيد غير صحيح');
  END;

  ---------------------------------------------------------------- التحقق من الرأس
  IF :G_USER_ROLE NOT IN ('ADMIN','ENTRY') THEN err('إدخال القيود وتعديلها من صلاحية المدخل فقط'); END IF;
  IF l_company IS NULL THEN err('اختر الشركة'); END IF;
  IF l_jt      IS NULL THEN err('اختر نوع القيد'); END IF;
  IF l_cur     IS NULL THEN err('اختر العملة'); END IF;
  IF NVL(l_rate, 0) <= 0 THEN err('سعر الصرف غير صحيح'); END IF;

  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE  :G_USER_ROLE = 'ADMIN' OR l_company = :G_COMPANY_ID
     OR  EXISTS (SELECT 1 FROM user_companies
                 WHERE user_name = UPPER(:APP_USER) AND company_id = l_company);
  IF l_cnt = 0 THEN err('ليس لديك صلاحية على هذه الشركة'); END IF;

  -- نوع القيد: يدوي للقيد الجديد ، والقيد الموجود (مثل تسوية الشيكات) يحتفظ بنوعه
  SELECT COUNT(*) INTO l_cnt FROM journal_types j
  WHERE  j.jt_code = l_jt AND j.is_active = 'Y'
  AND   (j.manual_allowed = 'Y' OR EXISTS (SELECT 1 FROM journals x WHERE x.journal_id = l_id AND x.jt_code = l_jt));
  IF l_cnt = 0 THEN err('نوع القيد لا يُدخل يدوياً'); END IF;

  IF l_date IS NOT NULL THEN
    SELECT COUNT(*) INTO l_cnt FROM fiscal_years
    WHERE  l_date BETWEEN start_date AND end_date AND is_closed = 'N';
    IF l_cnt = 0 THEN err('التاريخ خارج سنة مالية مفتوحة'); END IF;
  END IF;

  -- العملة الأساسية سعرها 1 دائماً
  SELECT COUNT(*) INTO l_cnt FROM currencies WHERE currency_code = l_cur AND is_base = 'Y';
  IF l_cnt = 1 THEN l_rate := 1; END IF;

  IF l_id IS NOT NULL THEN
    BEGIN
      SELECT status, journal_no, source_type INTO l_status, l_no, l_src
      FROM   journals WHERE journal_id = l_id FOR UPDATE;
      IF l_src NOT IN ('MANUAL','CHEQUE') THEN err('هذا القيد ناتج عن مستند آخر ويُعدَّل من مستنده'); END IF;
      IF l_status NOT IN ('DRAFT','RETURNED') THEN err('القيد ' || l_no || ' تمت مراجعته أو اعتماده أو ترحيله ولا يمكن تعديله'); END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN err('القيد غير موجود');
    END;
  END IF;

  ---------------------------------------------------------------- التحقق من السطور
  FOR r IN (SELECT * FROM JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
                 line_no    NUMBER       PATH '$.LINE_NO',
                 account_id NUMBER       PATH '$.ACCOUNT_ID',
                 debit      NUMBER       PATH '$.DEBIT',
                 credit     NUMBER       PATH '$.CREDIT'))) LOOP
    l_lines := l_lines + 1;
    IF r.account_id IS NULL THEN
      err('السطر ' || r.line_no || ': الحساب مطلوب');
    ELSE
      SELECT COUNT(*) INTO l_cnt FROM accounts
      WHERE  account_id = r.account_id AND is_postable = 'Y' AND is_active = 'Y'
      AND    (company_id IS NULL OR company_id = l_company);
      IF l_cnt = 0 THEN err('السطر ' || r.line_no || ': الحساب غير تحليلي أو موقوف أو لا يتبع الشركة'); END IF;
    END IF;
    IF NVL(r.debit, 0) < 0 OR NVL(r.credit, 0) < 0 THEN
      err('السطر ' || r.line_no || ': لا تُقبل مبالغ سالبة');
    ELSIF (NVL(r.debit, 0) > 0 AND NVL(r.credit, 0) > 0) OR (NVL(r.debit, 0) = 0 AND NVL(r.credit, 0) = 0) THEN
      err('السطر ' || r.line_no || ': أدخل مبلغاً في المدين أو الدائن فقط');
    END IF;
    l_dr := l_dr + NVL(r.debit, 0);
    l_cr := l_cr + NVL(r.credit, 0);
  END LOOP;

  IF l_lines < 2 THEN err('القيد يحتاج سطرين على الأقل'); END IF;
  IF ROUND(l_dr, 4) <> ROUND(l_cr, 4) THEN
    err('القيد غير متوازن: المدين ' || TO_CHAR(l_dr, 'FM999G999G999G990D00') ||
        ' والدائن ' || TO_CHAR(l_cr, 'FM999G999G999G990D00'));
  END IF;

  ---------------------------------------------------------------- عند وجود أخطاء
  IF l_errs.COUNT > 0 THEN
    ROLLBACK;
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.write('errors', l_errs);
    apex_json.close_object;
    RETURN;
  END IF;

  ---------------------------------------------------------------- الحفظ
  IF l_id IS NULL THEN
    -- رقم جديد: البادئة-السنة-مسلسل
    SELECT prefix INTO l_prefix FROM journal_types WHERE jt_code = l_jt;
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE  company_id = l_company AND doc_type = l_jt AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no)
      VALUES (l_company, l_jt, EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := l_prefix || '-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, created_by)
    VALUES (l_company, l_jt, l_no, l_date, l_cur, l_rate, l_desc, l_ref, 'DRAFT', 'MANUAL', :APP_USER)
    RETURNING journal_id INTO l_id;
  ELSE
    UPDATE journals
    SET    company_id = l_company, jt_code = l_jt, journal_date = l_date,
           currency_code = l_cur, exchange_rate = l_rate,
           description = l_desc, ref_no = l_ref
    WHERE  journal_id = l_id;
    DELETE FROM journal_lines WHERE journal_id = l_id;
  END IF;

  INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit,
                             debit_base, credit_base, partner_company_id, description)
  SELECT l_id, ROWNUM, account_id, NVL(debit, 0), NVL(credit, 0),
         ROUND(NVL(debit, 0) * l_rate, 2), ROUND(NVL(credit, 0) * l_rate, 2),
         NULL, description
  FROM   JSON_TABLE(l_clob, '$.lines[*]' COLUMNS (
           account_id         NUMBER        PATH '$.ACCOUNT_ID',
           debit              NUMBER        PATH '$.DEBIT',
           credit             NUMBER        PATH '$.CREDIT',
           description        VARCHAR2(500) PATH '$.DESCRIPTION'));

  -- فرق التقريب بالعملة الأساسية يُضاف على آخر سطر دائن
  SELECT SUM(debit_base), SUM(credit_base) INTO l_drb, l_crb
  FROM   journal_lines WHERE journal_id = l_id;
  IF l_drb <> l_crb THEN
    SELECT MAX(line_id) INTO l_last FROM journal_lines WHERE journal_id = l_id AND credit > 0;
    UPDATE journal_lines SET credit_base = credit_base + (l_drb - l_crb) WHERE line_id = l_last;
  END IF;

  UPDATE journals
  SET    total_debit = l_dr, total_credit = l_cr,
         status = 'DRAFT', return_note = NULL
  WHERE  journal_id = l_id;
  INSERT INTO doc_actions (doc_type, doc_id, action, from_status, to_status, action_by)
  VALUES ('JOURNAL', l_id, 'SAVE', l_status, 'DRAFT', :APP_USER);

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('id', l_id);
  apex_json.write('no', l_no);
  apex_json.write('message', 'تم حفظ القيد ' || l_no || ' - بانتظار المراجعة');
  apex_json.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.open_array('errors');
    apex_json.write(SQLERRM);
    apex_json.close_array;
    apex_json.close_object;
END;
