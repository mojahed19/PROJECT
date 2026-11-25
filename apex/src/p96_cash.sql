DECLARE
  -- ملخص الخزائن والبنوك لفترة (يوم واحد افتراضياً): لكل خزينة / بنك رصيد أول المدة ، المقبوض ، المدفوع ، الرصيد الختامي
  -- من القيود المرحّلة بالعملة الأساسية ، ثم إجمالي الخزائن والبنوك والإجمالي العام
  d1 DATE := TO_DATE(:P96_FROM, 'DD/MM/YYYY');
  d2 DATE := TO_DATE(:P96_TO,   'DD/MM/YYYY');
  g_ob NUMBER := 0; g_in NUMBER := 0; g_out NUMBER := 0; g_n NUMBER := 0;
  FUNCTION f (x NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN ROUND(NVL(x, 0), 2) = 0 THEN '..'
                    ELSE CASE WHEN x < 0 THEN '(' END || TO_CHAR(ABS(x), 'FM999G999G999G999G990D00') || CASE WHEN x < 0 THEN ')' END END; END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
  PROCEDURE row_ (p_name VARCHAR2, p_link VARCHAR2, p_code VARCHAR2, p_n NUMBER, p_ob NUMBER, p_in NUMBER, p_out NUMBER, p_cls VARCHAR2 DEFAULT NULL) IS
  BEGIN
    htp.p('<tr class="' || p_cls || '"><td class="lbl">' || CASE WHEN p_link IS NOT NULL THEN '<a href="' || p_link || '" title="كشف الحساب">' || e(p_name) || '</a>' ELSE e(p_name) END
          || '</td><td class="nt">' || e(p_code) || '</td><td class="nt">' || CASE WHEN p_n > 0 THEN TO_CHAR(p_n) END
          || '</td><td class="n">' || f(p_ob) || '</td><td class="n in">' || f(p_in) || '</td><td class="n out">' || f(p_out)
          || '</td><td class="n b">' || f(p_ob + p_in - p_out) || '</td></tr>');
  END;
BEGIN
  IF d1 IS NULL OR d2 IS NULL THEN htp.p('<p class="nt-empty">حدد الفترة</p>'); RETURN; END IF;
  htp.p('<div class="nt-head">ملخص الخزائن والبنوك '
        || CASE WHEN d1 = d2 THEN 'ليوم ' || TO_CHAR(d1, 'YYYY/MM/DD') ELSE 'من ' || TO_CHAR(d1, 'YYYY/MM/DD') || ' إلى ' || TO_CHAR(d2, 'YYYY/MM/DD') END
        || '</div>');
  htp.p('<div class="nt-block"><table class="fs"><thead><tr><th>الحساب</th><th>رقم الحساب</th><th>عدد الحركات</th>'
        || '<th>رصيد أول المدة</th><th>المقبوض</th><th>المدفوع</th><th>الرصيد الختامي</th></tr></thead><tbody>');

  FOR t IN (SELECT 'C' k, 'الخزائن' n FROM dual UNION ALL SELECT 'B', 'البنوك' FROM dual) LOOP
    DECLARE s_ob NUMBER := 0; s_in NUMBER := 0; s_out NUMBER := 0; s_n NUMBER := 0; c NUMBER := 0;
    BEGIN
      htp.p('<tr class="sec"><td class="lbl" colspan="7">' || t.n || '</td></tr>');
      FOR a IN (
        SELECT ac.account_id, ac.account_code, ac.name_ar,
               NVL(SUM(CASE WHEN m.journal_date < d1 THEN m.debit_base - m.credit_base END), 0) ob,
               NVL(SUM(CASE WHEN m.journal_date >= d1 THEN m.debit_base END), 0) inn,
               NVL(SUM(CASE WHEN m.journal_date >= d1 THEN m.credit_base END), 0) outt,
               COUNT(CASE WHEN m.journal_date >= d1 THEN 1 END) n
        FROM   accounts ac
        LEFT JOIN (SELECT jl.account_id, j.journal_date, jl.debit_base, jl.credit_base
                   FROM   journal_lines jl JOIN journals j ON j.journal_id = jl.journal_id
                   WHERE  j.status IN ('POSTED','REVERSED') AND j.journal_date < d2 + 1) m ON m.account_id = ac.account_id
        WHERE  ac.cash_bank = t.k AND ac.is_active = 'Y'
        GROUP  BY ac.account_id, ac.account_code, ac.name_ar
        ORDER  BY ac.account_code
      ) LOOP
        c := c + 1;
        row_(a.name_ar, apex_page.get_url(p_page => 81, p_clear_cache => 81, p_items => 'P81_ACCOUNT_ID,P81_FROM,P81_TO',
                                          p_values => a.account_id || ',' || TO_CHAR(d1, 'DD/MM/YYYY') || ',' || TO_CHAR(d2, 'DD/MM/YYYY')),
             a.account_code, a.n, a.ob, a.inn, a.outt);
        s_ob := s_ob + a.ob; s_in := s_in + a.inn; s_out := s_out + a.outt; s_n := s_n + a.n;
      END LOOP;
      IF c = 0 THEN
        htp.p('<tr><td colspan="7" class="nt-empty">لا توجد حسابات ' || t.n || ' (حدد نوع الحساب خزينة / بنك في شجرة الحسابات)</td></tr>');
      ELSE
        row_('إجمالي ' || t.n, NULL, NULL, s_n, s_ob, s_in, s_out, 'tot');
      END IF;
      g_ob := g_ob + s_ob; g_in := g_in + s_in; g_out := g_out + s_out; g_n := g_n + s_n;
    END;
  END LOOP;
  row_('الإجمالي العام (النقدية)', NULL, NULL, g_n, g_ob, g_in, g_out, 'grand');
  htp.p('</tbody></table></div>');
END;
