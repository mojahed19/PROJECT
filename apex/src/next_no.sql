DECLARE
  -- الرقم التالي المتوقع للمستند الجديد (يظهر عند الضغط على "جديد")
  -- x01 = نوع المستند ، x02 = طريقة الدفع ، x03 = التاريخ ، x04 = SALE / PURCHASE / VOUCHER
  -- الرقم النهائي يُعطى عند الحفظ (قد يختلف إذا حفظ مستخدم آخر مستنداً من نفس النوع قبلك)
  l_kind VARCHAR2(10) := apex_application.g_x04;
  l_type VARCHAR2(10) := apex_application.g_x01;
  l_pay  VARCHAR2(10) := apex_application.g_x02;
  l_code VARCHAR2(10);
  l_year NUMBER;
  l_seq  NUMBER;
  l_no   VARCHAR2(30);
BEGIN
  BEGIN
    l_year := EXTRACT(YEAR FROM TO_DATE(apex_application.g_x03, 'DD/MM/YYYY'));
  EXCEPTION WHEN OTHERS THEN l_year := NULL;
  END;
  l_year := NVL(l_year, EXTRACT(YEAR FROM SYSDATE));

  l_code := CASE l_kind
              WHEN 'SALE' THEN
                CASE WHEN l_type = 'SALE' THEN CASE l_pay WHEN 'CASH' THEN '1' ELSE '2' END
                     ELSE CASE l_pay WHEN 'CASH' THEN '5' ELSE '6' END END
              WHEN 'PURCHASE' THEN
                CASE WHEN l_type = 'PURCHASE' THEN CASE l_pay WHEN 'CASH' THEN '3' ELSE '4' END
                     ELSE CASE l_pay WHEN 'CASH' THEN '7' ELSE '8' END END
              ELSE CASE l_type WHEN 'R' THEN 'RV' ELSE 'PV' END
            END;

  SELECT NVL(MAX(last_no), 0) + 1 INTO l_seq
  FROM   doc_sequences
  WHERE  company_id = :G_PARENT_ID AND doc_type = l_code AND fy_year = l_year;

  l_no := CASE WHEN l_kind = 'VOUCHER' THEN l_code || '-' || l_year || '-' || LPAD(l_seq, 5, '0')
               ELSE l_code || l_year || LPAD(l_seq, 5, '0') END;

  apex_json.open_object;
  apex_json.write('no', l_no);
  apex_json.close_object;
END;
