DECLARE
  -- قائمة الحسابات حسب طريقة الدفع (x01 = CASH أو CREDIT) ، و x02 = SALE أو PURCHASE
  --   نقدي : كل الخزائن والحسابات البنكية
  --   آجل  : المبيعات = العملاء (تحت 1106) والفروع ، المشتريات = الموردون (تحت 2101)
  --   أضف أي عميل أو مورد جديد كحساب تحليلي تحت مجموعته في شجرة الحسابات
  l_json CLOB;
  l_pay  VARCHAR2(10) := apex_application.g_x01;
  l_kind VARCHAR2(10) := apex_application.g_x02;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'v' VALUE a.account_id,
           't' VALUE a.account_code || ' - ' || a.name_ar
                     || CASE a.cash_bank WHEN 'B' THEN ' (بنك)' WHEN 'C' THEN ' (خزينة)' END
                     || CASE WHEN ca.company_id IS NOT NULL THEN ' (فرع)' END)
         ORDER BY a.cash_bank DESC, a.account_code RETURNING CLOB)
  INTO   l_json
  FROM   accounts a
  LEFT JOIN company_accounts ca ON ca.ar_account_id = a.account_id
  WHERE  a.is_active = 'Y' AND a.is_postable = 'Y'
  AND    (a.company_id IS NULL OR a.company_id = :G_PARENT_ID)
  AND    (   (l_pay = 'CASH'   AND a.cash_bank IN ('C','B'))
          OR (l_pay = 'CREDIT' AND a.cash_bank = 'N' AND l_kind = 'SALE'
              AND (a.account_code LIKE '1106%' OR ca.company_id IS NOT NULL))       -- العملاء + الفروع
          OR (l_pay = 'CREDIT' AND a.cash_bank = 'N' AND l_kind = 'PURCHASE'
              AND a.account_code LIKE '2101%'));                                    -- الموردون

  apex_util.prn(COALESCE(l_json, TO_CLOB('[]')), FALSE);
END;
