var brb = {
  grid: null,

  init: function () {
    brb.grid = new JsonLines({
      container: '#brb_lines',
      columns  : [
        {name: 'ACCOUNT_ID', label: 'الحساب (كود / اسم)', type: 'lov', lov: 'accounts', required: true, width: '26em'},
        {name: 'DEBIT',      label: 'مدين',   type: 'number', decimals: 2, total: true, width: '10em'},
        {name: 'CREDIT',     label: 'دائن',   type: 'number', decimals: 2, total: true, width: '10em'},
        {name: 'NOTES',      label: 'ملاحظات', type: 'text', maxLength: 300}
      ],
      onChange: function (row, col) {
        if (col === 'DEBIT'  && row.DEBIT)  row.CREDIT = null;
        if (col === 'CREDIT' && row.CREDIT) row.DEBIT  = null;
      },
      onTotals: function (t) {
        var d = (t.DEBIT || 0) - (t.CREDIT || 0), el = document.getElementById('brb_diff');
        el.textContent = JsonLines.fmt(Math.abs(d), 2) + (Math.abs(d) < 0.005 ? ' ✔ متوازنة' : (d > 0 ? ' (المدين أكبر)' : ' (الدائن أكبر)'));
        el.className = 'jv-diff ' + (Math.abs(d) < 0.005 ? 'ok' : 'bad');
      }
    });
    brb.load();
    apex.jQuery('#P125_COMPANY_ID, #P125_AS_OF_DATE').on('change', brb.load);
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); brb.save(); }
    });
  },

  load: function () {
    if (!apex.item('P125_COMPANY_ID').getValue() || !apex.item('P125_AS_OF_DATE').getValue()) return;
    apex.server.process('INIT_DATA', {
      x01: apex.item('P125_COMPANY_ID').getValue(), x02: apex.item('P125_AS_OF_DATE').getValue()
    }, {dataType: 'json'}).done(function (d) {
      brb.grid.setLov('accounts', d.accounts);
      brb.grid.setData(d.lines);
    });
  },

  save: function () {
    var errs = brb.grid.validate(), t = brb.grid.totals();
    if (!apex.item('P125_COMPANY_ID').getValue()) errs.unshift('اختر الفرع');
    if (!apex.item('P125_AS_OF_DATE').getValue()) errs.unshift('أدخل تاريخ الميزانية');
    if (Math.abs((t.DEBIT || 0) - (t.CREDIT || 0)) >= 0.005) errs.push('الميزانية غير متوازنة');
    if (errs.length) { DocUtil.showErrors(errs); return; }
    DocUtil.save({
      header: {COMPANY_ID: apex.item('P125_COMPANY_ID').getValue(), AS_OF_DATE: apex.item('P125_AS_OF_DATE').getValue()},
      lines: brb.grid.getData()
    }, 'SAVE', function () { brb.load(); });
  }
};
