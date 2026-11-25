DECLARE
  -- القوائم المالية من شجرة الحسابات مباشرة (القيود المرحّلة ، والمعكوس مع عكسه يتصفّران):
  --   الورقة 1: تكلفة المبيعات للفترة (حسابات مجموعة التكلفة التي يتبعها حساب COGS ، المستوى 4) ثم قائمة الدخل للفترة
  --   الورقة 2: قائمة المركز المالي كما في "إلى تاريخ" (المجموعات = المستوى 2 ، البنود = المستوى 3) في ورقة واحدة
  -- الإيضاح = رقم الحساب في الشجرة
  d1 DATE := TO_DATE(:P84_FROM, 'DD/MM/YYYY');
  d2 DATE := TO_DATE(:P84_TO,   'DD/MM/YYYY');
  l_fy DATE;                                   -- بداية السنة المالية التي فيها "إلى تاريخ"
  l_cost_grp VARCHAR2(20); l_sales_grp VARCHAR2(20); l_ret VARCHAR2(20);
  l_cogs NUMBER; l_rev_gross NUMBER; l_returns NUMBER; l_net_rev NUMBER; l_dmg NUMBER := 0;
  l_gross_op NUMBER; l_other_rev NUMBER; l_gross NUMBER; l_admin NUMBER; l_dep NUMBER; l_tax NUMBER;
  l_before_tax NUMBER; l_net NUMBER; l_tot_rev NUMBER; l_tot_exp NUMBER;
  l_assets NUMBER := 0; l_eq_liab NUMBER := 0; l_sec NUMBER; l_eq NUMBER;
  l_ret_earn NUMBER; l_period_pl NUMBER;

  -- رصيد (مدين − دائن) لحساب وكل ما تحته خلال فترة (NULL = من البداية)
  FUNCTION b (p_code VARCHAR2, p_from DATE, p_to DATE) RETURN NUMBER IS l NUMBER;
  BEGIN
    SELECT NVL(SUM(jl.debit_base - jl.credit_base), 0) INTO l
    FROM   journal_lines jl
    JOIN   journals j ON j.journal_id = jl.journal_id AND j.status IN ('POSTED','REVERSED')
    JOIN   accounts a ON a.account_id = jl.account_id
    WHERE  a.account_code LIKE p_code || '%'
    AND    (p_from IS NULL OR j.journal_date >= p_from)
    AND    j.journal_date < p_to + 1;
    RETURN l;
  END;
  -- مجموع أرصدة حسابات المستوى 4 من نوع معيّن وأسماؤها تحتوي كلمة (الإهلاك ، الضرائب والزكاة)
  FUNCTION bn (p_type VARCHAR2, p_like1 VARCHAR2, p_like2 VARCHAR2, p_from DATE, p_to DATE) RETURN NUMBER IS l NUMBER := 0;
  BEGIN
    FOR a IN (SELECT account_code FROM accounts WHERE acc_level = 4 AND acc_type = p_type
              AND (name_ar LIKE p_like1 OR name_ar LIKE p_like2)
              AND (l_cost_grp IS NULL OR account_code NOT LIKE l_cost_grp || '%')) LOOP
      l := l + b(a.account_code, p_from, p_to);
    END LOOP;
    RETURN l;
  END;
  FUNCTION tot (p_type VARCHAR2, p_from DATE, p_to DATE) RETURN NUMBER IS l NUMBER := 0;
  BEGIN
    FOR a IN (SELECT account_code FROM accounts WHERE acc_level = 1 AND acc_type = p_type) LOOP
      l := l + b(a.account_code, p_from, p_to);
    END LOOP;
    RETURN l;
  END;
  FUNCTION f (n NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN n IS NULL THEN NULL WHEN ROUND(n, 2) = 0 THEN '..' ELSE TO_CHAR(n, 'FM999G999G999G999G990D00') END; END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;

  -- سطر في قائمة المركز المالي: البيان | الإيضاح | جزئي | كلي
  PROCEDURE r4 (p_lbl VARCHAR2, p_note VARCHAR2, p_part NUMBER, p_total NUMBER, p_cls VARCHAR2 DEFAULT NULL) IS
  BEGIN
    htp.p('<tr class="' || p_cls || '"><td class="lbl">' || e(p_lbl) || '</td><td class="nt">' || e(p_note) || '</td><td class="n">'
          || f(p_part) || '</td><td class="n">' || f(p_total) || '</td></tr>');
  END;
  -- سطر في قائمة الدخل وتكلفة المبيعات: البيان | الإيضاح | المبلغ
  PROCEDURE r3 (p_lbl VARCHAR2, p_note VARCHAR2, p_amt NUMBER, p_cls VARCHAR2 DEFAULT NULL) IS
  BEGIN
    htp.p('<tr class="' || p_cls || '"><td class="lbl">' || e(p_lbl) || '</td><td class="nt">' || e(p_note) || '</td><td class="n">'
          || f(p_amt) || '</td></tr>');
  END;
  PROCEDURE head (p_title VARCHAR2, p_cols VARCHAR2) IS
  BEGIN
    htp.p('<div class="fs-title">' || e(p_title) || '</div>');
    htp.p('<table class="fs"><thead><tr>' || p_cols || '</tr></thead><tbody>');
  END;

  -- مجموعة من المركز المالي (حساب مستوى 2): عنوان ، بنود المستوى 3 في "جزئي" ، الإجمالي في "كلي"
  -- p_sign = 1 للأصول (مدين − دائن) ، −1 للخصوم وحقوق الملكية (دائن − مدين)
  FUNCTION grp (p_code VARCHAR2, p_name VARCHAR2, p_sign NUMBER, p_extra BOOLEAN DEFAULT FALSE) RETURN NUMBER IS l NUMBER := 0; v NUMBER;
  BEGIN
    r4(p_name, NULL, NULL, NULL, 'sec');
    FOR a IN (SELECT account_code, name_ar FROM accounts WHERE parent_id = (SELECT account_id FROM accounts WHERE account_code = p_code)
              ORDER BY account_code) LOOP
      v := p_sign * b(a.account_code, NULL, d2);
      l := l + v;
      r4(a.name_ar, a.account_code, v, NULL);
    END LOOP;
    IF p_extra THEN   -- حقوق الملكية: الأرباح المرحّلة وأرباح الفترة (من حسابات الإيرادات والمصروفات)
      r4('أرباح وخسائر مرحلة', NULL, l_ret_earn, NULL);
      r4('أرباح وخسائر الفترة', NULL, l_period_pl, NULL);
      l := l + l_ret_earn + l_period_pl;
    END IF;
    r4('إجمالي ' || p_name, NULL, NULL, l, 'tot');
    RETURN l;
  END;
BEGIN
  IF d1 IS NULL OR d2 IS NULL THEN htp.p('<p>حدد الفترة</p>'); RETURN; END IF;

  SELECT NVL(MAX(start_date), TRUNC(d2, 'YYYY')) INTO l_fy FROM fiscal_years WHERE d2 BETWEEN start_date AND end_date;
  -- مجموعة التكلفة = حساب المستوى 2 الذي يتبعه حساب تكلفة البضاعة المباعة ، ومجموعة إيراد النشاط من حساب المبيعات
  SELECT MAX(SUBSTR(a.account_code, 1, 2)) INTO l_cost_grp  FROM account_settings s JOIN accounts a ON a.account_id = s.account_id WHERE s.setting_code = 'COGS';
  SELECT MAX(SUBSTR(a.account_code, 1, 2)) INTO l_sales_grp FROM account_settings s JOIN accounts a ON a.account_id = s.account_id WHERE s.setting_code IN ('SALES_EXT','SALES','POS_SALES');
  SELECT MAX(a.account_code) INTO l_ret FROM account_settings s JOIN accounts a ON a.account_id = s.account_id WHERE s.setting_code = 'SALES_RETURN';

  ------------------------------------------------------------------ أرقام قائمة الدخل للفترة
  l_tot_rev   := -tot('REV', d1, d2);
  l_tot_exp   :=  tot('EXP', d1, d2);
  l_returns   := CASE WHEN l_ret IS NOT NULL THEN b(l_ret, d1, d2) ELSE 0 END;                 -- مدين = مردودات
  l_rev_gross := CASE WHEN l_sales_grp IS NOT NULL THEN -b(l_sales_grp, d1, d2) ELSE 0 END + l_returns;
  l_net_rev   := l_rev_gross - l_returns;
  l_cogs      := CASE WHEN l_cost_grp IS NOT NULL THEN b(l_cost_grp, d1, d2) ELSE 0 END;
  l_gross_op  := l_net_rev - l_cogs - l_dmg;
  l_other_rev := l_tot_rev - l_net_rev;
  l_gross     := l_gross_op + l_other_rev;
  l_dep       := bn('EXP', '%إهلاك%', '%اهلاك%', d1, d2);
  l_tax       := bn('EXP', '%ضريب%', '%زكا%', d1, d2);
  l_admin     := l_tot_exp - l_cogs - l_dep - l_tax;
  l_before_tax:= l_gross - l_admin - l_dep;
  l_net       := l_before_tax - l_tax;

  -- للمركز المالي: أرباح الفترة من بداية السنة المالية ، وما قبلها أرباح مرحّلة
  l_period_pl := -(tot('REV', l_fy, d2) + tot('EXP', l_fy, d2));
  l_ret_earn  := -(tot('REV', NULL, l_fy - 1) + tot('EXP', NULL, l_fy - 1));

  ------------------------------------------------------------------ 2) تكلفة المبيعات
  htp.p('<div class="fs-page">');
  head('تكلفة المبيعات للفترة من ' || TO_CHAR(d1, 'YYYY/MM/DD') || ' إلى ' || TO_CHAR(d2, 'YYYY/MM/DD'),
       '<th>البيان</th><th>الإيضاح</th><th>المبلغ</th>');
  FOR a IN (SELECT account_code, name_ar FROM accounts WHERE acc_level = 4 AND account_code LIKE l_cost_grp || '%' ORDER BY account_code) LOOP
    r3(a.name_ar, a.account_code, b(a.account_code, d1, d2));
  END LOOP;
  r3('صافي تكلفة المبيعات', NULL, l_cogs, 'grand');
  htp.p('</tbody></table>');

  ------------------------------------------------------------------ 3) قائمة الدخل
  htp.p('<div class="fs-gap"></div>');
  head('قائمة الدخل للفترة من ' || TO_CHAR(d1, 'YYYY/MM/DD') || ' إلى ' || TO_CHAR(d2, 'YYYY/MM/DD'),
       '<th>البيان</th><th>الإيضاح</th><th>المبلغ</th>');
  r3('إيراد النشاط', l_sales_grp, l_rev_gross);
  r3('(-) مردودات إيراد النشاط', l_ret, l_returns);
  r3('صافي إيراد النشاط', NULL, l_net_rev, 'tot');
  r3('(-) تكلفة المبيعات', l_cost_grp, l_cogs);
  r3('(-) تلفيات المخزون', NULL, l_dmg);
  r3('إجمالي الربح أو الخسارة التشغيلي', NULL, l_gross_op, 'tot');
  r3('(+) الإيرادات الأخرى', NULL, l_other_rev);
  r3('مجمل الربح أو الخسارة', NULL, l_gross, 'tot');
  r3('(-) المصروفات العمومية والإدارية', NULL, l_admin);
  r3('(-) الإهلاك', NULL, l_dep);
  r3('صافي الربح القابل للتوزيع', NULL, l_before_tax, 'tot');
  r3('(-) الضرائب والزكاة', NULL, l_tax);
  r3('صافي الربح أو الخسارة', NULL, l_net, 'grand');
  htp.p('</tbody></table></div>');

  ------------------------------------------------------------------ 1) قائمة المركز المالي
  htp.p('<div class="fs-page fs-bs">');
  head('قائمة المركز المالي كما في ' || TO_CHAR(d2, 'YYYY/MM/DD'),
       '<th>البيان</th><th>الإيضاح</th><th>جزئي</th><th>كلي</th>');
  r4('الموجودات', NULL, NULL, NULL, 'main');
  -- الموجودات غير المتداولة أولاً ثم المتداولة
  FOR g IN (SELECT a.account_code, a.name_ar FROM accounts a JOIN accounts p ON p.account_id = a.parent_id
            WHERE a.acc_level = 2 AND p.acc_type = 'ASSET'
            ORDER BY CASE WHEN a.name_ar LIKE '%متداول%' AND a.name_ar NOT LIKE '%غير%' THEN 1 ELSE 0 END, a.account_code) LOOP
    l_assets := l_assets + grp(g.account_code, g.name_ar, 1);
  END LOOP;
  r4('إجمالي الموجودات', NULL, NULL, l_assets, 'grand');

  r4('حقوق الملكية والمطلوبات', NULL, NULL, NULL, 'main');
  l_eq := 0;
  FOR g IN (SELECT a.account_code, a.name_ar, ROW_NUMBER() OVER (ORDER BY a.account_code) rn
            FROM accounts a JOIN accounts p ON p.account_id = a.parent_id
            WHERE a.acc_level = 2 AND p.acc_type = 'EQUITY' ORDER BY a.account_code) LOOP
    l_eq := l_eq + grp(g.account_code, g.name_ar, -1, g.rn = 1);
  END LOOP;
  l_eq_liab := l_eq;
  FOR g IN (SELECT a.account_code, a.name_ar FROM accounts a JOIN accounts p ON p.account_id = a.parent_id
            WHERE a.acc_level = 2 AND p.acc_type = 'LIAB'
            ORDER BY CASE WHEN a.name_ar LIKE '%متداول%' AND a.name_ar NOT LIKE '%غير%' THEN 0 ELSE 1 END, a.account_code) LOOP
    l_eq_liab := l_eq_liab + grp(g.account_code, g.name_ar, -1);
  END LOOP;
  r4('إجمالي حقوق الملكية والمطلوبات', NULL, NULL, l_eq_liab, 'grand');
  htp.p('</tbody></table>');
  IF ROUND(l_assets - l_eq_liab, 2) <> 0 THEN
    htp.p('<div class="fs-warn">تنبيه: الفرق بين الموجودات وحقوق الملكية والمطلوبات = ' || f(l_assets - l_eq_liab) || '</div>');
  END IF;
  htp.p('</div>');

END;
