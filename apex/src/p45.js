// إذن توريد / صرف شيكات: رأس الإذن + جدول الشيكات (JSON)
var chq = {
  grid: null,
  banks: [],

  init: function () {
    var status = apex.item('P45_STATUS').getValue() || 'DRAFT',
        pay    = apex.item('P45_VOUCHER_TYPE').getValue() === 'P',
        vdate  = apex.item('P45_VOUCHER_DATE').getValue() || null;

    chq.grid = new JsonLines({
      container: '#chq_lines',
      readOnly : !DocUtil.canEdit(status),
      columns  : [
        {name: 'CHEQUE_NO', label: 'رقم الشيك', type: 'text', required: true, maxLength: 30, width: '9em'},
        pay ? {name: 'BANK_ACCOUNT_ID', label: 'البنك المسحوب عليه', type: 'select', required: true, width: '16em',
               options: function () { return chq.banks; }}
            : {name: 'BANK_NAME', label: 'بنك الساحب', type: 'text', required: true, maxLength: 100, width: '14em'},
        {name: 'DUE_DATE', label: 'تاريخ الاستحقاق (يوم/شهر/سنة)', type: 'text', required: true, maxLength: 10, width: '9em',
         defaultValue: vdate},
        {name: 'AMOUNT', label: 'المبلغ', type: 'number', decimals: 2, total: true, required: true, width: '10em'},
        {name: 'PAYEE_NAME', label: pay ? 'المستفيد (يُطبع على الشيك)' : 'اسم الساحب', type: 'text', maxLength: 150, ignoreEmpty: true},
        {name: 'STATUS_T', label: 'حالة الشيك', type: 'display'}
      ],
      newRow: function (r) { r.PAYEE_NAME = apex.item('P45_PARTY_NAME').getValue() || null; },
      onTotals: function (t) {
        var el = document.getElementById('chq_total');
        if (el) el.textContent = JsonLines.fmt(t.AMOUNT || 0, 2);
      }
    });

    apex.server.process('INIT_DATA', {x01: apex.item('P45_VOUCHER_ID').getValue()}, {dataType: 'json'})
      .done(function (d) {
        chq.banks = d.banks || [];
        chq.grid.setData(d.lines || []);
      });

    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); chq.save(); }
    });
    EnterNav.first('#main');
  },

  save: function () {
    var errs = [], g = function (n) { return apex.item('P45_' + n).getValue(); };
    if (!g('VOUCHER_DATE'))       errs.push('أدخل تاريخ الإذن');
    if (!g('COUNTER_ACCOUNT_ID')) errs.push('اختر الحساب المقابل');
    if (!g('DESCRIPTION'))        errs.push('أدخل البيان');
    errs = errs.concat(chq.grid.validate());
    var lines = chq.grid.getData();
    if (!lines.length) errs.push('أدخل شيكاً واحداً على الأقل');
    lines.forEach(function (l, i) {
      if (l.DUE_DATE && !/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(l.DUE_DATE)) errs.push('الشيك ' + (i + 1) + ': تاريخ الاستحقاق بصيغة يوم/شهر/سنة');
    });
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var doc = {
      header: {
        VOUCHER_ID: g('VOUCHER_ID'), VOUCHER_TYPE: g('VOUCHER_TYPE'), VOUCHER_DATE: g('VOUCHER_DATE'),
        COUNTER_ACCOUNT_ID: g('COUNTER_ACCOUNT_ID'), PARTY_NAME: g('PARTY_NAME'), DESCRIPTION: g('DESCRIPTION')
      },
      lines: lines
    };
    DocUtil.save(doc, 'DRAFT', function (d) {
      apex.page.submit({request: 'RELOAD', set: {P45_VOUCHER_ID: d.id}, showWait: true});
    });
  }
};
