-- 2. تاريخ العكس
DECLARE l_d DATE; l_orig DATE; l_cnt NUMBER;
BEGIN
  l_d := TO_DATE(:P60_REV_DATE, 'DD/MM/YYYY');
  SELECT journal_date INTO l_orig FROM journals WHERE journal_id = :P60_JOURNAL_ID;
  IF l_d < l_orig THEN RETURN 'تاريخ العكس قبل تاريخ القيد الأصلي'; END IF;
  SELECT COUNT(*) INTO l_cnt FROM fiscal_years
  WHERE l_d BETWEEN start_date AND end_date AND is_closed = 'N';
  IF l_cnt = 0 THEN RETURN 'تاريخ العكس خارج سنة مالية مفتوحة'; END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN RETURN 'تاريخ العكس غير صحيح';
END;
