-- =====================================================================
--  11_cheque_bank_serial.sql
--  * البنك يُحدد في رأس إذن الشيكات (صرف: البنك المسحوب عليه ، توريد: البنك المودَع فيه)
--  * مسلسل عام لكل شيك: 16 + السنة + 5 خانات (بنفس طريقة أرقام الأذونات)
--  * اسم المستفيد يؤخذ من رأس الإذن
--  يُشغّل مرة واحدة بعد 10 (آمن لإعادة التشغيل)
-- =====================================================================
SET DEFINE OFF

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = 'VOUCHERS' AND column_name = 'BANK_ACCOUNT_ID';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE vouchers ADD (bank_account_id NUMBER REFERENCES accounts)';
  END IF;
  SELECT COUNT(*) INTO l_cnt FROM user_tab_columns WHERE table_name = 'CHEQUES' AND column_name = 'CHEQUE_SERIAL';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE cheques ADD (cheque_serial VARCHAR2(20))';
  END IF;
END;
/

-- بنك الأذونات الحالية: من شيكاتها، وإلا أول حساب بنكي
UPDATE vouchers v
SET    bank_account_id = NVL((SELECT MIN(NVL(c.bank_account_id, c.settle_bank_id)) FROM cheques c WHERE c.voucher_id = v.voucher_id),
                             (SELECT MIN(account_id) FROM accounts WHERE cash_bank = 'B' AND is_active = 'Y'))
WHERE  v.voucher_kind = 'CHEQUE' AND v.bank_account_id IS NULL;

UPDATE cheques c
SET    bank_account_id = (SELECT v.bank_account_id FROM vouchers v WHERE v.voucher_id = c.voucher_id AND v.voucher_type = 'P')
WHERE  c.bank_account_id IS NULL
AND    EXISTS (SELECT 1 FROM vouchers v WHERE v.voucher_id = c.voucher_id AND v.voucher_type = 'P');

-- مسلسل للشيكات الحالية بترتيب إدخالها
DECLARE
  l_co  NUMBER;
  l_seq NUMBER;
BEGIN
  FOR c IN (SELECT c.cheque_id, v.company_id, EXTRACT(YEAR FROM v.voucher_date) yr
            FROM cheques c JOIN vouchers v ON v.voucher_id = c.voucher_id
            WHERE c.cheque_serial IS NULL ORDER BY c.cheque_id) LOOP
    UPDATE doc_sequences SET last_no = last_no + 1
    WHERE  company_id = c.company_id AND doc_type = '16' AND fy_year = c.yr
    RETURNING last_no INTO l_seq;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO doc_sequences (company_id, doc_type, fy_year, last_no) VALUES (c.company_id, '16', c.yr, 1);
      l_seq := 1;
    END IF;
    UPDATE cheques SET cheque_serial = '16' || c.yr || LPAD(l_seq, 5, '0') WHERE cheque_id = c.cheque_id;
  END LOOP;
END;
/

DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_constraints WHERE constraint_name = 'CHEQUES_SERIAL_UK';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE cheques MODIFY (cheque_serial NOT NULL)';
    EXECUTE IMMEDIATE 'ALTER TABLE cheques ADD CONSTRAINT cheques_serial_uk UNIQUE (cheque_serial)';
  END IF;
END;
/

COMMIT;
