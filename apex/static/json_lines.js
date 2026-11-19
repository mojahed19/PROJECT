/* =====================================================================
 * json_lines.js  -  جدول تفاصيل (سطور) يعمل بـ JSON بدلاً من Interactive Grid
 * يُستخدم في: قيود اليومية، سندات القبض والصرف، الفواتير، الخصم/الفرق/الحافز
 *
 *  var grid = new JsonLines({
 *    container : '#lines',                       // div داخل Static Content region
 *    columns   : [
 *      {name:'ACCOUNT_ID', label:'الحساب', type:'lov', lov:'accounts', required:true, width:'12em'},
 *      {name:'DEBIT',  label:'مدين', type:'number', decimals:2, total:true},
 *      {name:'UNIT_ID',label:'الوحدة', type:'select', options:function(row){ return [{v:1,t:'حبة'}]; }},
 *      {name:'TOTAL',  label:'الإجمالي', type:'display', decimals:2, total:true},
 *      {name:'NOTES',  label:'البيان', type:'text'}
 *    ],
 *    onChange  : function(row, colName, grid){ ... },   // لحساب الحقول أو تعبئة الأسعار
 *    onTotals  : function(totals, grid){ ... },
 *    readOnly  : false
 *  });
 *  grid.setLov('accounts', [{id:1, code:'1101001', name:'الصندوق'}]);
 *  grid.setData([...]);   grid.getData();   grid.validate();
 *
 *  لوحة المفاتيح:
 *   Enter            الخلية التالية (عبر enter_nav.js) - وفي آخر خلية من آخر سطر يُضاف سطر جديد
 *   Ctrl + Delete    حذف السطر الحالي
 *   Ctrl + Insert    إدراج سطر بعد الحالي
 *   F9 في خانة الحساب/الصنف: قائمة البحث (datalist)
 * ===================================================================== */
