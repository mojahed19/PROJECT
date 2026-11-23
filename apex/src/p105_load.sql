DECLARE
  r annual_incentives%ROWTYPE;
BEGIN
  SELECT * INTO r FROM annual_incentives WHERE inc_id = :P105_INC_ID;
  :P105_INC_NO      := r.inc_no;
  :P105_FY_YEAR     := r.fy_year;
  :P105_PERCENT     := r.percent;
  :P105_BASIS       := r.basis;
  :P105_EMP_TYPE    := r.emp_type;
  :P105_DESCRIPTION := r.description;
  :P105_STATUS      := r.status;
  :P105_JOURNAL_ID  := r.journal_id;
  :P105_TOTAL       := TO_CHAR(r.total_amount, 'FM999G999G999G990D00');
  __WF__
END;
