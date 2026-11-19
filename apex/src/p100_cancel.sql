UPDATE payroll_runs SET status = 'CANCELLED' WHERE run_id = :P100_RUN_ID AND status = 'DRAFT';
