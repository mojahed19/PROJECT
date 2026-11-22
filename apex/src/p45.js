// إذن توريد / صرف شيكات: البنك والمستفيد في رأس الإذن + جدول الشيكات (JSON)
// لكل شيك مسلسل عام يُعطى عند الحفظ: 16 + السنة + 5 خانات
var chq = {
  grid: null,

  init: function () {
    var status = apex.item('P45_STATUS').getValue() || 'DRAFT',
        pay    = apex.item('P45_VOUCHER_TYPE').getValue() === 'P',
        vdate  = apex.item('P45_VOUCHER_DATE').getValue() || null;

    var cols = [
      {name: 'CHEQUE_SERIAL', label: 'المسلسل', type: 'display'},
      {name: 'CHEQUE_NO', label: 'رقم الشيك', type: 'text', required: true, maxLength: 30, width: '9em'},
      {name: 'DUE_DATE', label: 'تاريخ الصرف (يوم/شهر/سنة)', type: 'text', required: true, maxLength: 10, width: '9em',
       defaultValue: vdate},
      {name: 'AMOUNT', label: 'المبلغ', type: 'number', decimals: 2, total: true, required: true, width: '10em'}
    ];
    if (!pay) cols.push({name: 'BANK_NAME', label: 'بنك الساحب (اختياري)', type: 'text', maxLength: 100, width: '14em', ignoreEmpty: true});
    cols.push({name: 'STATUS_T', label: 'حالة الشيك', type: 'display'});

    chq.grid = new JsonLines({
      container: '#chq_lines',
      readOnly : !DocUtil.canEdit(status),
      columns  : cols,
      onTotals: function (t) {
        var el = document.getElementById('chq_total');
        if (el) el.textContent = JsonLines.fmt(t.AMOUNT || 0, 2);
      }
    });

    apex.server.process('INIT_DATA', {x01: apex.item('P45_VOUCHER_ID').getValue()}, {dataType: 'json'})
      .done(function (d) { chq.grid.setData(d.lines || []); });

    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); chq.save(); }
    });
    EnterNav.first('#main');
  },

  save: function () {
    var errs = [], g = function (n) { return apex.item('P45_' + n).getValue(); },
        pay = g('VOUCHER_TYPE') === 'P';
    if (!g('VOUCHER_DATE'))       errs.push('أدخل تاريخ الإذن');
    if (!g('BANK_ACCOUNT_ID'))    errs.push('اختر البنك');
    if (!g('COUNTER_ACCOUNT_ID')) errs.push('اختر الحساب المقابل');
    if (pay && !g('PARTY_NAME'))  errs.push('أدخل اسم المستفيد (يُطبع على الشيكات)');
    if (!g('DESCRIPTION'))        errs.push('أدخل البيان');
    errs = errs.concat(chq.grid.validate());
    var lines = chq.grid.getData();
    if (!lines.length) errs.push('أدخل شيكاً واحداً على الأقل');
    lines.forEach(function (l, i) {
      if (l.DUE_DATE && !/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(l.DUE_DATE)) errs.push('الشيك ' + (i + 1) + ': تاريخ الصرف بصيغة يوم/شهر/سنة');
    });
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var doc = {
      header: {
        VOUCHER_ID: g('VOUCHER_ID'), VOUCHER_TYPE: g('VOUCHER_TYPE'), VOUCHER_DATE: g('VOUCHER_DATE'),
        BANK_ACCOUNT_ID: g('BANK_ACCOUNT_ID'), COUNTER_ACCOUNT_ID: g('COUNTER_ACCOUNT_ID'),
        PARTY_NAME: g('PARTY_NAME'), DESCRIPTION: g('DESCRIPTION')
      },
      lines: lines
    };
    DocUtil.save(doc, 'DRAFT', function (d) {
      apex.page.submit({request: 'RELOAD', set: {P45_VOUCHER_ID: d.id}, showWait: true});
    });
  }
};
