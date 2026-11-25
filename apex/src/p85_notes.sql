DECLARE
  -- الإيضاحات للفترة تجميعياً حسب مستوى شجرة الحسابات:
  --   كل حساب في "مستوى التجميع" إيضاح مستقل ، تحته حساباته في "مستوى التفصيل" بمدين ودائن الفترة والرصيد ، ثم الإجمالي
  --   الرصيد = مدين الفترة − دائن الفترة (مع بيان طبيعته مدين/دائن) ، من القيود المرحّلة (والمعكوس مع عكسه يتصفّران)
  d1 DATE := TO_DATE(:P85_FROM, 'DD/MM/YYYY');
  d2 DATE := TO_DATE(:P85_TO,   'DD/MM/YYYY');
  lg NUMBER := NVL(TO_NUMBER(:P85_GROUP_LEVEL), 3);
  ld NUMBER := NVL(TO_NUMBER(:P85_DETAIL_LEVEL), 4);
  n  NUMBER := 0;
  g_dr NUMBER; g_cr NUMBER; c_dr NUMBER; c_cr NUMBER; t_dr NUMBER := 0; t_cr NUMBER := 0;

  PROCEDURE mv (p_code VARCHAR2, o_dr OUT NUMBER, o_cr OUT NUMBER) IS
  BEGIN
    SELECT NVL(SUM(jl.debit_base), 0), NVL(SUM(jl.credit_base), 0) INTO o_dr, o_cr
    FROM   journal_lines jl
    JOIN   journals j ON j.journal_id = jl.journal_id AND j.status IN ('POSTED','REVERSED')
    JOIN   accounts a ON a.account_id = jl.account_id
    WHERE  a.account_code LIKE p_code || '%'
    AND    j.journal_date >= d1 AND j.journal_date < d2 + 1;
  END;
  FUNCTION f (x NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN ROUND(NVL(x, 0), 2) = 0 THEN '..' ELSE TO_CHAR(x, 'FM999G999G999G999G990D00') END; END;
  FUNCTION bal (x NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN ROUND(x, 2) = 0 THEN '..'
                ELSE TO_CHAR(ABS(x), 'FM999G999G999G999G990D00') || ' <span class="nt-dir">' || CASE WHEN x > 0 THEN 'مدين' ELSE 'دائن' END || '</span>' END;
  END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
  PROCEDURE row_ (p_name VARCHAR2, p_code VARCHAR2, p_dr NUMBER, p_cr NUMBER, p_cls VARCHAR2 DEFAULT NULL) IS
  BEGIN
    htp.p('<tr class="' || p_cls || '"><td class="lbl">' || e(p_name) || '</td><td class="nt">' || e(p_code) || '</td><td class="n">'
          || f(p_dr) || '</td><td class="n">' || f(p_cr) || '</td><td class="n">' || bal(p_dr - p_cr) || '</td></tr>');
  END;
BEGIN
  IF d1 IS NULL OR d2 IS NULL THEN htp.p('<p>حدد الفترة</p>'); RETURN; END IF;
  IF ld <= lg THEN ld := LEAST(lg + 1, 4); END IF;

  htp.p('<div class="nt-head">الإيضاحات للفترة من ' || TO_CHAR(d1, 'YYYY/MM/DD') || ' إلى ' || TO_CHAR(d2, 'YYYY/MM/DD')
        || ' <span class="nt-sub">(التجميع على المستوى ' || lg || ' والتفصيل حتى المستوى ' || ld || ')</span></div>');

  FOR g IN (SELECT account_code, name_ar FROM accounts WHERE acc_level = lg ORDER BY account_code) LOOP
    mv(g.account_code, g_dr, g_cr);
    CONTINUE WHEN ROUND(g_dr, 2) = 0 AND ROUND(g_cr, 2) = 0;
    n := n + 1;
    t_dr := t_dr + g_dr; t_cr := t_cr + g_cr;
    htp.p('<div class="nt-block"><div class="nt-title">إيضاح رقم ' || n || ': ' || e(g.account_code) || ' - ' || e(g.name_ar) || '</div>');
    htp.p('<table class="fs"><thead><tr><th>الحساب</th><th>رقم الحساب</th><th>مدين</th><th>دائن</th><th>الرصيد</th></tr></thead><tbody>');
    FOR c IN (SELECT account_code, name_ar FROM accounts
              WHERE acc_level = ld AND account_code LIKE g.account_code || '%' ORDER BY account_code) LOOP
      mv(c.account_code, c_dr, c_cr);
      IF ROUND(c_dr, 2) <> 0 OR ROUND(c_cr, 2) <> 0 THEN
        row_(c.name_ar, c.account_code, c_dr, c_cr);
      END IF;
    END LOOP;
    row_('إجمالي ' || g.name_ar, NULL, g_dr, g_cr, 'grand');
    htp.p('</tbody></table></div>');
  END LOOP;

  IF n = 0 THEN
    htp.p('<p class="nt-empty">لا توجد حركات مرحّلة في الفترة</p>');
  ELSE
    -- إجمالي كل الإيضاحات: مجموع المدين يساوي مجموع الدائن عند توازن القيود
    htp.p('<div class="nt-block"><table class="fs"><tbody>');
    row_('إجمالي الإيضاحات', NULL, t_dr, t_cr, 'grand');
    htp.p('</tbody></table></div>');
  END IF;
END;
