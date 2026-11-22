DECLARE
  -- طباعة قيد يومية A4
  j journals%ROWTYPE;
  l_type VARCHAR2(100);
  FUNCTION fn (n NUMBER) RETURN VARCHAR2 IS BEGIN RETURN CASE WHEN NVL(n, 0) <> 0 THEN TO_CHAR(n, 'FM999G999G999G990D00') END; END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
BEGIN
  BEGIN SELECT * INTO j FROM journals WHERE journal_id = :P32_JOURNAL_ID;
  EXCEPTION WHEN NO_DATA_FOUND THEN htp.p('<p>القيد غير موجود</p>'); RETURN; END;
  SELECT MAX(name_ar) INTO l_type FROM journal_types WHERE jt_code = j.jt_code;

  htp.p('<div class="inv inv-a4">');
  htp.p('<div class="inv-title">' || e(l_type)
        || CASE WHEN j.status NOT IN ('POSTED','REVERSED') THEN ' <span class="inv-draft">(غير مرحّل)</span>' END
        || CASE WHEN j.status = 'REVERSED' THEN ' <span class="inv-draft">(معكوس)</span>' END || '</div>');
  htp.p('<table class="inv-head">');
  htp.p('<tr><th>رقم القيد</th><td class="inv-no">' || e(j.journal_no) || '</td><th>التاريخ</th><td>' || TO_CHAR(j.journal_date, 'DD/MM/YYYY') || '</td></tr>');
  htp.p('<tr><th>البيان</th><td colspan="3">' || e(j.description) || '</td></tr>');
  IF j.ref_no IS NOT NULL THEN htp.p('<tr><th>المرجع</th><td colspan="3">' || e(j.ref_no) || '</td></tr>'); END IF;
  htp.p('</table>');

  htp.p('<table class="inv-lines"><thead><tr><th>#</th><th>رقم الحساب</th><th>اسم الحساب</th><th>مدين</th><th>دائن</th><th>البيان</th></tr></thead><tbody>');
  FOR l IN (SELECT l.line_no, a.account_code, a.name_ar, l.debit, l.credit, l.description
            FROM journal_lines l JOIN accounts a ON a.account_id = l.account_id
            WHERE l.journal_id = j.journal_id ORDER BY l.line_no) LOOP
    htp.p('<tr><td class="c">' || l.line_no || '</td><td>' || e(l.account_code) || '</td><td>' || e(l.name_ar) || '</td><td class="n">'
          || fn(l.debit) || '</td><td class="n">' || fn(l.credit) || '</td><td>' || e(l.description) || '</td></tr>');
  END LOOP;
  htp.p('<tr class="inv-net"><td colspan="3"><b>الإجمالي</b></td><td class="n"><b>' || fn(j.total_debit) || '</b></td><td class="n"><b>'
        || fn(j.total_credit) || '</b></td><td></td></tr>');
  htp.p('</tbody></table>');

  htp.p('<table class="inv-sign"><tr><td>المدخل<br>' || e(j.created_by) || '<br>..................</td>'
        || '<td>المراجع<br>' || e(j.reviewed_by) || '<br>..................</td>'
        || '<td>المعتمد<br>' || e(j.approved_by) || '<br>..................</td></tr></table>');
  htp.p('<div class="inv-foot">طُبع بواسطة ' || e(:APP_USER) || ' في ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '</div>');
  htp.p('</div>');
END;