(function () {
  "use strict";

  var seq = 0;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }
  function toNum(v) {
    if (v === null || v === undefined || v === '') return null;
    var n = parseFloat(String(v).replace(/,/g, '').replace(/[٠-٩]/g, function (d) { return d.charCodeAt(0) - 1632; }));
    return isNaN(n) ? null : n;
  }
  function fmt(n, dec) {
    if (n === null || n === undefined || n === '') return '';
    return Number(n).toLocaleString('en-US', {minimumFractionDigits: dec, maximumFractionDigits: dec});
  }

  function JsonLines(opts) {
    this.opts      = opts;
    this.cols      = opts.columns;
    this.rows      = [];
    this.lovs      = {};      // name -> {list:[], byCode:{}, byId:{}}
    this.readOnly  = !!opts.readOnly;
    this.id        = 'jl' + (++seq);
    this.$root     = document.querySelector(opts.container);
    this._build();
    this.setData([]);
  }

  /* ---------------- LOV ---------------- */
  // توحيد الحروف العربية للبحث: أ إ آ ← ا ، ة ← ه ، ى ← ي ، وحذف التشكيل والتطويل
  function norm(s) {
    return String(s == null ? '' : s).toLowerCase()
      .replace(/[ً-ْـ]/g, '')
      .replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي')
      .replace(/[٠-٩]/g, function (d) { return d.charCodeAt(0) - 1632; })
      .trim();
  }

  /* سجل القائمة: {id, code, name, bc: {باركود: رقم الوحدة}} - bc اختياري */
  JsonLines.prototype.setLov = function (name, list) {
    var byCode = {}, byId = {}, byBc = {};
    list.forEach(function (r) {
      r._k = norm(r.code + ' ' + r.name);
      if (r.bc0) { r.bc = r.bc || {}; r.bc[r.bc0] = r.bu; }   // باركود الصنف = الوحدة الأساسية
      byCode[String(r.code).toUpperCase()] = r;
      if (!(r.id in byId)) byId[r.id] = r;
      if (r.bc) Object.keys(r.bc).forEach(function (b) { byBc[norm(b)] = {rec: r, unit: r.bc[b]}; });
    });
    this.lovs[name] = {list: list, byCode: byCode, byId: byId, byBc: byBc};
    // إعادة عرض الأسماء بعد تحميل القائمة
    for (var i = 0; i < this.rows.length; i++) this.refreshRow(i);
  };

  JsonLines.prototype.lovRecord = function (lovName, id) {
    var l = this.lovs[lovName];
    return l && id != null ? l.byId[id] || null : null;
  };

  // البحث: الكود أو الباركود يبدأ بالنص، أو كل كلمات النص موجودة في الاسم/الكود
  JsonLines.prototype.searchLov = function (lovName, text, max) {
    var l = this.lovs[lovName];
    if (!l) return [];
    var q = norm(text);
    if (!q) return l.list.slice(0, max || 30);
    var words = q.split(/\s+/), out = [], seen = {};
    function add(r, unit) { if (!seen[r.id]) { seen[r.id] = 1; out.push({rec: r, unit: unit}); } }
    Object.keys(l.byBc).forEach(function (b) { if (b.indexOf(q) === 0) add(l.byBc[b].rec, l.byBc[b].unit); });
    l.list.forEach(function (r) { if (norm(r.code).indexOf(q) === 0) add(r); });
    l.list.forEach(function (r) {
      if (words.every(function (w) { return r._k.indexOf(w) >= 0; })) add(r);
    });
    return out.slice(0, max || 30);
  };

  JsonLines.prototype._resolveLov = function (col, text) {
    var l = this.lovs[col.lov];
    if (!l) return {ok: false};
    text = (text || '').trim();
    if (!text) return {ok: true, rec: null};
    var rec = l.byCode[text.toUpperCase()];
    if (rec) return {ok: true, rec: rec};
    var bc = l.byBc[norm(text)];
    if (bc) return {ok: true, rec: bc.rec, unit: bc.unit};
    var m = this.searchLov(col.lov, text, 2);
    if (m.length === 1) return {ok: true, rec: m[0].rec, unit: m[0].unit};
    return {ok: false, many: m.length > 1};
  };

  /* ---------------- نافذة البحث المنسدلة ---------------- */
  JsonLines.prototype._popShow = function (el) {
    var self = this, c = this._col(el.dataset.col);
    var res = this.searchLov(c.lov, el.value, 40);
    if (!this.$pop) {
      this.$pop = document.createElement('div');
      this.$pop.className = 'jl-pop';
      document.body.appendChild(this.$pop);
      this.$pop.addEventListener('mousedown', function (e) {
        var o = e.target.closest('.jl-opt');
        if (!o) return;
        e.preventDefault();
        var r = self._popRes[+o.dataset.i];
        self._pick(self._popEl, r.rec, r.unit);
      });
    }
    this._popEl = el; this._popRes = res; this._popIdx = res.length ? 0 : -1;
    if (!res.length) {
      this.$pop.innerHTML = '<div class="jl-opt jl-none">لا توجد نتائج</div>';
    } else {
      this.$pop.innerHTML = res.map(function (r, i) {
        return '<div class="jl-opt' + (i === 0 ? ' is-active' : '') + '" data-i="' + i + '">' +
               '<span class="jl-opt-code">' + esc(r.rec.code) + '</span> ' + esc(r.rec.name) +
               (r.rec.info ? ' <span class="jl-opt-info">' + esc(r.rec.info) + '</span>' : '') + '</div>';
      }).join('');
    }
    var rc = el.getBoundingClientRect();
    this.$pop.style.top = (rc.bottom + 2) + 'px';
    this.$pop.style.right = (window.innerWidth - rc.right) + 'px';
    this.$pop.style.display = 'block';
  };

  JsonLines.prototype._popHide = function () { if (this.$pop) this.$pop.style.display = 'none'; this._popEl = null; };
  JsonLines.prototype._popOpen = function () { return this.$pop && this.$pop.style.display === 'block' && this._popEl; };

  JsonLines.prototype._popMove = function (d) {
    if (!this._popRes.length) return;
    this._popIdx = (this._popIdx + d + this._popRes.length) % this._popRes.length;
    var opts = this.$pop.querySelectorAll('.jl-opt');
    opts.forEach(function (o, i) { o.classList.toggle('is-active', i === this._popIdx); }, this);
    opts[this._popIdx].scrollIntoView({block: 'nearest'});
  };

  // اختيار سجل: تعبئة الخلية ثم الانتقال للخلية التالية
  JsonLines.prototype._pick = function (el, rec, unit) {
    this._popHide();
    el.value = rec.code;
    this._onInput(el, true, {rec: rec, unit: unit});
    var next = this.$tbody.querySelector('tr[data-idx="' + el.closest('tr').dataset.idx + '"] [data-col="' + el.dataset.col + '"]');
    if (next && window.EnterNav) window.EnterNav.next(next);
  };

  /* ---------------- البناء ---------------- */
  JsonLines.prototype._build = function () {
    var self = this, h = [];
    h.push('<table class="jl-table" id="' + this.id + '"><thead><tr><th class="jl-no">#</th>');
    this.cols.forEach(function (c) {
      if (c.hidden) return;
      h.push('<th' + (c.width ? ' style="width:' + c.width + '"' : '') + '>' + esc(c.label) +
             (c.required ? ' <span class="jl-req">*</span>' : '') + '</th>');
    });
    h.push('<th class="jl-act"></th></tr></thead><tbody></tbody><tfoot><tr><td class="jl-no"></td>');
    this.cols.forEach(function (c) {
      if (c.hidden) return;
      h.push('<td data-total="' + c.name + '" class="' + (c.total ? 'jl-num' : '') + '"></td>');
    });
    h.push('<td></td></tr></tfoot></table>');
    if (!this.readOnly) {
      h.push('<button type="button" class="t-Button t-Button--small t-Button--icon t-Button--iconLeft jl-add" tabindex="-1">' +
             '<span class="t-Icon fa fa-plus" aria-hidden="true"></span>إضافة سطر</button>');
    }
    this.$root.innerHTML = h.join('');
    this.$tbody = this.$root.querySelector('tbody');
    this.$tfoot = this.$root.querySelector('tfoot');

    var add = this.$root.querySelector('.jl-add');
    if (add) add.addEventListener('click', function () { self.addRow(null, true); });

    this.$tbody.addEventListener('click', function (e) {
      var b = e.target.closest('.jl-del');
      if (b) self.removeRow(+b.closest('tr').dataset.idx);
    });
    this.$tbody.addEventListener('change', function (e) { self._onInput(e.target, true); });
    this.$tbody.addEventListener('input', function (e) {
      if (e.target.dataset.type === 'number') self._onInput(e.target, false);
      if (e.target.dataset.type === 'lov' && !e.target.readOnly) self._popShow(e.target);
    });
    this.$tbody.addEventListener('focusout', function (e) {
      var el = e.target;
      if (el.dataset.type === 'lov') setTimeout(function () { if (self._popEl === el && document.activeElement !== el) self._popHide(); }, 150);
      if (el.dataset.type === 'number') {
        var r = self.rows[+el.closest('tr').dataset.idx];
        if (r) el.value = fmt(r[el.dataset.col], self._col(el.dataset.col).decimals || 0);
      }
    });
    this.$tbody.addEventListener('keydown', function (e) { self._onKey(e); });
  };

  JsonLines.prototype._col = function (name) {
    for (var i = 0; i < this.cols.length; i++) if (this.cols[i].name === name) return this.cols[i];
  };

  JsonLines.prototype._cellHtml = function (c, row, idx) {
    var v = row[c.name], ro = this.readOnly || c.readonly ||
            (typeof c.readonlyIf === 'function' && c.readonlyIf(row));
    var base = ' data-col="' + c.name + '" data-type="' + c.type + '"' + (ro ? ' readonly tabindex="-1"' : '');
    switch (c.type) {
      case 'lov':
        var rec = this.lovRecord(c.lov, v);
        return '<input type="text" class="jl-in jl-code"' + base + '' +
               ' value="' + esc(rec ? rec.code : (row[c.name + '$text'] || '')) + '" autocomplete="off">' +
               '<span class="jl-name">' + esc(rec ? rec.name : '') + '</span>';
      case 'number':
        return '<input type="text" inputmode="decimal" class="jl-in jl-num"' + base +
               ' value="' + esc(fmt(v, c.decimals || 0)) + '">';
      case 'select':
        var opts = typeof c.options === 'function' ? c.options(row, this) : (c.options || []);
        return '<select class="jl-in"' + base + (ro ? ' disabled' : '') + '>' +
               (c.nullText !== false ? '<option value="">' + esc(c.nullText || '') + '</option>' : '') +
               opts.map(function (o) {
                 return '<option value="' + esc(o.v) + '"' + (String(o.v) === String(v) ? ' selected' : '') + '>' +
                        esc(o.t) + '</option>';
               }).join('') + '</select>';
      case 'display':
        return '<span class="jl-disp' + (c.decimals != null ? ' jl-num' : '') + '" data-col="' + c.name + '">' +
               esc(c.decimals != null ? fmt(v, c.decimals) : v) + '</span>';
      default:
        return '<input type="text" class="jl-in"' + base + ' value="' + esc(v) + '"' +
               (c.maxLength ? ' maxlength="' + c.maxLength + '"' : '') + '>';
    }
  };

  JsonLines.prototype._rowHtml = function (row, idx) {
    var self = this, h = ['<tr data-idx="' + idx + '"><td class="jl-no">' + (idx + 1) + '</td>'];
    this.cols.forEach(function (c) {
      if (c.hidden) return;
      h.push('<td class="jl-' + c.type + '">' + self._cellHtml(c, row, idx) + '</td>');
    });
    h.push('<td class="jl-act">' + (this.readOnly ? '' :
      '<button type="button" class="jl-del" tabindex="-1" title="حذف السطر (Ctrl+Delete)">' +
      '<span class="fa fa-trash-o" aria-hidden="true"></span></button>') + '</td></tr>');
    return h.join('');
  };

  JsonLines.prototype.render = function () {
    var self = this;
    this.$tbody.innerHTML = this.rows.map(function (r, i) { return self._rowHtml(r, i); }).join('');
    this._totals();
  };

  JsonLines.prototype.refreshRow = function (idx) {
    var tr = this.$tbody.querySelector('tr[data-idx="' + idx + '"]');
    if (!tr) return;
    var active = document.activeElement, col = active && tr.contains(active) ? active.dataset.col : null;
    var tmp = document.createElement('tbody');
    tmp.innerHTML = this._rowHtml(this.rows[idx], idx);
    tr.parentNode.replaceChild(tmp.firstChild, tr);
    if (col) {
      var el = this.$tbody.querySelector('tr[data-idx="' + idx + '"] [data-col="' + col + '"]');
      if (el && el.focus) el.focus();
    }
  };

  /* ---------------- الأحداث ---------------- */
  JsonLines.prototype._onInput = function (el, committed, forced) {
    var tr = el.closest('tr'); if (!tr) return;
    var idx = +tr.dataset.idx, row = this.rows[idx], c = this._col(el.dataset.col);
    if (!row || !c) return;

    if (c.type === 'lov') {
      if (!committed) return;
      if (!forced && row[c.name] != null && row[c.name + '$text'] === el.value) return;   // لم يتغير
      var res = forced ? {ok: true, rec: forced.rec, unit: forced.unit} : this._resolveLov(c, el.value);
      row[c.name + '$unit'] = res.unit || null;   // وحدة الباركود إن وُجدت
      el.classList.toggle('jl-err', !res.ok);
      row[c.name] = res.ok && res.rec ? res.rec.id : null;
      row[c.name + '$text'] = el.value;
      tr.querySelector('[data-col="' + c.name + '"] + .jl-name').textContent = res.rec ? res.rec.name : (res.ok ? '' : 'غير موجود');
    } else if (c.type === 'number') {
      row[c.name] = toNum(el.value);
    } else {
      row[c.name] = el.value === '' ? null : el.value;
    }

    if (committed && this.opts.onChange) {
      var before = JSON.stringify(row);
      this.opts.onChange(row, c.name, this);
      if (JSON.stringify(row) !== before) this._syncRow(idx, c.name);
    } else if (!committed && this.opts.onChange && c.type === 'number') {
      this.opts.onChange(row, c.name, this);
      this._syncRow(idx, c.name);
    }
    this._totals();
  };

  // تحديث الخلايا التي تغيّرت بالحساب دون إعادة بناء الخلية التي يكتب فيها المستخدم
  JsonLines.prototype._syncRow = function (idx, editingCol) {
    var self = this, tr = this.$tbody.querySelector('tr[data-idx="' + idx + '"]'), row = this.rows[idx];
    this.cols.forEach(function (c) {
      if (c.hidden || c.name === editingCol) return;
      var td = tr.querySelector('[data-col="' + c.name + '"]');
      if (!td) return;
      td = td.closest('td');
      var html = self._cellHtml(c, row, idx);
      if (td.innerHTML !== html) td.innerHTML = html;
    });
  };

  JsonLines.prototype._onKey = function (e) {
    var el = e.target, tr = el.closest('tr');
    if (!tr) return;
    var idx = +tr.dataset.idx;

    if (e.ctrlKey && e.key === 'Delete') { e.preventDefault(); this.removeRow(idx, true); return; }
    if (e.ctrlKey && e.key === 'Insert') { e.preventDefault(); this.addRow(null, true, idx + 1); return; }

    // نافذة البحث: الأسهم للتنقل، Enter للاختيار، Esc للإغلاق
    var cc = this._col(el.dataset.col);
    if (cc && cc.type === 'lov' && !el.readOnly) {
      if (this._popOpen() && this._popEl === el) {
        if (e.key === 'ArrowDown') { e.preventDefault(); this._popMove(1); return; }
        if (e.key === 'ArrowUp')   { e.preventDefault(); this._popMove(-1); return; }
        if (e.key === 'Escape')    { e.preventDefault(); this._popHide(); return; }
        if (e.key === 'Enter' && !e.shiftKey && this._popIdx >= 0 && el.value.trim()) {
          e.preventDefault();
          var pr = this._popRes[this._popIdx];
          this._pick(el, pr.rec, pr.unit);
          return;
        }
      } else if (e.key === 'ArrowDown' || e.key === 'F9') { e.preventDefault(); this._popShow(el); return; }
    }
    if (e.key !== 'Enter' || e.shiftKey) return;

    // اعتماد قيمة الخلية قبل الانتقال
    var c = this._col(el.dataset.col);
    if (c && c.type === 'lov') {
      this._onInput(el, true);
      if (el.classList.contains('jl-err')) { e.preventDefault(); this._popShow(el); return; }   // غير موجود أو أكثر من نتيجة: نعرض البحث
      this._popHide();
    }

    // هل هذه آخر خلية قابلة للكتابة في آخر سطر؟
    var editable = Array.prototype.filter.call(
      tr.querySelectorAll('.jl-in'), function (x) { return !x.readOnly && !x.disabled; });
    var isLastCell = editable[editable.length - 1] === el,
        isLastRow  = idx === this.rows.length - 1;

    // Enter في أول خلية من آخر سطر وهو فارغ = الخروج من الجدول (إلى زر الحفظ مثلاً)
    if (isLastRow && editable[0] === el && !el.value && this._isEmpty(this.rows[idx]) && this.rows.length > 1) {
      e.preventDefault();
      window.EnterNav.nextAfter(this.$root);
      return;
    }

    if (isLastCell && isLastRow && !this.readOnly) {
      e.preventDefault();
      if (el.dataset.type !== 'lov') this._onInput(el, true);
      if (this._isEmpty(this.rows[idx])) {
        // سطر فارغ: نخرج من الجدول للحقل التالي بعده
        if (!window.EnterNav.nextAfter(this.$root)) el.blur();
      } else {
        this.addRow(null, true);
      }
    }
    // غير ذلك: enter_nav.js ينقل للحقل التالي
  };

  /* ---------------- عمليات السطور ---------------- */
  JsonLines.prototype._blank = function () {
    var r = {};
    this.cols.forEach(function (c) { r[c.name] = c.defaultValue != null ? c.defaultValue : null; });
    if (this.opts.newRow) this.opts.newRow(r, this);
    return r;
  };

  JsonLines.prototype._isEmpty = function (row) {
    var self = this;
    return this.cols.every(function (c) {
      if (c.type === 'display' || c.hidden || c.ignoreEmpty) return true;
      var v = row[c.name];
      // كود مكتوب لكنه غير موجود في القائمة: السطر ليس فارغاً (ليظهر خطأ "مطلوب")
      if (c.type === 'lov' && v == null && row[c.name + '$text']) return false;
      return v === null || v === undefined || v === '' || (c.defaultValue != null && v === c.defaultValue);
    });
  };

  JsonLines.prototype.addRow = function (data, focus, at) {
    var r = data || this._blank();
    if (at == null || at >= this.rows.length) { this.rows.push(r); at = this.rows.length - 1; }
    else this.rows.splice(at, 0, r);
    this.render();
    if (focus) this.focusRow(at);
    return r;
  };

  JsonLines.prototype.removeRow = function (idx, focus) {
    if (this.readOnly) return;
    this.rows.splice(idx, 1);
    if (!this.rows.length) this.rows.push(this._blank());
    this.render();
    if (focus) this.focusRow(Math.min(idx, this.rows.length - 1));
  };

  JsonLines.prototype.focusRow = function (idx) {
    var el = this.$tbody.querySelector('tr[data-idx="' + idx + '"] .jl-in:not([readonly]):not([disabled])');
    if (el) window.EnterNav ? window.EnterNav.focus(el) : el.focus();
  };

  JsonLines.prototype.setData = function (arr) {
    var self = this;
    this.rows = (arr || []).map(function (r) {
      var b = self._blank();
      Object.keys(r).forEach(function (k) { b[k.toUpperCase()] = r[k]; });
      return b;
    });
    if (!this.readOnly) this.rows.push(this._blank());
    if (!this.rows.length) this.rows.push(this._blank());
    this.render();
  };

  // السطور غير الفارغة فقط، مع رقم السطر - جاهزة لـ JSON.stringify
  JsonLines.prototype.getData = function () {
    var self = this, out = [], n = 0;
    this.rows.forEach(function (r) {
      if (self._isEmpty(r)) return;
      var o = {LINE_NO: ++n};
      self.cols.forEach(function (c) { if (!c.noSubmit) o[c.name] = r[c.name]; });
      out.push(o);
    });
    return out;
  };

  JsonLines.prototype.setReadOnly = function (ro) {
    this.readOnly = ro;
    this._build();
    this.setData(this.getData());
  };

  /* ---------------- الإجماليات والتحقق ---------------- */
  JsonLines.prototype.totals = function () {
    var t = {}, self = this;
    this.cols.forEach(function (c) {
      if (!c.total) return;
      t[c.name] = self.rows.reduce(function (s, r) { return s + (toNum(r[c.name]) || 0); }, 0);
    });
    return t;
  };

  JsonLines.prototype._totals = function () {
    var self = this, t = this.totals();
    Object.keys(t).forEach(function (k) {
      var td = self.$tfoot.querySelector('[data-total="' + k + '"]');
      if (td) td.textContent = fmt(t[k], self._col(k).decimals || 0);
    });
    if (this.opts.onTotals) this.opts.onTotals(t, this);
  };

  // يرجع مصفوفة رسائل خطأ (فارغة = سليم)
  JsonLines.prototype.validate = function () {
    var self = this, errs = [], n = 0;
    this.$tbody.querySelectorAll('.jl-err').forEach(function (x) { x.classList.remove('jl-err'); });
    this.rows.forEach(function (r, i) {
      if (self._isEmpty(r)) return;
      n++;
      self.cols.forEach(function (c) {
        if (!c.required) return;
        var v = r[c.name];
        if (v === null || v === undefined || v === '') {
          errs.push('السطر ' + (i + 1) + ': ' + c.label + ' مطلوب');
          var el = self.$tbody.querySelector('tr[data-idx="' + i + '"] [data-col="' + c.name + '"]');
          if (el) el.classList.add('jl-err');
        }
      });
      if (self.opts.validateRow) {
        var m = self.opts.validateRow(r, i, self);
        if (m) errs.push('السطر ' + (i + 1) + ': ' + m);
      }
    });
    if (!n) errs.push('أدخل سطراً واحداً على الأقل');
    return errs;
  };

  JsonLines.toNum = toNum;
  JsonLines.fmt   = fmt;
  window.JsonLines = JsonLines;
})();

