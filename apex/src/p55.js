var pur = {
  grid: null,

  units: function (row, g) {
    var it = (g || pur.grid).lovRecord('items', row.ITEM_ID);
    return it ? it.units : [];
  },

  init: function () {
    var status = apex.item('P55_STATUS').getValue() || 'DRAFT';
    pur.grid = new JsonLines({
      container: '#pur_lines',
      readOnly : !DocUtil.canEdit(status),
      columns  : [
        {name: 'ITEM_ID',    label: 'الصنف (كود / اسم / باركود)', type: 'lov', lov: 'items', required: true, width: '26em'},
        {name: 'UNIT_ID',    label: 'الوحدة',   type: 'select', required: true, nullText: false, options: pur.units, width: '8em', readonly: true},
        {name: 'BAL',        label: 'الرصيد',   type: 'display', decimals: 2, noSubmit: true, width: '7em'},
        {name: 'QTY',        label: 'الكمية',   type: 'number', decimals: 2, required: true, width: '7em'},
        {name: 'PRICE',      label: 'سعر الشراء', type: 'number', decimals: 2, required: true, width: '9em', readonly: true},
        {name: 'DISCOUNT',   label: 'الخصم',    type: 'number', decimals: 2, total: true, width: '7em'},
        {name: 'LINE_TOTAL', label: 'الإجمالي', type: 'display', decimals: 2, total: true, noSubmit: true}
      ],
      onChange: function (row, col, g) {
        if (col === 'ITEM_ID') {
          var u = pur.units(row, g);
          row.UNIT_ID = row['ITEM_ID$unit'] || (u.length ? u[u.length - 1].v : null);   // وحدة الباركود أو الوحدة الكبرى
          col = 'UNIT_ID';
        }
        var unit = pur.units(row, g).filter(function (x) { return String(x.v) === String(row.UNIT_ID); })[0];
        if (col === 'UNIT_ID') {
          if (unit && unit.price != null) row.PRICE = unit.price;          // آخر سعر شراء لهذه الوحدة
          if (!row.QTY && row.ITEM_ID) row.QTY = 1;
        }
        var it = (g || pur.grid).lovRecord('items', row.ITEM_ID);
        row.BAL = it && unit ? it.bal / unit.factor : null;
        row.LINE_TOTAL = (row.QTY || 0) * (row.PRICE || 0) - (row.DISCOUNT || 0);
      },
      onTotals: function (t) {
        var disc = JsonLines.toNum(apex.item('P55_DISCOUNT_AMOUNT').getValue()) || 0;
        document.getElementById('pur_gross').textContent = JsonLines.fmt(t.LINE_TOTAL || 0, 2);
        document.getElementById('pur_net').textContent   = JsonLines.fmt((t.LINE_TOTAL || 0) - disc, 2);
      }
    });
    pur.load();

    apex.jQuery('#P55_WAREHOUSE_ID').on('change', pur.load);
    apex.jQuery('#P55_DISCOUNT_AMOUNT').on('change', function () { pur.grid._totals(); });
    apex.jQuery('#P55_CURRENCY_CODE, #P55_INVOICE_DATE').on('change', function () {
      DocUtil.loadRate('P55_CURRENCY_CODE', 'P55_INVOICE_DATE', 'P55_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); pur.save('DRAFT'); }
    });
    // طريقة الدفع: تتغير قائمة الحسابات فوراً
    DocUtil.payAccounts('P55_PAY_TYPE', 'P55_SUPPLIER_ACCOUNT_ID', 'PURCHASE', true);
    apex.jQuery('#P55_PAY_TYPE').on('change', function () { DocUtil.payAccounts('P55_PAY_TYPE', 'P55_SUPPLIER_ACCOUNT_ID', 'PURCHASE', false); });
    var nx = function () { DocUtil.nextNo('PURCHASE', 'P55_PINV_ID', 'P55_INVOICE_TYPE', 'P55_PAY_TYPE', 'P55_INVOICE_DATE'); };
    nx(); apex.jQuery('#P55_PAY_TYPE, #P55_INVOICE_DATE').on('change', nx);
    EnterNav.first('#main');
  },

  load: function () {
    var keep = pur.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P55_WAREHOUSE_ID').getValue(),
      x02: apex.item('P55_PINV_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      pur.grid.setLov('items', d.items);
      var rows = keep.length ? keep : d.lines;
      rows.forEach(function (r) { pur.grid.opts.onChange(r, 'QTY', pur.grid); });
      pur.grid.setData(rows);
    });
  },

  print: function () {
    window.open(apex.util.makeApplicationUrl({pageId: 57, itemNames: ['P57_PINV_ID'],
      itemValues: [apex.item('P55_PINV_ID').getValue()]}), 'print', 'width=900,height=1000');
  },

  save: function (action) {
    var errs = [];
    if (!apex.item('P55_WAREHOUSE_ID').getValue())        errs.push('اختر المخزن');
    if (!apex.item('P55_SUPPLIER_ACCOUNT_ID').getValue()) errs.push('اختر المورد / الخزينة');
    errs = errs.concat(pur.grid.validate());
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var g = function (n) { return apex.item('P55_' + n).getValue(); };
    var doc = {
      header: {
        PINV_ID: g('PINV_ID'), INVOICE_TYPE: g('INVOICE_TYPE'), COMPANY_ID: g('COMPANY_ID'),
        INVOICE_DATE: g('INVOICE_DATE'), SUPPLIER_INV_NO: g('SUPPLIER_INV_NO'), PAY_TYPE: g('PAY_TYPE'), PAY_METHOD: g('PAY_METHOD'),
        SUPPLIER_ACCOUNT_ID: g('SUPPLIER_ACCOUNT_ID'), SUPPLIER_NAME: g('SUPPLIER_NAME'),
        WAREHOUSE_ID: g('WAREHOUSE_ID'), CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'),
        DISCOUNT_AMOUNT: JsonLines.toNum(g('DISCOUNT_AMOUNT')), DESCRIPTION: g('DESCRIPTION')
      },
      lines: pur.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P55_PINV_ID: d.id, P55_LOADED_ID: ''}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الفاتورة: إضافة الكميات للمخزن وإنشاء القيد؟', function (ok) { if (ok) go(); });
    else go();
  }
};
