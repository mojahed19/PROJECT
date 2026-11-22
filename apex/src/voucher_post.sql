DECLARE
      -- ترحيل الإذن (نقدي أو شيكات) = إنشاء قيد مرحّل بنفس رقم الإذن
      --   توريد نقدي : من ح/ الخزينة            إلى ح/ الحساب المقابل
      --   صرف نقدي   : من ح/ الحساب المقابل     إلى ح/ الخزينة
      --   توريد شيكات: من ح/ شيكات تحت التحصيل  إلى ح/ الحساب المقابل
      --   صرف شيكات  : من ح/ الحساب المقابل     إلى ح/ شيكات تحت الصرف
      v     vouchers%ROWTYPE;
      l_jt  VARCHAR2(10);
      l_mid NUMBER;
      l_jid NUMBER;
      l_amt NUMBER;
      l_r   NUMBER;
      l_p   NUMBER;
    BEGIN
      SELECT * INTO v FROM vouchers WHERE voucher_id = l_id;
      IF v.voucher_kind = 'CHEQUE' THEN
        l_jt := CASE v.voucher_type WHEN 'R' THEN 'CR' ELSE 'CP' END;
        BEGIN
          SELECT account_id INTO l_mid FROM account_settings
          WHERE  company_id = v.company_id
          AND    setting_code = CASE v.voucher_type WHEN 'R' THEN 'CHEQUES_IN' ELSE 'CHEQUES_OUT' END;
        EXCEPTION WHEN NO_DATA_FOUND THEN
          raise_application_error(-20001, 'حدد حساب الشيكات تحت التحصيل / تحت الصرف في الحسابات الافتراضية');
        END;
      ELSE
        l_jt  := CASE v.voucher_type WHEN 'R' THEN 'RV' ELSE 'PV' END;
        l_mid := v.cash_account_id;
      END IF;
      IF v.counter_account_id IS NULL OR l_mid IS NULL THEN
        raise_application_error(-20001, 'الإذن ينقصه الحساب المقابل أو حساب الخزينة');
      END IF;

      l_amt := v.total_amount;
      l_r   := CASE v.voucher_type WHEN 'R' THEN l_amt ELSE 0 END;   -- مدين الحساب الوسيط في التوريد
      l_p   := CASE v.voucher_type WHEN 'P' THEN l_amt ELSE 0 END;   -- دائن الحساب الوسيط في الصرف

      INSERT INTO journals (company_id, jt_code, journal_no, journal_date, currency_code, exchange_rate,
                            description, status, source_type, source_id, total_debit, total_credit,
                            created_by, reviewed_by, reviewed_on, approved_by, approved_on, posted_by, posted_on)
      VALUES (v.company_id, l_jt, v.voucher_no, v.voucher_date, v.currency_code, v.exchange_rate,
              NVL(v.description, CASE v.voucher_type WHEN 'R' THEN 'إذن توريد ' ELSE 'إذن صرف ' END || v.voucher_no),
              'POSTED', 'VOUCHER', v.voucher_id, l_amt, l_amt,
              v.created_by, v.reviewed_by, v.reviewed_on, v.approved_by, v.approved_on, :APP_USER, SYSDATE)
      RETURNING journal_id INTO l_jid;

      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
      VALUES (l_jid, 1, l_mid, l_r, l_p, ROUND(l_r * v.exchange_rate, 2), ROUND(l_p * v.exchange_rate, 2),
              NVL(v.party_name, v.description));
      INSERT INTO journal_lines (journal_id, line_no, account_id, debit, credit, debit_base, credit_base, description)
      VALUES (l_jid, 2, v.counter_account_id, l_p, l_r, ROUND(l_p * v.exchange_rate, 2), ROUND(l_r * v.exchange_rate, 2),
              NVL(v.description, v.party_name));

      UPDATE vouchers SET journal_id = l_jid WHERE voucher_id = l_id;
    END;