var vch = {
  grid: null, companies: [],

  init: function () {
    var status = apex.item('P40_STATUS').getValue() || 'DRAFT';
    vch.grid = new JsonLines({
      container: '#v_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ACCOUNT_ID',  label: 'الحساب المقابل', type: 'lov', lov: 'accounts', required: true, width: '24em'},
        {name: 'AMOUNT',      label: 'المبلغ', type: 'number', decimals: 2, total: true, required: true, width: '10em'},
        {name: 'PARTNER_COMPANY_ID', label: 'شركة مقابلة', type: 'select', width: '12em',
         options: function () { return vch.companies; }},
        {name: 'DESCRIPTION', label: 'البيان', type: 'text', maxLength: 500, ignoreEmpty: true}
      ],
      newRow: function (r) { r.DESCRIPTION = apex.item('P40_DESCRIPTION').getValue() || null; },
      onTotals: function (t) {
        document.getElementById('v_words').textContent =
          JsonLines.fmt(t.AMOUNT || 0, 2) + ' ' + (apex.item('P40_CURRENCY_CODE').getValue() || '');
      }
    });
    vch.load();

    apex.jQuery('#P40_COMPANY_ID').on('change', vch.load);
    apex.jQuery('#P40_CURRENCY_CODE, #P40_VOUCHER_DATE').on('change', function () {
      DocUtil.loadRate('P40_CURRENCY_CODE', 'P40_VOUCHER_DATE', 'P40_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); vch.save('DRAFT'); }
    });
    EnterNav.first('#main');
  },

  load: function () {
    var keep = vch.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P40_COMPANY_ID').getValue(),
      x02: apex.item('P40_VOUCHER_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      vch.companies = d.companies;
      vch.grid.setLov('accounts', d.accounts);
      vch.grid.setData(keep.length ? keep : d.lines);
    });
  },

  save: function (action) {
    var errs = [];
    if (!apex.item('P40_CASH_ACCOUNT_ID').getValue()) errs.push('اختر الصندوق أو البنك');
    if (!apex.item('P40_VOUCHER_DATE').getValue())    errs.push('أدخل التاريخ');
    errs = errs.concat(vch.grid.validate());
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P40_' + n).getValue(); };
    var doc = {
      header: {
        VOUCHER_ID: g('VOUCHER_ID'), VOUCHER_TYPE: g('VOUCHER_TYPE'), COMPANY_ID: g('COMPANY_ID'),
        VOUCHER_DATE: g('VOUCHER_DATE'), CASH_ACCOUNT_ID: g('CASH_ACCOUNT_ID'),
        CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'),
        PAY_METHOD: g('PAY_METHOD'), CHEQUE_NO: g('CHEQUE_NO'), CHEQUE_DATE: g('CHEQUE_DATE'),
        BANK_NAME: g('BANK_NAME'), PARTY_NAME: g('PARTY_NAME'), DESCRIPTION: g('DESCRIPTION')
      },
      lines: vch.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P40_VOUCHER_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الإذن وإنشاء القيد؟', function (ok) { if (ok) go(); });
    else go();
  }
};
