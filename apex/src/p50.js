var inv = {
  grid: null,

  units: function (row, g) {
    var it = (g || inv.grid).lovRecord('items', row.ITEM_ID);
    return it ? it.units : [];
  },

  init: function () {
    var status = apex.item('P50_STATUS').getValue() || 'DRAFT';
    inv.grid = new JsonLines({
      container: '#inv_lines',
      readOnly : status !== 'DRAFT' || !DocUtil.canEdit(status),
      columns  : [
        {name: 'ITEM_ID',    label: 'الصنف (كود / اسم / باركود)', type: 'lov', lov: 'items', required: true, width: '26em'},
        {name: 'UNIT_ID',    label: 'الوحدة',   type: 'select', required: true, nullText: false, options: inv.units, width: '8em', readonly: true},
        {name: 'BAL',        label: 'الرصيد',   type: 'display', decimals: 2, noSubmit: true, width: '7em'},
        {name: 'QTY',        label: 'الكمية',   type: 'number', decimals: 2, required: true, width: '7em'},
        {name: 'PRICE',      label: 'السعر',    type: 'number', decimals: 2, required: true, width: '9em', readonly: true},
        {name: 'DISCOUNT',   label: 'الخصم',    type: 'number', decimals: 2, total: true, width: '7em'},
        {name: 'LINE_TOTAL', label: 'الإجمالي', type: 'display', decimals: 2, total: true, noSubmit: true}
      ],
      onChange: function (row, col, g) {
        if (col === 'ITEM_ID') {
          var u = inv.units(row, g);
          row.UNIT_ID = row['ITEM_ID$unit'] || (u.length ? u[0].v : null);   // وحدة الباركود أو الأصغر
          col = 'UNIT_ID';
        }
        var unit = inv.units(row, g).filter(function (x) { return String(x.v) === String(row.UNIT_ID); })[0];
        if (col === 'UNIT_ID') {
          if (unit && unit.price != null) row.PRICE = unit.price;          // سعر قائمة الأسعار إن وُجد
          if (!row.QTY && row.ITEM_ID) row.QTY = 1;
        }
        var it = (g || inv.grid).lovRecord('items', row.ITEM_ID);
        row.BAL = it && unit ? it.bal / unit.factor : null;
        row.LINE_TOTAL = (row.QTY || 0) * (row.PRICE || 0) - (row.DISCOUNT || 0);
      },
      onTotals: function (t) {
        var disc = JsonLines.toNum(apex.item('P50_DISCOUNT_AMOUNT').getValue()) || 0;
        document.getElementById('inv_gross').textContent = JsonLines.fmt(t.LINE_TOTAL || 0, 2);
        document.getElementById('inv_net').textContent   = JsonLines.fmt((t.LINE_TOTAL || 0) - disc, 2);
      }
    });
    inv.loadItems(false);

    apex.jQuery('#P50_WAREHOUSE_ID').on('change', function () { inv.loadItems(false); });
    apex.jQuery('#P50_PRICE_LIST_ID').on('change', function () { inv.loadItems(true); });
    apex.jQuery('#P50_DISCOUNT_AMOUNT').on('change', function () { inv.grid._totals(); });
    apex.jQuery('#P50_CURRENCY_CODE, #P50_INVOICE_DATE').on('change', function () {
      DocUtil.loadRate('P50_CURRENCY_CODE', 'P50_INVOICE_DATE', 'P50_EXCHANGE_RATE');
    });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); inv.save('DRAFT'); }
    });
    // طريقة الدفع: تتغير قائمة الحسابات فوراً
    DocUtil.payAccounts('P50_PAY_TYPE', 'P50_ACCOUNT_ID', 'SALE', true);
    apex.jQuery('#P50_PAY_TYPE').on('change', function () { DocUtil.payAccounts('P50_PAY_TYPE', 'P50_ACCOUNT_ID', 'SALE', false); });
    // رقم الفاتورة الجديد يظهر فوراً ويتغير مع طريقة الدفع والتاريخ
    var nx = function () { DocUtil.nextNo('SALE', 'P50_INVOICE_ID', 'P50_INVOICE_TYPE', 'P50_PAY_TYPE', 'P50_INVOICE_DATE'); };
    nx(); apex.jQuery('#P50_PAY_TYPE, #P50_INVOICE_DATE').on('change', nx);
    EnterNav.first('#main');
  },

  // repriceAll = true عند تغيير قائمة الأسعار: تُعاد أسعار كل السطور
  loadItems: function (repriceAll) {
    var keep = inv.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P50_PRICE_LIST_ID').getValue(),
      x02: apex.item('P50_INVOICE_ID').getValue(),
      x03: apex.item('P50_WAREHOUSE_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      inv.grid.setLov('items', d.items);
      var rows = keep.length ? keep : d.lines;
      rows.forEach(function (r) { inv.grid.opts.onChange(r, repriceAll ? 'UNIT_ID' : 'QTY', inv.grid); });
      inv.grid.setData(rows);
    });
  },

  print: function (size) {
    window.open(apex.util.makeApplicationUrl({pageId: size === 'A4' ? 53 : 54,
      itemNames: ['P' + (size === 'A4' ? 53 : 54) + '_INVOICE_ID'], itemValues: [apex.item('P50_INVOICE_ID').getValue()]}),
      'print', size === 'A4' ? 'width=900,height=1000' : 'width=420,height=800');
  },

  save: function (action) {
    var errs = [], g = function (n) { return apex.item('P50_' + n).getValue(); };
    if (!g('WAREHOUSE_ID')) errs.push('اختر المخزن');
    if (!g('ACCOUNT_ID')) errs.push(g('PAY_TYPE') === 'CASH' ? 'اختر الخزينة أو الحساب البنكي' : 'اختر حساب العميل');
    errs = errs.concat(inv.grid.validate());
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var doc = {
      header: {
        INVOICE_ID: g('INVOICE_ID'), INVOICE_TYPE: g('INVOICE_TYPE'), INVOICE_DATE: g('INVOICE_DATE'),
        PAY_TYPE: g('PAY_TYPE'), ACCOUNT_ID: g('ACCOUNT_ID'),
        CUSTOMER_NAME: g('CUSTOMER_NAME'), WAREHOUSE_ID: g('WAREHOUSE_ID'), PRICE_LIST_ID: g('PRICE_LIST_ID'),
        CURRENCY_CODE: g('CURRENCY_CODE'), EXCHANGE_RATE: g('EXCHANGE_RATE'),
        DISCOUNT_AMOUNT: JsonLines.toNum(g('DISCOUNT_AMOUNT')), DESCRIPTION: g('DESCRIPTION')
      },
      lines: inv.grid.getData()
    };
    var go = function () {
      DocUtil.save(doc, action, function (d) {
        apex.page.submit({request: 'RELOAD', set: {P50_INVOICE_ID: d.id, P50_LOADED_ID: ''}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('ترحيل الفاتورة: خصم الكميات من المخزن وإنشاء القيد؟', function (ok) { if (ok) go(); });
    else go();
  }
};
