DECLARE
  r     journals%ROWTYPE;
  l_cnt NUMBER;
BEGIN
  SELECT * INTO r FROM journals WHERE journal_id = :P30_JOURNAL_ID;

  -- صلاحية الشركة
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE  :G_USER_ROLE = 'ADMIN' OR r.company_id = :G_COMPANY_ID
     OR  EXISTS (SELECT 1 FROM user_companies
                 WHERE user_name = UPPER(:APP_USER) AND company_id = r.company_id);
  IF l_cnt = 0 THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الشركة');
  END IF;

  :P30_COMPANY_ID    := r.company_id;
  :P30_JT_CODE       := r.jt_code;
  :P30_JOURNAL_NO    := r.journal_no;
  :P30_JOURNAL_DATE  := TO_CHAR(r.journal_date, 'DD/MM/YYYY');
  :P30_CURRENCY_CODE := r.currency_code;
  :P30_EXCHANGE_RATE := r.exchange_rate;
  :P30_REF_NO        := r.ref_no;
  :P30_DESCRIPTION   := r.description;
  :P30_STATUS        := r.status;
  :P30_SOURCE_TYPE   := r.source_type;
  __WF__
END;
