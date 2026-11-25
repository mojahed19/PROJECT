DECLARE
  -- أعمار الديون في تاريخ معيّن لمجموعة العملاء (1106) أو الموردين (2101):
  --   الرصيد = صافي القيود المرحّلة حتى التاريخ (للعملاء مدين − دائن ، للموردين دائن − مدين)
  --   يوزَّع الرصيد على أحدث الحركات التي زادته (الفواتير) أولاً ، والسداد يُخصم من الأقدم (FIFO)
  --   عمر كل جزء = التاريخ المحدد − تاريخ الحركة ، في 4 فترات بطول P86_DAYS يوماً
  l_grp  NUMBER := TO_NUMBER(:P86_GROUP_ID);
  l_asof DATE   := TO_DATE(:P86_AS_OF, 'DD/MM/YYYY');
  l_days NUMBER := NVL(TO_NUMBER(:P86_DAYS), 30);
  l_code accounts.account_code%TYPE;
  l_name accounts.name_ar%TYPE;
  l_sign NUMBER;
  n NUMBER := 0;
  t_bal NUMBER := 0; t1 NUMBER := 0; t2 NUMBER := 0; t3 NUMBER := 0; t4 NUMBER := 0; t_adv NUMBER := 0;
  FUNCTION f (x NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN ROUND(NVL(x, 0), 2) = 0 THEN '..' ELSE TO_CHAR(x, 'FM999G999G999G999G990D00') END; END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
BEGIN
  IF l_grp IS NULL OR l_asof IS NULL THEN htp.p('<p class="nt-empty">اختر المجموعة والتاريخ</p>'); RETURN; END IF;
  SELECT account_code, name_ar, CASE nature WHEN 'C' THEN -1 ELSE 1 END INTO l_code, l_name, l_sign
  FROM accounts WHERE account_id = l_grp;

  htp.p('<div class="nt-head">أعمار الديون - ' || e(l_name) || ' في ' || TO_CHAR(l_asof, 'YYYY/MM/DD')
        || ' <span class="nt-sub">(الفترات كل ' || l_days || ' يوماً)</span></div>');
  htp.p('<div class="nt-block"><table class="fs ag"><thead><tr><th>الحساب</th><th>رقم الحساب</th><th>آخر حركة</th><th>الرصيد</th>'
        || '<th>حتى ' || l_days || ' يوم</th><th>' || (l_days + 1) || ' - ' || (2 * l_days) || '</th>'
        || '<th>' || (2 * l_days + 1) || ' - ' || (3 * l_days) || '</th><th>أكثر من ' || (3 * l_days) || '</th>'
        || '<th>رصيد عكسي (مقدم)</th></tr></thead><tbody>');

  FOR r IN (
    WITH l AS (
      SELECT jl.account_id, j.journal_date d, jl.line_id, l_sign * (jl.debit_base - jl.credit_base) net
      FROM   journal_lines jl
      JOIN   journals j ON j.journal_id = jl.journal_id AND j.status IN ('POSTED','REVERSED')
      JOIN   accounts a ON a.account_id = jl.account_id
      WHERE  a.account_code LIKE l_code || '%' AND a.acc_level = 4
      AND    j.journal_date < l_asof + 1
    ),
    b AS (SELECT account_id, SUM(net) bal, MAX(d) last_d FROM l GROUP BY account_id),
    inc AS (
      SELECT account_id, d, net amt,
             SUM(net) OVER (PARTITION BY account_id ORDER BY d DESC, line_id DESC ROWS UNBOUNDED PRECEDING) cum
      FROM   l WHERE net > 0
    ),
    alloc AS (
      SELECT i.account_id, l_asof - i.d age, LEAST(i.amt, GREATEST(b.bal - (i.cum - i.amt), 0)) amt
      FROM   inc i JOIN b ON b.account_id = i.account_id
      WHERE  b.bal > 0
    )
    SELECT a.account_id, a.account_code, a.name_ar, b.bal, b.last_d,
           NVL(SUM(CASE WHEN x.age <= l_days THEN x.amt END), 0) b1,
           NVL(SUM(CASE WHEN x.age > l_days AND x.age <= 2 * l_days THEN x.amt END), 0) b2,
           NVL(SUM(CASE WHEN x.age > 2 * l_days AND x.age <= 3 * l_days THEN x.amt END), 0) b3,
           NVL(SUM(CASE WHEN x.age > 3 * l_days THEN x.amt END), 0) b4
    FROM   b
    JOIN   accounts a ON a.account_id = b.account_id
    LEFT JOIN alloc x ON x.account_id = b.account_id
    WHERE  ROUND(b.bal, 2) <> 0
    GROUP  BY a.account_id, a.account_code, a.name_ar, b.bal, b.last_d
    ORDER  BY a.account_code
  ) LOOP
    n := n + 1;
    t_bal := t_bal + r.bal;
    t1 := t1 + r.b1; t2 := t2 + r.b2; t3 := t3 + r.b3; t4 := t4 + r.b4;
    IF r.bal < 0 THEN t_adv := t_adv - r.bal; END IF;
    htp.p('<tr><td class="lbl"><a href="' || apex_page.get_url(p_page => 81, p_clear_cache => 81,
            p_items => 'P81_ACCOUNT_ID,P81_TO', p_values => r.account_id || ',' || TO_CHAR(l_asof, 'DD/MM/YYYY'))
          || '" title="كشف الحساب">' || e(r.name_ar) || '</a></td><td class="nt">' || e(r.account_code) || '</td>'
          || '<td class="nt">' || TO_CHAR(r.last_d, 'YYYY/MM/DD') || '</td>'
          || '<td class="n b">' || f(GREATEST(r.bal, 0)) || '</td>'
          || '<td class="n">' || f(r.b1) || '</td><td class="n">' || f(r.b2) || '</td>'
          || '<td class="n">' || f(r.b3) || '</td><td class="n' || CASE WHEN r.b4 > 0 THEN ' old' END || '">' || f(r.b4) || '</td>'
          || '<td class="n">' || f(GREATEST(-r.bal, 0)) || '</td></tr>');
  END LOOP;

  IF n = 0 THEN
    htp.p('<tr><td colspan="9" class="nt-empty">لا توجد أرصدة على حسابات ' || e(l_name) || ' في هذا التاريخ</td></tr>');
  ELSE
    htp.p('<tr class="grand"><td class="lbl">الإجمالي (' || n || ' حساب)</td><td></td><td></td>'
          || '<td class="n">' || f(t1 + t2 + t3 + t4) || '</td><td class="n">' || f(t1) || '</td><td class="n">' || f(t2) || '</td>'
          || '<td class="n">' || f(t3) || '</td><td class="n">' || f(t4) || '</td><td class="n">' || f(t_adv) || '</td></tr>');
    IF t1 + t2 + t3 + t4 > 0 THEN
      htp.p('<tr class="pct"><td class="lbl">النسبة من الرصيد</td><td></td><td></td><td class="n">100%</td>'
            || '<td class="n">' || ROUND(100 * t1 / (t1 + t2 + t3 + t4)) || '%</td><td class="n">' || ROUND(100 * t2 / (t1 + t2 + t3 + t4)) || '%</td>'
            || '<td class="n">' || ROUND(100 * t3 / (t1 + t2 + t3 + t4)) || '%</td><td class="n">' || ROUND(100 * t4 / (t1 + t2 + t3 + t4)) || '%</td><td></td></tr>');
    END IF;
  END IF;
  htp.p('</tbody></table></div>');
END;