/* =====================================================================
 * دوال مساعدة مشتركة للصفحات
 * ===================================================================== */
window.DocUtil = {
  // جلب سعر الصرف حسب العملة والتاريخ (Ajax Callback اسمه GET_RATE في الصفحة)
  loadRate: function (curItem, dateItem, rateItem) {
    var cur = apex.item(curItem).getValue();
    if (!cur) return;
    apex.server.process('GET_RATE', {x01: cur, x02: apex.item(dateItem).getValue()}, {dataType: 'json'})
      .done(function (d) { if (d.rate) apex.item(rateItem).setValue(d.rate); });
  },

  // قائمة الحسابات حسب طريقة الدفع (نقدي: الصناديق والبنوك ، آجل: العملاء / الموردون)
  // تُبنى خيارات القائمة في المتصفح دون إعادة تحميل الصفحة (Ajax Callback اسمه PAY_ACCOUNTS)
  payAccounts: function (payItem, accItem, kind, keepValue) {
    var sel = document.getElementById(accItem);
    if (!sel) return;
    var pay = apex.item(payItem).getValue() || 'CASH';
    var v = keepValue ? apex.item(accItem).getValue() : '';
    var lbl = document.querySelector('label[for="' + accItem + '"]');
    if (lbl) lbl.textContent = pay === 'CASH' ? 'الصندوق / الحساب البنكي' : (kind === 'PURCHASE' ? 'حساب المورد' : 'حساب العميل');
    return apex.server.process('PAY_ACCOUNTS', {x01: pay, x02: kind}, {dataType: 'json'}).done(function (list) {
      var esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); };
      sel.innerHTML = '<option value="">- اختر -</option>' + list.map(function (o) {
        return '<option value="' + esc(o.v) + '">' + esc(o.t) + '</option>';
      }).join('');
      sel.value = list.some(function (o) { return String(o.v) === String(v); }) ? v : '';
    });
  },

  showErrors: function (errs) {
    apex.message.clearErrors();
    apex.message.showErrors(errs.map(function (m) {
      return {type: 'error', location: 'page', message: m, unsafe: false};
    }));
  },

  // إرسال المستند كـ JSON إلى Ajax Callback (افتراضياً SAVE_DOC)
  save: function (doc, action, onOk, processName) {
    apex.message.clearErrors();
    var spinner = apex.util.showSpinner();
    return apex.server.process(processName || 'SAVE_DOC',
        {x01: action, p_clob_01: JSON.stringify(doc)}, {dataType: 'json'})
      .done(function (d) {
        if (d.ok) {
          apex.message.showPageSuccess(d.message || 'تم الحفظ');
          if (onOk) onOk(d);
        } else {
          DocUtil.showErrors(d.errors || ['خطأ غير معروف']);
        }
      })
      .fail(function (x) { DocUtil.showErrors(['خطأ في الاتصال: ' + (x.responseText || x.statusText).substring(0, 300)]); })
      .always(function () { spinner.remove(); });
  }
};
