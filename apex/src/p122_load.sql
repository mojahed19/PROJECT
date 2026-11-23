DECLARE
  r budget_plans%ROWTYPE;
BEGIN
  IF :P122_PLAN_ID IS NULL AND :P122_FY_YEAR IS NOT NULL AND :P122_DEPT_ID IS NOT NULL THEN
    SELECT MAX(plan_id) INTO :P122_PLAN_ID FROM budget_plans WHERE fy_year = :P122_FY_YEAR AND dept_id = :P122_DEPT_ID;
  END IF;
  :P122_STATUS := NULL;
  IF :P122_PLAN_ID IS NOT NULL THEN
    SELECT * INTO r FROM budget_plans WHERE plan_id = :P122_PLAN_ID;
    :P122_FY_YEAR     := r.fy_year;
    :P122_DEPT_ID     := r.dept_id;
    :P122_DESCRIPTION := r.description;
    :P122_STATUS      := r.status;
    __WF__
  END IF;
END;
