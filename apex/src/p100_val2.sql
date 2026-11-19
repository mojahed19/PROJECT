DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years
  WHERE LAST_DAY(TO_DATE(:P100_PERIOD || '01', 'YYYYMMDD')) BETWEEN start_date AND end_date AND is_closed = 'N';
  RETURN CASE WHEN l_cnt = 0 THEN 'الشهر خارج سنة مالية مفتوحة' END;
END;
