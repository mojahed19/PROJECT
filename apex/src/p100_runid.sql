SELECT MAX(run_id) FROM payroll_runs
WHERE pay_period = :P100_PERIOD AND NVL(company_id, 0) = NVL(:P100_COMPANY_ID, 0)
AND   status <> 'CANCELLED'
