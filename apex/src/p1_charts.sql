DECLARE
  -- رسوم لوحة المدير (HTML/CSS بدون مكتبات): الإيرادات والمصروفات شهرياً ، المبيعات نقدي / آجل ، أعلى 5 أصناف مبيعاً
  -- نفس مرشحات اللوحة: السنة ، الشركة ، العرض (المجمّع يستبعد المعاملات البينية) ، وقيد الإقفال لا يدخل
  l_year NUMBER := NVL(TO_NUMBER(:P1_YEAR), EXTRACT(YEAR FROM SYSDATE));
  TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  rev t_num; exp_ t_num;
  l_max NUMBER := 0; l_cash NUMBER := 0; l_credit NUMBER := 0; l_tot NUMBER; l_top NUMBER := 0;
  FUNCTION f (x NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G999G990'); END;
  -- مختصر للأعمدة: ألف / مليون
  FUNCTION s (x NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN ABS(x) >= 1e6 THEN TO_CHAR(ROUND(x / 1e6, 1), 'FM999G990D0') || ' م'
                WHEN ABS(x) >= 1e3 THEN TO_CHAR(ROUND(x / 1e3), 'FM999G990') || ' ألف'
                WHEN x = 0 THEN '' ELSE TO_CHAR(ROUND(x), 'FM990') END;
  END;
  FUNCTION pct (x NUMBER, m NUMBER) RETURN NUMBER IS
  BEGIN RETURN CASE WHEN NVL(m, 0) <= 0 OR NVL(x, 0) <= 0 THEN 0 ELSE GREATEST(ROUND(100 * x / m, 1), 1) END; END;
  FUNCTION e (t VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(t); END;
BEGIN
  FOR m IN 1 .. 12 LOOP rev(m) := 0; exp_(m) := 0; END LOOP;
  FOR r IN (
    SELECT EXTRACT(MONTH FROM j.journal_date) m,
           -SUM(CASE WHEN a.acc_type = 'REV' THEN l.debit_base - l.credit_base END) rv,
            SUM(CASE WHEN a.acc_type = 'EXP' THEN l.debit_base - l.credit_base END) ex
    FROM   journals j
    JOIN   journal_lines l ON l.journal_id = j.journal_id
    JOIN   accounts a ON a.account_id = l.account_id
    WHERE  j.status IN ('POSTED','REVERSED') AND j.source_type <> 'CLOSING'
    AND    EXTRACT(YEAR FROM j.journal_date) = l_year
    AND    a.acc_type IN ('REV','EXP')
    AND    (:P1_COMPANY_ID IS NULL OR j.company_id = :P1_COMPANY_ID)
    AND    (:G_USER_ROLE = 'ADMIN' OR j.company_id = :G_COMPANY_ID)
    AND    (NVL(:P1_MODE, 'SEP') = 'SEP' OR l.partner_company_id IS NULL)
    GROUP  BY EXTRACT(MONTH FROM j.journal_date)
  ) LOOP
    rev(r.m) := NVL(r.rv, 0); exp_(r.m) := NVL(r.ex, 0);
    l_max := GREATEST(l_max, rev(r.m), exp_(r.m));
  END LOOP;

  htp.p('<div class="ch-wrap">');
  ------------------------------------------------------------------ 1) الإيرادات والمصروفات شهرياً
  htp.p('<div class="ch-card ch-wide"><div class="ch-title">الإيرادات والمصروفات شهرياً - ' || l_year
        || ' <span class="ch-legend"><i class="rv"></i>الإيرادات <i class="ex"></i>المصروفات</span></div>');
  IF l_max = 0 THEN
    htp.p('<div class="ch-empty">لا توجد إيرادات أو مصروفات مرحّلة في ' || l_year || '</div>');
  ELSE
    htp.p('<div class="ch-cols">');
    FOR m IN 1 .. 12 LOOP
      htp.p('<div class="ch-col" title="شهر ' || m || ': الإيرادات ' || f(rev(m)) || ' ، المصروفات ' || f(exp_(m)) || ' ، الصافي ' || f(rev(m) - exp_(m)) || '">'
            || '<div class="ch-bars">'
            || '<div class="ch-bar rv" style="height:' || pct(rev(m), l_max) || '%"><span>' || s(rev(m)) || '</span></div>'
            || '<div class="ch-bar ex" style="height:' || pct(exp_(m), l_max) || '%"><span>' || s(exp_(m)) || '</span></div>'
            || '</div><div class="ch-lbl">' || m || '</div></div>');
    END LOOP;
    htp.p('</div>');
  END IF;
  htp.p('</div>');

  ------------------------------------------------------------------ 2) المبيعات نقدي / آجل (صافي بعد المرتجعات)
  SELECT NVL(SUM(CASE WHEN i.pay_type = 'CASH'   THEN amt END), 0),
         NVL(SUM(CASE WHEN i.pay_type = 'CREDIT' THEN amt END), 0)
  INTO   l_cash, l_credit
  FROM  (SELECT i.pay_type, CASE i.invoice_type WHEN 'SALE' THEN 1 ELSE -1 END * i.net_amount * i.exchange_rate amt
         FROM   invoices i
         WHERE  i.status = 'POSTED' AND EXTRACT(YEAR FROM i.invoice_date) = l_year
         AND    (:P1_COMPANY_ID IS NULL OR i.company_id = :P1_COMPANY_ID)
         AND    (:G_USER_ROLE = 'ADMIN' OR i.company_id = :G_COMPANY_ID)) i;
  l_tot := l_cash + l_credit;
  htp.p('<div class="ch-card"><div class="ch-title">المبيعات نقدي / آجل - ' || l_year || '</div>');
  IF l_tot <= 0 THEN
    htp.p('<div class="ch-empty">لا توجد مبيعات مرحّلة</div>');
  ELSE
    htp.p('<div class="ch-split"><div class="cs" style="width:' || ROUND(100 * GREATEST(l_cash, 0) / l_tot, 1) || '%"></div>'
          || '<div class="cr" style="width:' || ROUND(100 * GREATEST(l_credit, 0) / l_tot, 1) || '%"></div></div>');
    htp.p('<table class="ch-tab"><tr><td><i class="cs"></i>نقدي</td><td class="n">' || f(l_cash) || '</td><td class="n">' || ROUND(100 * l_cash / l_tot) || '%</td></tr>'
          || '<tr><td><i class="cr"></i>آجل</td><td class="n">' || f(l_credit) || '</td><td class="n">' || ROUND(100 * l_credit / l_tot) || '%</td></tr>'
          || '<tr class="t"><td>الإجمالي</td><td class="n">' || f(l_tot) || '</td><td></td></tr></table>');
  END IF;
  htp.p('</div>');

  ------------------------------------------------------------------ 3) أعلى 5 أصناف مبيعاً (صافي القيمة)
  htp.p('<div class="ch-card"><div class="ch-title">أعلى 5 أصناف مبيعاً - ' || l_year || '</div>');
  FOR r IN (
    SELECT name_ar, amt, MAX(amt) OVER () mx FROM (
      SELECT it.name_ar,
             SUM(CASE i.invoice_type WHEN 'SALE' THEN 1 ELSE -1 END * l.line_total
                 * CASE WHEN i.gross_amount > 0 THEN i.net_amount / i.gross_amount ELSE 1 END * i.exchange_rate) amt
      FROM   invoices i
      JOIN   invoice_lines l ON l.invoice_id = i.invoice_id
      JOIN   items it ON it.item_id = l.item_id
      WHERE  i.status = 'POSTED' AND EXTRACT(YEAR FROM i.invoice_date) = l_year
      AND    (:P1_COMPANY_ID IS NULL OR i.company_id = :P1_COMPANY_ID)
      AND    (:G_USER_ROLE = 'ADMIN' OR i.company_id = :G_COMPANY_ID)
      GROUP  BY it.name_ar
      ORDER  BY 2 DESC
    ) WHERE amt > 0 AND ROWNUM <= 5
  ) LOOP
    l_top := l_top + 1;
    htp.p('<div class="ch-hrow"><div class="ch-hl">' || e(r.name_ar) || '</div><div class="ch-ht"><div class="ch-hb" style="width:'
          || pct(r.amt, r.mx) || '%"></div></div><div class="ch-hv">' || f(r.amt) || '</div></div>');
  END LOOP;
  IF l_top = 0 THEN htp.p('<div class="ch-empty">لا توجد مبيعات مرحّلة</div>'); END IF;
  htp.p('</div>');
  htp.p('</div>');
END;
