DECLARE
  -- طباعة إذن توريد / صرف (نقدي أو شيكات) A4
  v vouchers%ROWTYPE;
  l_cash VARCHAR2(300); l_acc VARCHAR2(300); l_title VARCHAR2(100);
__TAFQEET__
  FUNCTION fn (n NUMBER) RETURN VARCHAR2 IS BEGIN RETURN TO_CHAR(NVL(n, 0), 'FM999G999G999G990D00'); END;
  FUNCTION e (s VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN apex_escape.html(s); END;
BEGIN
  BEGIN SELECT * INTO v FROM vouchers WHERE voucher_id = :P42_VOUCHER_ID;
  EXCEPTION WHEN NO_DATA_FOUND THEN htp.p('<p>الإذن غير موجود</p>'); RETURN; END;
  SELECT MAX(account_code || ' - ' || name_ar) INTO l_cash FROM accounts WHERE account_id = v.cash_account_id;
  SELECT MAX(account_code || ' - ' || name_ar) INTO l_acc  FROM accounts WHERE account_id = v.counter_account_id;
  l_title := CASE v.voucher_type WHEN 'R' THEN 'إذن توريد ' ELSE 'إذن صرف ' END
          || CASE v.voucher_kind WHEN 'CHEQUE' THEN 'شيكات' ELSE 'نقدي' END;

  htp.p('<div class="inv inv-a4">');
  htp.p('<div class="inv-title">' || e(l_title)
        || CASE WHEN v.status NOT IN ('APPROVED','POSTED') THEN ' <span class="inv-draft">(غير معتمد)</span>' END
        || CASE WHEN v.status = 'REVERSED' THEN ' <span class="inv-draft">(ملغى بقيد عكسي)</span>' END || '</div>');
  htp.p('<table class="inv-head">');
  htp.p('<tr><th>رقم الإذن</th><td class="inv-no">' || e(v.voucher_no) || '</td><th>التاريخ</th><td>' || TO_CHAR(v.voucher_date, 'DD/MM/YYYY') || '</td></tr>');
  htp.p('<tr><th>' || CASE v.voucher_type WHEN 'R' THEN 'استلمنا من' ELSE 'صرفنا إلى' END || '</th><td colspan="3">' || e(v.party_name) || '</td></tr>');
  IF v.voucher_kind = 'CASH' THEN
    htp.p('<tr><th>الخزينة</th><td colspan="3">' || e(l_cash) || '</td></tr>');
  END IF;
  htp.p('<tr><th>الحساب المقابل</th><td colspan="3">' || e(l_acc) || '</td></tr>');
  htp.p('<tr><th>المبلغ</th><td class="inv-no">' || fn(v.total_amount) || '</td><th>العملة</th><td>جنيه سوداني</td></tr>');
  htp.p('<tr><th>المبلغ كتابة</th><td colspan="3">' || e(tafqeet(v.total_amount)) || '</td></tr>');
  htp.p('<tr><th>البيان</th><td colspan="3">' || e(v.description) || '</td></tr>');
  htp.p('</table>');

  IF v.voucher_kind = 'CHEQUE' THEN
    htp.p('<table class="inv-lines"><thead><tr><th>#</th><th>رقم الشيك</th><th>البنك</th><th>تاريخ الاستحقاق</th>'
          || '<th>' || CASE v.voucher_type WHEN 'R' THEN 'الساحب' ELSE 'المستفيد' END || '</th><th>المبلغ</th></tr></thead><tbody>');
    FOR c IN (SELECT c.line_no, c.cheque_no, NVL(b.name_ar, c.bank_name) bank, c.due_date, c.payee_name, c.amount
              FROM cheques c LEFT JOIN accounts b ON b.account_id = c.bank_account_id
              WHERE c.voucher_id = v.voucher_id ORDER BY c.line_no) LOOP
      htp.p('<tr><td class="c">' || c.line_no || '</td><td>' || e(c.cheque_no) || '</td><td>' || e(c.bank) || '</td><td class="c">'
            || TO_CHAR(c.due_date, 'DD/MM/YYYY') || '</td><td>' || e(c.payee_name) || '</td><td class="n">' || fn(c.amount) || '</td></tr>');
    END LOOP;
    htp.p('</tbody></table>');
  END IF;

  htp.p('<table class="inv-sign"><tr><td>المدخل<br>' || e(v.created_by) || '<br>..................</td>'
        || '<td>المراجع<br>' || e(v.reviewed_by) || '<br>..................</td>'
        || '<td>المعتمد<br>' || e(v.approved_by) || '<br>..................</td>'
        || '<td>' || CASE v.voucher_type WHEN 'R' THEN 'المورِّد' ELSE 'المستلم' END || '<br><br>..................</td></tr></table>');
  htp.p('<div class="inv-foot">طُبع بواسطة ' || e(:APP_USER) || ' في ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || '</div>');
  htp.p('</div>');
END;
