DECLARE
  -- الميزانية المجمّعة: الشركة الأم من القيود المرحّلة + كل فرع من آخر ميزانية مُدخلة يدوياً حتى التاريخ
  l_date   DATE   := NVL(TO_DATE(:P126_AS_OF_DATE, 'DD/MM/YYYY'), TRUNC(SYSDATE));
  l_lvl    NUMBER := NVL(TO_NUMBER(:P126_LEVEL), 2);
  l_excl   VARCHAR2(1) := NVL(:P126_EXCLUDE, 'Y');
  l_parent NUMBER := :G_PARENT_ID;

  TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE t_txt IS TABLE OF VARCHAR2(200) INDEX BY PLS_INTEGER;
  br_id   t_num; br_name t_txt; br_date t_txt;
  col_tot t_num;                 -- إجمالي كل عمود (للتحقق من التوازن)
  l_v     NUMBER; l_sum NUMBER; l_any BOOLEAN; l_sign NUMBER; l_n PLS_INTEGER := 0;
  l_row   VARCHAR2(32767);

  FUNCTION fn (n NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN NVL(n, 0) = 0 THEN '-' ELSE TO_CHAR(n, 'FM999G999G999G990D00') END; END;
BEGIN
  FOR b IN (SELECT c.company_id, c.name_ar,
                   (SELECT MAX(as_of_date) FROM branch_balances x WHERE x.company_id = c.company_id AND x.as_of_date <= l_date) d
            FROM companies c WHERE c.is_parent = 'N' AND c.is_active = 'Y' ORDER BY c.company_code) LOOP
    l_n := l_n + 1; br_id(l_n) := b.company_id; br_name(l_n) := b.name_ar;
    br_date(l_n) := NVL(TO_CHAR(b.d, 'DD/MM/YYYY'), 'لا توجد ميزانية');
  END LOOP;
  FOR i IN 0 .. l_n + 1 LOOP col_tot(i) := 0; END LOOP;

  htp.p('<div style="overflow-x:auto"><table class="jl-table cons-table"><thead><tr><th>الحساب</th><th>الشركة الأم<br><small>من القيود حتى '
        || TO_CHAR(l_date, 'DD/MM/YYYY') || '</small></th>');
  FOR i IN 1 .. l_n LOOP
    htp.p('<th>' || apex_escape.html(br_name(i)) || '<br><small>ميزانية ' || br_date(i) || '</small></th>');
  END LOOP;
  htp.p('<th>الإجمالي المجمّع</th></tr></thead><tbody>');

  FOR a IN (SELECT account_code, name_ar, acc_type, nature FROM accounts WHERE acc_level = l_lvl ORDER BY account_code) LOOP
    l_sign := CASE a.nature WHEN 'D' THEN 1 ELSE -1 END;   -- يُعرض الرصيد بطبيعة الحساب
    l_any := FALSE;

    -- الشركة الأم من القيود
    SELECT NVL(SUM(l.debit_base - l.credit_base), 0) INTO l_v
    FROM   journal_lines l
    JOIN   journals j ON j.journal_id = l.journal_id
    JOIN   accounts d ON d.account_id = l.account_id
    WHERE  j.company_id = l_parent AND j.status IN ('POSTED','REVERSED') AND j.journal_date <= l_date
    AND    d.account_code LIKE a.account_code || '%'
    AND    (l_excl = 'N' OR d.account_id NOT IN (SELECT ar_account_id FROM company_accounts));
    l_v := l_v * l_sign; l_sum := l_v; col_tot(0) := col_tot(0) + l_v;
    IF l_v <> 0 THEN l_any := TRUE; END IF;
    l_row := '<td class="jl-num">' || fn(l_v) || '</td>';

    -- الفروع من الإدخال اليدوي
    FOR i IN 1 .. l_n LOOP
      SELECT NVL(SUM(b.debit - b.credit), 0) INTO l_v
      FROM   branch_balances b JOIN accounts d ON d.account_id = b.account_id
      WHERE  b.company_id = br_id(i)
      AND    b.as_of_date = (SELECT MAX(x.as_of_date) FROM branch_balances x WHERE x.company_id = br_id(i) AND x.as_of_date <= l_date)
      AND    d.account_code LIKE a.account_code || '%'
      AND    (l_excl = 'N' OR d.account_id NOT IN (SELECT s.account_id FROM account_settings s WHERE s.setting_code = 'INTERCO_AP'));
      l_v := l_v * l_sign; l_sum := l_sum + l_v; col_tot(i) := col_tot(i) + l_v;
      IF l_v <> 0 THEN l_any := TRUE; END IF;
      l_row := l_row || '<td class="jl-num">' || fn(l_v) || '</td>';
    END LOOP;

    IF l_any THEN
      htp.p('<tr><td>' || apex_escape.html(a.account_code || ' - ' || a.name_ar) || '</td>' || l_row
            || '<td class="jl-num"><b>' || fn(l_sum) || '</b></td></tr>');
    END IF;
  END LOOP;
  htp.p('</tbody></table></div>');
  htp.p('<p class="jl-hint">الأرصدة بطبيعة الحساب: الأصول والمصروفات موجبة بالمدين، والخصوم وحقوق الملكية والإيرادات موجبة بالدائن. '
        || CASE WHEN l_excl = 'Y' THEN 'تم استبعاد الحسابات البينية (ذمم الفروع لدى الأم وحساب الأم لدى الفروع).' END || '</p>');
END;
