// الخطة (الموازنة التقديرية) لإدارة: كل بنود الميزانية بالأرباع الأربعة
var plan = {
  grid: null,
  init: function () {
    var status = apex.item('P122_STATUS').getValue() || 'DRAFT';
    plan.grid = new JsonLines({
      container: '#plan_lines',
      readOnly : !DocUtil.canEdit(status),
      columns  : [
        {name: 'BITEM_ID', label: '', type: 'display', hidden: true},
        {name: 'NOTE_NO',  label: 'الإيضاح', type: 'display', width: '6em'},
        {name: 'NAME_AR',  label: 'البند', type: 'display', width: '18em'},
        {name: 'TYPE_T',   label: 'النوع', type: 'display', width: '6em'},
        {name: 'Q1', label: 'الربع الأول',  type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'Q2', label: 'الربع الثاني', type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'Q3', label: 'الربع الثالث', type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'Q4', label: 'الربع الرابع', type: 'number', decimals: 2, total: true, width: '9em'},
        {name: 'TOTAL', label: 'الإجمالي', type: 'display', decimals: 2, total: true, noSubmit: true},
        {name: 'NOTES', label: 'ملاحظات', type: 'text', maxLength: 300, ignoreEmpty: true}
      ],
      onChange: function (row) { row.TOTAL = (row.Q1 || 0) + (row.Q2 || 0) + (row.Q3 || 0) + (row.Q4 || 0); }
    });
    apex.server.process('INIT_DATA', {x01: apex.item('P122_PLAN_ID').getValue()}, {dataType: 'json'})
      .done(function (d) {
        (d.lines || []).forEach(function (r) { r.TOTAL = (r.Q1 || 0) + (r.Q2 || 0) + (r.Q3 || 0) + (r.Q4 || 0); });
        plan.grid.setData(d.lines || []);
        // البنود معرّفة مسبقاً: لا سطر فارغ إضافي
        var last = plan.grid.rows[plan.grid.rows.length - 1];
        if (last && !last.BITEM_ID && plan.grid.rows.length > 1) { plan.grid.rows.pop(); plan.grid.render(); }
      });
    document.addEventListener('keydown', function (e) {
      if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); plan.save(); }
    });
  },

  save: function () {
    var g = function (n) { return apex.item('P122_' + n).getValue(); };
    if (!g('FY_YEAR') || !g('DEPT_ID')) { DocUtil.showErrors(['اختر السنة والإدارة']); return; }
    var doc = {
      header: {PLAN_ID: g('PLAN_ID'), FY_YEAR: g('FY_YEAR'), DEPT_ID: g('DEPT_ID'), DESCRIPTION: g('DESCRIPTION')},
      lines: plan.grid.rows.filter(function (r) { return r.BITEM_ID; }).map(function (r) {
        return {BITEM_ID: r.BITEM_ID, Q1: r.Q1, Q2: r.Q2, Q3: r.Q3, Q4: r.Q4, NOTES: r.NOTES};
      })
    };
    DocUtil.save(doc, 'DRAFT', function (d) {
      apex.page.submit({request: 'RELOAD', set: {P122_PLAN_ID: d.id}, showWait: true});
    });
  }
};
