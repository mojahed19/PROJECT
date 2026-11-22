DECLARE
  -- طباعة الشيك بمقاس الشيك البنكي: المواضع بالمليمتر من جدول cheque_layouts لكل بنك (أو المقاس الافتراضي)
  c  cheques%ROWTYPE;
  v  vouchers%ROWTYPE;
  ly cheque_layouts%ROWTYPE;
  l_bank VARCHAR2(200);
__TAFQEET__
  FUNCTION pos (p_top NUMBER, p_right NUMBER) RETURN VARCHAR2 IS
  BEGIN RETURN 'top:' || TO_CHAR(p_top, 'FM9990.0') || 'mm;right:' || TO_CHAR(p_right, 'FM9990.0') || 'mm;'; END;
BEGIN
  BEGIN
    SELECT * INTO c FROM cheques  WHERE cheque_id  = :P48_CHEQUE_ID;
    SELECT * INTO v FROM vouchers WHERE voucher_id = c.voucher_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN htp.p('<p>الشيك غير موجود</p>'); RETURN;
  END;
  IF v.voucher_type <> 'P' THEN htp.p('<p>الطباعة للشيكات الصادرة فقط</p>'); RETURN; END IF;
  IF v.status NOT IN ('APPROVED','POSTED') THEN htp.p('<p>لا يُطبع الشيك قبل اعتماد الإذن</p>'); RETURN; END IF;

  BEGIN
    SELECT * INTO ly FROM cheque_layouts WHERE bank_account_id = c.bank_account_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    SELECT * INTO ly FROM cheque_layouts WHERE bank_account_id IS NULL AND ROWNUM = 1;
  END;
  SELECT MAX(name_ar) INTO l_bank FROM accounts WHERE account_id = c.bank_account_id;

  htp.p('<style>@page { size: ' || ly.width_mm || 'mm ' || ly.height_mm || 'mm; margin: 0; }</style>');
  htp.p('<div class="no-print"><button type="button" class="t-Button t-Button--hot" onclick="window.print()">طباعة الشيك</button>'
        || ' &nbsp; <span style="color:#666">' || apex_escape.html(l_bank) || ' - مسلسل ' || c.cheque_serial || ' - شيك رقم ' || apex_escape.html(c.cheque_no)
        || ' - مقاس ' || ly.width_mm || ' × ' || ly.height_mm || ' مم (' || apex_escape.html(ly.layout_name) || ')</span></div>');
  htp.p('<div class="chq" style="width:' || ly.width_mm || 'mm;height:' || ly.height_mm || 'mm;font-size:' || ly.font_size || 'px">');
  htp.p('<div style="' || pos(ly.date_top, ly.date_right) || '">' || TO_CHAR(c.due_date, 'DD/MM/YYYY') || '</div>');
  htp.p('<div style="' || pos(ly.payee_top, ly.payee_right) || '">' || apex_escape.html(c.payee_name) || '</div>');
  htp.p('<div class="w" style="' || pos(ly.words_top, ly.words_right) || 'width:' || ly.words_width || 'mm">'
        || apex_escape.html(tafqeet(c.amount)) || '</div>');
  htp.p('<div style="' || pos(ly.amount_top, ly.amount_right) || 'direction:ltr">#' || TO_CHAR(c.amount, 'FM999G999G999G990D00') || '#</div>');
  htp.p('</div>');
END;
