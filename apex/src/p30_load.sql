DECLARE
  j     journals%ROWTYPE;
  l_cnt NUMBER;
BEGIN
  SELECT * INTO j FROM journals WHERE journal_id = :P30_JOURNAL_ID;

  -- صلاحية الشركة
  SELECT COUNT(*) INTO l_cnt FROM dual
  WHERE  :G_USER_ROLE = 'GM' OR j.company_id = :G_COMPANY_ID
     OR  EXISTS (SELECT 1 FROM user_companies
                 WHERE user_name = UPPER(:APP_USER) AND company_id = j.company_id);
  IF l_cnt = 0 THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الشركة');
  END IF;

  :P30_COMPANY_ID    := j.company_id;
  :P30_JT_CODE       := j.jt_code;
  :P30_JOURNAL_NO    := j.journal_no;
  :P30_JOURNAL_DATE  := TO_CHAR(j.journal_date, 'DD/MM/YYYY');
  :P30_CURRENCY_CODE := j.currency_code;
  :P30_EXCHANGE_RATE := j.exchange_rate;
  :P30_REF_NO        := j.ref_no;
  :P30_DESCRIPTION   := j.description;
  :P30_STATUS        := j.status;
  :P30_SOURCE_TYPE   := j.source_type;
END;
