var bud = {
  grid: null,
  months: ['M01','M02','M03','M04','M05','M06','M07','M08','M09','M10','M11','M12'],

  init: function () {
    var cols = [
      {name: 'ACCOUNT_ID', label: 'الحساب', type: 'lov', lov: 'accounts', required: true, width: '20em'},
      {name: 'ANNUAL', label: 'السنوي (توزيع)', type: 'number', decimals: 0, noSubmit: true, ignoreEmpty: true, width: '9em'}
    ];
    bud.months.forEach(function (m, i) {
      cols.push({name: m, label: String(i + 1), type: 'number', decimals: 0, total: true, width: '6.5em'});
    });
    cols.push({name: 'TOTAL', label: 'الإجمالي', type: 'display', decimals: 0, total: true, noSubmit: true});

    bud.grid = new JsonLines({
      container: '#bud_lines',
      readOnly: apex.item('P120_STATUS').getValue() === 'APPROVED',
      columns: cols,
      onChange: function (row, col) {
        if (col === 'ANNUAL' && row.ANNUAL) {                // توزيع بالتساوي والباقي على ديسمبر
          var each = Math.floor(row.ANNUAL / 12);
          bud.months.forEach(function (m) { row[m] = each; });
          row.M12 = row.ANNUAL - each * 11;
        }
        row.TOTAL = bud.months.reduce(function (s, m) { return s + (row[m] || 0); }, 0);
      }
    });
    bud.load('');
    EnterNav.first('#bud_lines');
  },

  load: function (copyFrom) {
    apex.server.process('INIT_DATA', {
      x01: apex.item('P120_COMPANY_ID').getValue(), x02: apex.item('P120_BUDGET_ID').getValue(),
      x03: copyFrom, x04: apex.item('P120_FY_YEAR').getValue()
    }, {dataType: 'json'}).done(function (d) {
      bud.grid.setLov('accounts', d.accounts);
      d.lines.forEach(function (r) { bud.grid.opts.onChange(r, 'M01', bud.grid); });
      bud.grid.setData(d.lines);
    });
  },

  save: function (action) {
    var errs = bud.grid.validate();
    if (errs.length) { DocUtil.showErrors(errs); return; }
    DocUtil.save({
      header: {COMPANY_ID: apex.item('P120_COMPANY_ID').getValue(), FY_YEAR: apex.item('P120_FY_YEAR').getValue(),
               NAME: apex.item('P120_NAME').getValue()},
      lines: bud.grid.getData()
    }, action, function () { apex.page.submit('RELOAD'); });
  }
};
