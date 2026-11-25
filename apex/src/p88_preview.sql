DECLARE
  -- معاينة إقفال السنة: الحالة ، المستندات المعلّقة ، حسابات الإيرادات والمصروفات التي ستُصفّر ، وصافي النتيجة
  l_year NUMBER := TO_NUMBER(:P88_YEAR);
  fy     fiscal_years%ROWTYPE;
  l_pj   NUMBER; l_pv NUMBER; l_prev NUMBER;
  l_rev  NUMBER := 0; l_exp NUMBER := 0; n NUMBER := 0;
  l_ret  VARCHAR2(300);
  l_cl   VARCHAR2(30);
  FUNCTION f (x NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN CASE WHEN ROUND(NVL(x, 0), 2) = 0 THEN '..' ELSE TO_CHAR(x, 'FM999G999G999G999G990D00') END; END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
BEGIN
  IF l_year IS NULL THEN htp.p('<p class="nt-empty">اختر السنة المالية</p>'); RETURN; END IF;
  SELECT * INTO fy FROM fiscal_years WHERE fy_year = l_year;

  SELECT COUNT(*) INTO l_pj FROM journals
  WHERE  journal_date BETWEEN fy.start_date AND fy.end_date AND status IN ('DRAFT','RETURNED','REVIEWED','APPROVED');
  SELECT COUNT(*) INTO l_pv FROM vouchers
  WHERE  voucher_date BETWEEN fy.start_date AND fy.end_date AND status IN ('DRAFT','RETURNED','REVIEWED','APPROVED');
  SELECT COUNT(*) INTO l_prev FROM fiscal_years WHERE fy_year < l_year AND is_closed = 'N';
  SELECT MAX(a.account_code || ' - ' || a.name_ar) INTO l_ret
  FROM account_settings s JOIN accounts a ON a.account_id = s.account_id WHERE s.setting_code = 'RETAINED_EARNINGS';
  SELECT MAX(journal_no) INTO l_cl FROM journals WHERE source_type = 'CLOSING' AND source_id = fy.fy_id;

  htp.p('<div class="nt-head">إقفال السنة المالية ' || l_year || ' <span class="nt-sub">(' || TO_CHAR(fy.start_date, 'YYYY/MM/DD')
        || ' - ' || TO_CHAR(fy.end_date, 'YYYY/MM/DD') || ')</span></div>');
  htp.p('<div class="nt-block"><ul class="fy-st">');
  htp.p('<li>الحالة: ' || CASE fy.is_closed WHEN 'Y' THEN '<b class="bad">مقفلة</b>' || CASE WHEN l_cl IS NOT NULL THEN ' (قيد الإقفال ' || e(l_cl) || ')' END
                                             ELSE '<b class="ok">مفتوحة</b>' END || '</li>');
  IF fy.is_closed = 'N' THEN
    htp.p('<li class="' || CASE WHEN l_prev > 0 THEN 'bad' ELSE 'ok' END || '">السنوات السابقة: '
          || CASE WHEN l_prev > 0 THEN l_prev || ' سنة غير مقفلة (أقفلها أولاً)' ELSE 'مقفلة' END || '</li>');
    htp.p('<li class="' || CASE WHEN l_pj + l_pv > 0 THEN 'bad' ELSE 'ok' END || '">المستندات غير المرحّلة في السنة: '
          || CASE WHEN l_pj + l_pv > 0 THEN l_pj || ' قيد و ' || l_pv || ' إذن (رحّلها أو احذفها قبل الإقفال)' ELSE 'لا يوجد' END || '</li>');
    htp.p('<li class="' || CASE WHEN l_ret IS NULL THEN 'bad' ELSE 'ok' END || '">حساب الأرباح المرحّلة: '
          || NVL(e(l_ret), 'غير محدد (الحسابات الافتراضية: RETAINED_EARNINGS)') || '</li>');
  END IF;
  htp.p('</ul></div>');

  htp.p('<div class="nt-block"><div class="nt-title">' || CASE fy.is_closed WHEN 'Y' THEN 'الحسابات التي أُقفلت' ELSE 'الحسابات التي ستُقفل (تُصفّر في آخر يوم من السنة)' END || '</div>');
  htp.p('<table class="fs"><thead><tr><th>الحساب</th><th>رقم الحساب</th><th>النوع</th><th>الرصيد</th><th>قيد الإقفال</th></tr></thead><tbody>');
  FOR a IN (SELECT ac.account_code, ac.name_ar, ac.acc_type, SUM(jl.debit_base - jl.credit_base) bal
            FROM   journal_lines jl
            JOIN   journals j ON j.journal_id = jl.journal_id
            JOIN   accounts ac ON ac.account_id = jl.account_id
            WHERE  j.journal_date BETWEEN fy.start_date AND fy.end_date
            AND    j.status IN ('POSTED','REVERSED') AND j.source_type <> 'CLOSING'
            AND    ac.acc_type IN ('REV','EXP')
            GROUP  BY ac.account_code, ac.name_ar, ac.acc_type
            HAVING ROUND(SUM(jl.debit_base - jl.credit_base), 2) <> 0
            ORDER  BY ac.account_code) LOOP
    n := n + 1;
    IF a.acc_type = 'REV' THEN l_rev := l_rev - a.bal; ELSE l_exp := l_exp + a.bal; END IF;
    htp.p('<tr><td class="lbl">' || e(a.name_ar) || '</td><td class="nt">' || e(a.account_code) || '</td><td class="nt">'
          || CASE a.acc_type WHEN 'REV' THEN 'إيراد' ELSE 'مصروف' END || '</td><td class="n">'
          || f(ABS(a.bal)) || ' ' || CASE WHEN a.bal > 0 THEN 'مدين' ELSE 'دائن' END || '</td><td class="nt">'
          || CASE WHEN a.bal > 0 THEN 'دائن ' ELSE 'مدين ' END || f(ABS(a.bal)) || '</td></tr>');
  END LOOP;
  IF n = 0 THEN
    htp.p('<tr><td colspan="5" class="nt-empty">لا توجد حركات إيرادات أو مصروفات مرحّلة في السنة</td></tr>');
  END IF;
  htp.p('<tr class="grand"><td class="lbl">إجمالي الإيرادات</td><td></td><td></td><td class="n">' || f(l_rev) || '</td><td></td></tr>');
  htp.p('<tr class="grand"><td class="lbl">إجمالي المصروفات</td><td></td><td></td><td class="n">' || f(l_exp) || '</td><td></td></tr>');
  htp.p('<tr class="grand net"><td class="lbl">' || CASE WHEN l_rev - l_exp >= 0 THEN 'صافي الربح' ELSE 'صافي الخسارة' END
        || ' (إلى الأرباح المرحّلة)</td><td></td><td></td><td class="n">' || f(ABS(l_rev - l_exp)) || '</td><td class="nt">'
        || CASE WHEN l_rev - l_exp >= 0 THEN 'دائن ' ELSE 'مدين ' END || f(ABS(l_rev - l_exp)) || '</td></tr>');
  htp.p('</tbody></table></div>');
EXCEPTION WHEN NO_DATA_FOUND THEN
  htp.p('<p class="nt-empty">السنة غير موجودة في السنوات المالية</p>');
END;
