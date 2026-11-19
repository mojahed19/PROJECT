var jv = {
  grid: null,
  companies: [],

  init: function () {
    var status = apex.item('P30_STATUS').getValue() || 'DRAFT';

    jv.grid = new JsonLines({
      container: '#jv_lines',
      readOnly : status !== 'DRAFT',
      columns  : [
        {name: 'ACCOUNT_ID',  label: 'الحساب', type: 'lov', lov: 'accounts', required: true, width: '24em'},
        {name: 'DEBIT',       label: 'مدين',   type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'CREDIT',      label: 'دائن',   type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'DESCRIPTION', label: 'البيان', type: 'text', maxLength: 500, ignoreEmpty: true},
        {name: 'PARTNER_COMPANY_ID', label: 'شركة مقابلة', type: 'select', width: '12em',
         options: function () { return jv.companies; }}
      ],
      // مدين أو دائن فقط في السطر
      onChange: function (row, col) {
        if (col === 'DEBIT'  && row.DEBIT)  row.CREDIT = null;
        if (col === 'CREDIT' && row.CREDIT) row.DEBIT  = null;
      },
      // السطر الجديد يأخذ بيان السطر السابق أو بيان القيد
      newRow: function (r, g) {
        var prev = g.rows.length ? g.rows[g.rows.length - 1] : null;
        r.DESCRIPTION = (prev && prev.DESCRIPTION) || apex.item('P30_DESCRIPTION').getValue() || null;
      },
      onTotals: function (t) {
        var d = (t.DEBIT || 0) - (t.CREDIT || 0), el = document.getElementById('jv_diff');
        el.textContent = JsonLines.fmt(Math.abs(d), 2) + (Math.abs(d) < 0.005 ? ' ✔' : (d > 0 ? ' (مدين)' : ' (دائن)'));
        el.className = 'jv-diff ' + (Math.abs(d) < 0.005 ? 'ok' : 'bad');
      }
    });

    jv.load();

    // تغيير الشركة يعيد تحميل الحسابات (لكل شركة حساباتها الخاصة + المشتركة)
    apex.jQuery('#P30_COMPANY_ID').on('change', jv.load);
    // تغيير العملة أو التاريخ يجلب سعر الصرف
    apex.jQuery('#P30_CURRENCY_CODE, #P30_JOURNAL_DATE').on('change', function () {
      DocUtil.loadRate('P30_CURRENCY_CODE', 'P30_JOURNAL_DATE', 'P30_EXCHANGE_RATE');
    });
    // Ctrl+S = حفظ مسودة
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); jv.save('DRAFT'); }
    });

    EnterNav.first('#main');
  },

  load: function () {
    var keep = jv.grid.getData();
    apex.server.process('INIT_DATA', {
      x01: apex.item('P30_COMPANY_ID').getValue(),
      x02: apex.item('P30_JOURNAL_ID').getValue()
    }, {dataType: 'json'}).done(function (d) {
      jv.companies = d.companies;
      jv.grid.setLov('accounts', d.accounts);
      jv.grid.setData(keep.length ? keep : d.lines);
    });
  },

  save: function (action) {
    var errs = [], t = jv.grid.totals();
    if (!apex.item('P30_JT_CODE').getValue())       errs.push('اختر نوع القيد');
    if (!apex.item('P30_JOURNAL_DATE').getValue())  errs.push('أدخل التاريخ');
    if (!apex.item('P30_CURRENCY_CODE').getValue()) errs.push('اختر العملة');
    errs = errs.concat(jv.grid.validate());
    if (Math.abs((t.DEBIT || 0) - (t.CREDIT || 0)) >= 0.005) errs.push('القيد غير متوازن');
    if (errs.length) { DocUtil.showErrors(errs); return; }

    var doc = {
      header: {
        JOURNAL_ID   : apex.item('P30_JOURNAL_ID').getValue(),
        COMPANY_ID   : apex.item('P30_COMPANY_ID').getValue(),
        JT_CODE      : apex.item('P30_JT_CODE').getValue(),
        JOURNAL_DATE : apex.item('P30_JOURNAL_DATE').getValue(),
        CURRENCY_CODE: apex.item('P30_CURRENCY_CODE').getValue(),
        EXCHANGE_RATE: apex.item('P30_EXCHANGE_RATE').getValue(),
        REF_NO       : apex.item('P30_REF_NO').getValue(),
        DESCRIPTION  : apex.item('P30_DESCRIPTION').getValue()
      },
      lines: jv.grid.getData()
    };

    var go = function () {
      DocUtil.save(doc, action, function (d) {
        // إعادة فتح القيد المحفوظ
        apex.page.submit({request: 'RELOAD', set: {P30_JOURNAL_ID: d.id}, showWait: true});
      });
    };
    if (action === 'POST') apex.message.confirm('بعد الترحيل لا يمكن تعديل القيد. متابعة؟', function (ok) { if (ok) go(); });
    else go();
  },

  remove: function () {
    apex.message.confirm('حذف هذه المسودة نهائياً؟', function (ok) {
      if (!ok) return;
      apex.server.process('DELETE_DOC', {x01: apex.item('P30_JOURNAL_ID').getValue()}, {dataType: 'json'})
        .done(function (d) {
          if (d.ok) apex.navigation.redirect('f?p=&APP_ID.:31:&SESSION.::NO:30');
          else DocUtil.showErrors(['لا يمكن حذف هذا القيد']);
        });
    });
  }
};
