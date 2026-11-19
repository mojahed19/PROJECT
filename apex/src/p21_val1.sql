DECLARE l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM journals WHERE jt_code = :P21_JT_CODE;
  RETURN CASE WHEN l_cnt > 0 THEN 'لا يمكن حذف نوع قيد مستخدم. أوقفه بدلاً من ذلك' END;
END;
