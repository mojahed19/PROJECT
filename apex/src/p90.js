var stk = {
  grid: null,

  unitsOf: function (row, g) { var it = (g || stk.grid).lovRecord('items', row.ITEM_ID); return it ? it.units : []; },
  factorOf: function (row) {
    var u = stk.unitsOf(row).filter(function (x) { return String(x.v) === String(row.UNIT_ID); })[0];
    return u ? u.factor : 1;
  },

  init: function () {
    var type = apex.item('P90_TRANS_TYPE').getValue(),
        status = apex.item('P90_STATUS').getValue() || 'DRAFT';

    stk.grid = new JsonLines({
      container: '#st_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ITEM_ID',   label: 'الصنف',  type: 'lov', lov: 'items', required: true, width: '24em'},
        {name: 'UNIT_ID',   label: 'الوحدة', type: 'select', nullText: false, required: true, options: stk.unitsOf, width: '8em'},
        {name: 'BAL',       label: 'الرصيد الحالي', type: 'display', decimals: 2, noSubmit: true, width: '8em'},
        {name: 'QTY',       label: type === 'COUNT' ? 'الكمية الفعلية' : 'الكمية',
         type: 'number', decimals: 2, required: true, width: '8em'},
        {name: 'UNIT_COST', label: 'تكلفة الوحدة', type: 'number', decimals: 4, width: '9em',
         hidden: type !== 'RECEIPT' && type !== 'OPENING'},
        {name: 'VALUE',     label: 'القيمة', type: 'display', decimals: 2, total: true, noSubmit: true,
         hidden: type !== 'RECEIPT' && type !== 'OPENING'}
      ],
      onChange: function (row, col) {
        if (col === 'ITEM_ID') { var u = stk.unitsOf(row); row.UNIT_ID = row['ITEM_ID$unit'] || (u.length ? u[0].v : null); }
        var it = stk.grid.lovRecord('items', row.ITEM_ID);
        row.BAL = it ? it.bal / stk.factorOf(row) : null;           // الرصيد بالوحدة المختارة
        row.VALUE = (row.QTY || 0) * (row.UNIT_COST || 0);
      }
    });
    stk.load();
    apex.jQuery('#P90_WAREHOUSE_ID').on('change', stk.load);
    apex.jQuery('#P90_CURRENCY_CODE, #P90_TRANS_DATE').on('change', function () {
      DocUtil.loadRate('P90_CURRENCY_CODE', 'P90_TRANS_DATE', 'P90_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); stk.save('DRAFT'); }
    });
    EnterNav.first('#main');
  },

  load: function () {
    var keep = stk.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P90_WAREHOUSE_ID').getValue(), x02: apex.item('P90_TRANS_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      stk.grid.setLov('items', d.items);
      var rows = keep.length ? keep : d.lines;
      rows.forEach(function (r) { stk.grid.opts.onChange(r, 'QTY', stk.grid); });
      stk.grid.setData(rows);
    });
  },

  save: function (action) {
    var errs = stk.grid.validate();
    if (!apex.item('P90_WAREHOUSE_ID').getValue()) errs.unshift('اختر المخزن');
    if (errs.length) { DocUtil.showErrors(errs); return; }
    var g = function (n) { return apex.item('P90_' + n).getValue(); };
    var doc = {
      header: {TRANS_ID: g('TRANS_ID'), TRANS_TYPE: g('TRANS_TYPE'), COMPANY_ID: g('COMPANY_ID'),
               TRANS_DATE: g('TRANS_DATE'), WAREHOUSE_ID: g('WAREHOUSE_ID'), TO_WAREHOUSE_ID: g('TO_WAREHOUSE_ID'),
               COUNTER_ACCOUNT_ID: g('COUNTER_ACCOUNT_ID'), CURRENCY_CODE: g('CURRENCY_CODE'),
               EXCHANGE_RATE: g('EXCHANGE_RATE'), DESCRIPTION: g('DESCRIPTION')},
      lines: stk.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P90_TRANS_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الحركة؟', function (ok) { if (ok) go(); }); else go();
  }
};
