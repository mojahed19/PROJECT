DECLARE
  l_date  DATE := TO_DATE(:P60_REV_DATE, 'DD/MM/YYYY');
  l_main  journals%ROWTYPE;
  l_msg   VARCHAR2(4000);

  -- عكس قيد واحد، ويرجع رقم القيد العكسي
  FUNCTION reverse_one (p_id NUMBER) RETURN VARCHAR2 IS
    j      journals%ROWTYPE;
    l_new  NUMBER;
    l_seq  NUMBER;
    l_no   VARCHAR2(30);
  BEGIN
    SELECT * INTO j FROM journals WHERE journal_id = p_id FOR UPDATE;
    IF j.status <> 'POSTED' THEN
      raise_application_error(-20020, 'القيد ' || j.journal_no || ' لا يمكن عكسه');
    END IF;

    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE company_id = j.company_id AND doc_type = 'REV' AND fy_year = EXTRACT(YEAR FROM l_date)
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences VALUES (j.company_id, 'REV', EXTRACT(YEAR FROM l_date), 1);
      l_seq := 1;
    END IF;
    l_no := 'REV-' || EXTRACT(YEAR FROM l_date) || '-' || LPAD(l_seq, 5, '0');

    INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                          description, ref_no, status, source_type, source_id, reversal_of_id,
                          reverse_reason, total_debit, total_credit, created_by, posted_by, posted_on)
    VALUES (j.company_id, 'REV', l_no, l_date, j.currency_code, j.exchange_rate,
            SUBSTR('عكس القيد ' || j.journal_no || ' - ' || :P60_REASON, 1, 500), j.journal_no,
            'POSTED', 'REVERSAL', j.journal_id, j.journal_id,
            SUBSTR(:P60_REASON, 1, 500), j.total_credit, j.total_debit, :APP_USER, :APP_USER, SYSDATE)
    RETURNING journal_id INTO l_new;

    -- تبادل المدين والدائن (بالعملة الأصلية وبالعملة الأساسية بنفس سعر الصرف الأصلي)
    INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base,
                               partner_company_id, employee_id, description)
    SELECT l_new, line_no, account_id, credit, debit, credit_base, debit_base,
           partner_company_id, employee_id, SUBSTR('عكس: ' || description, 1, 500)
    FROM   journal_lines WHERE journal_id = p_id;

    UPDATE journals
    SET    status = 'REVERSED', reversed_by_id = l_new, reverse_reason = SUBSTR(:P60_REASON, 1, 500)
    WHERE  journal_id = p_id;

    RETURN l_no;
  END;
BEGIN
  SELECT * INTO l_main FROM journals WHERE journal_id = :P60_JOURNAL_ID;

  IF l_main.source_type = 'INVOICE' THEN
    FOR i IN (SELECT invoice_id, journal_id, sub_journal_id FROM invoices
              WHERE journal_id = l_main.journal_id FOR UPDATE) LOOP
      l_msg := reverse_one(i.journal_id);
      IF i.sub_journal_id IS NOT NULL THEN
        l_msg := l_msg || ' و ' || reverse_one(i.sub_journal_id);
      END IF;
      UPDATE invoices SET status = 'REVERSED' WHERE invoice_id = i.invoice_id;
      UPDATE stock_trans SET status = 'REVERSED'
      WHERE  source_type = 'INVOICE' AND source_id = i.invoice_id;
    END LOOP;

  ELSIF l_main.source_type = 'PURCHASE' THEN
    l_msg := reverse_one(l_main.journal_id);
    UPDATE purchase_invoices SET status = 'REVERSED' WHERE pinv_id = l_main.source_id;
    UPDATE stock_trans SET status = 'REVERSED' WHERE source_type = 'PURCHASE' AND source_id = l_main.source_id;

  ELSIF l_main.source_type = 'VOUCHER' THEN
    l_msg := reverse_one(l_main.journal_id);
    UPDATE vouchers SET status = 'REVERSED' WHERE voucher_id = l_main.source_id;

  ELSE
    l_msg := reverse_one(l_main.journal_id);
  END IF;

  apex_application.g_print_success_message := 'تم عكس القيد ' || l_main.journal_no || ' بالقيد ' || l_msg;
  :P60_JOURNAL_ID := NULL;
  :P60_REASON     := NULL;
END;
