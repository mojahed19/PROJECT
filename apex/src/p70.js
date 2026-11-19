var adj = {
  grid: null,

  init: function () {
    var type   = apex.item('P70_ADJ_TYPE').getValue(),
        status = apex.item('P70_STATUS').getValue() || 'DRAFT',
        fixedSign = type === 'DED' ? '-' : (type === 'INC' ? '+' : null);

    adj.grid = new JsonLines({
      container: '#adj_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'EMPLOYEE_ID', label: 'الموظف', type: 'lov', lov: 'employees', required: true, width: '22em'},
        {name: 'COMPANY',     label: 'الشركة', type: 'display', noSubmit: true, width: '10em'},
        {name: 'GRADE',       label: 'الدرجة', type: 'display', noSubmit: true, width: '5em'},
        {name: 'DIRECTION',   label: '+/-',    type: 'select', nullText: false, width: '5em',
         defaultValue: fixedSign || '+', readonly: !!fixedSign,
         options: [{v: '+', t: '+ إضافة'}, {v: '-', t: '- خصم'}]},
        {name: 'AMOUNT',      label: 'المبلغ', type: 'number', decimals: 2, required: true, total: true, width: '10em'},
        {name: 'NOTES',       label: 'ملاحظات', type: 'text', maxLength: 300}
      ],
      onChange: function (row, col, g) {
        if (col === 'EMPLOYEE_ID') adj.fillEmp(row, g);
      }
    });

    apex.server.process('INIT_DATA', {x01: apex.item('P70_ADJ_ID').getValue()}, {dataType: 'json'})
      .done(function (d) {
        adj.grid.setLov('employees', d.employees);
        d.lines.forEach(function (r) { adj.fillEmp(r, adj.grid); });
        adj.grid.setData(d.lines);
      });

    apex.jQuery('#P70_CURRENCY_CODE, #P70_ADJ_DATE').on('change', function () {
      DocUtil.loadRate('P70_CURRENCY_CODE', 'P70_ADJ_DATE', 'P70_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); adj.save('DRAFT'); }
    });
    EnterNav.first('#main');
  },

  // يعرض شركة الموظف ودرجته بجانب اسمه
  fillEmp: function (row, g) {
    var e = g.lovRecord('employees', row.EMPLOYEE_ID);
    row.COMPANY = e ? e.company : null;
    row.GRADE   = e ? e.grade   : null;
  },

  save: function (action) {
    var errs = [];
    if (action !== 'CANCEL') {
      if (!apex.item('P70_PAY_PERIOD').getValue()) errs.push('اختر شهر الراتب');
      if (!apex.item('P70_REASON').getValue())     errs.push('السبب مطلوب');
      errs = errs.concat(adj.grid.validate());
    }
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P70_' + n).getValue(); };
    var doc = {
      header: {
        ADJ_ID: g('ADJ_ID'), ADJ_TYPE: g('ADJ_TYPE'), ADJ_DATE: g('ADJ_DATE'),
        PAY_PERIOD: g('PAY_PERIOD'), ALLOWANCE_ID: g('ALLOWANCE_ID'),
        CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'), REASON: g('REASON')
      },
      lines: adj.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P70_ADJ_ID: d.id}, showWait: true});
      });
    };
    var msg = {APPROVE: 'اعتماد المستند؟ لن يمكن تعديله بعد ذلك', CANCEL: 'إلغاء المستند؟'}[action];
    if (msg) apex.message.confirm(msg, function (ok) { if (ok) go(); });
    else go();
  }
};
