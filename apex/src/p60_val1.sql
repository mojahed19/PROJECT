-- 1. حالة القيد والصلاحية
DECLARE j journals%ROWTYPE; l_cnt NUMBER;
BEGIN
  SELECT * INTO j FROM journals WHERE journal_id = :P60_JOURNAL_ID;
  IF j.status <> 'POSTED'            THEN RETURN 'القيد غير مرحّل أو معكوس مسبقاً'; END IF;
  IF j.reversal_of_id IS NOT NULL
     OR j.jt_code = 'REV'            THEN RETURN 'لا يمكن عكس قيد عكسي'; END IF;
  IF j.source_type = 'CLOSING'       THEN RETURN 'قيد الإقفال يُلغى بإعادة فتح السنة من صفحة إقفال السنة المالية'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM invoices WHERE sub_journal_id = j.journal_id;
  IF l_cnt > 0 THEN RETURN 'هذا قيد شركة فرعية ناتج عن فاتورة. اعكس قيد الشركة الأم'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM vouchers v JOIN cheques c ON c.voucher_id = v.voucher_id
  WHERE  j.source_type = 'VOUCHER' AND v.voucher_id = j.source_id AND c.status <> 'PENDING';
  IF l_cnt > 0 THEN RETURN 'شيكات هذا الإذن تمت تسوية بعضها. ألغِ التسويات أو اعكس قيودها أولاً'; END IF;
  IF :G_USER_ROLE NOT IN ('ADMIN','APPROVER') THEN RETURN 'عكس القيود من صلاحية المعتمد'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE :G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID
     OR EXISTS (SELECT 1 FROM user_companies WHERE user_name = UPPER(:APP_USER) AND company_id = j.company_id);
  IF l_cnt = 0 THEN RETURN 'ليس لديك صلاحية على هذه الشركة'; END IF;
  RETURN NULL;
EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'القيد غير موجود';
END;
