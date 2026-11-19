DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM payroll_runs
  WHERE pay_period = :P100_PERIOD AND status <> 'CANCELLED'
  AND   NVL(company_id, 0) <> NVL(:P100_COMPANY_ID, 0)
  AND   (company_id IS NULL OR :P100_COMPANY_ID IS NULL OR company_id = :P100_COMPANY_ID);
  RETURN CASE WHEN l_cnt > 0 THEN 'يوجد مسير آخر لهذا الشهر يشمل نفس الشركات' END;
END;
