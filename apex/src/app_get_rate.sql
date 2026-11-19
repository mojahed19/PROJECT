DECLARE
  l_rate NUMBER;
  l_date DATE := NVL(TO_DATE(apex_application.g_x02, 'DD/MM/YYYY'), TRUNC(SYSDATE));
BEGIN
  SELECT CASE WHEN c.is_base = 'Y' THEN 1
              ELSE (SELECT r.rate FROM exchange_rates r
                    WHERE  r.currency_code = c.currency_code
                    AND    r.rate_date <= l_date
                    ORDER  BY r.rate_date DESC FETCH FIRST 1 ROW ONLY) END
  INTO   l_rate
  FROM   currencies c
  WHERE  c.currency_code = apex_application.g_x01;

  apex_json.open_object;
  apex_json.write('rate', l_rate);
  apex_json.close_object;
EXCEPTION WHEN NO_DATA_FOUND THEN
  apex_json.open_object; apex_json.write('rate', ''); apex_json.close_object;
END;
