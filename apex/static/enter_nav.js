/* =====================================================================
 * enter_nav.js  -  التنقل بين الحقول بمفتاح ENTER في كل صفحات التطبيق
 *   Enter          : الحقل التالي
 *   Shift + Enter  : الحقل السابق (وفي حقول النص المتعدد: سطر جديد)
 *   الحقل الذي عليه data-no-enter أو class="no-enter" لا يتأثر.
 *   الأزرار التي تحمل class="js-enter" تدخل في التنقل (مثل زر الحفظ).
 * يُضاف في: Shared Components > User Interface > JavaScript File URLs
 *          #APP_FILES#enter_nav#MIN#.js
 * ===================================================================== */
(function () {
  "use strict";

  var FIELDS = [
    'input:not([type=hidden]):not([type=button]):not([type=submit]):not([type=reset]):not([type=file])',
    'select', 'textarea', 'button.js-enter'
  ].join(',');

  function isUsable(el) {
    if (el.disabled || el.readOnly) return false;
    if (el.tabIndex < 0) return false;
    if (el.closest('[data-no-enter], .no-enter')) return false;
    // ظاهر على الشاشة
    if (!(el.offsetWidth || el.offsetHeight || el.getClientRects().length)) return false;
    var st = window.getComputedStyle(el);
    return st.visibility !== 'hidden' && st.display !== 'none';
  }

  function scopeOf(el) {
    // داخل نافذة حوار (Modal) نتنقل داخلها فقط
    return el.closest('.ui-dialog-content, .t-Dialog-page, form') || document.body;
  }

  function fieldsIn(scope) {
    return Array.prototype.filter.call(scope.querySelectorAll(FIELDS), isUsable);
  }

  function focusField(el) {
    if (!el) return;
    el.focus();
    if (el.select && (el.type === 'text' || el.type === 'number' || el.type === 'search' ||
                      el.type === 'tel' || el.inputMode === 'decimal')) {
      try { el.select(); } catch (e) { /* بعض الأنواع لا تدعم select */ }
    }
  }

  function move(from, step) {
    var list = fieldsIn(scopeOf(from)),
        i = list.indexOf(from);
    if (i < 0) return false;
    var target = list[i + step];
    if (target) { focusField(target); return true; }
    return false;
  }

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.defaultPrevented || e.isComposing) return;
    if (e.ctrlKey || e.altKey || e.metaKey) return;

    var el = e.target;
    if (!el.matches || !el.matches(FIELDS)) return;
    if (el.closest('[data-no-enter], .no-enter')) return;
    // لا نتدخل في نوافذ Popup LOV الخاصة بـ APEX
    if (el.closest('.a-PopupLOV-dialog, .a-PopupLOV-searchBar')) return;
    // الأزرار: Enter يضغط الزر طبيعياً
    if (el.tagName === 'BUTTON') return;
    // النص المتعدد: Shift+Enter = سطر جديد
    if (el.tagName === 'TEXTAREA' && e.shiftKey) return;

    // آخر حقل في النموذج (مثل كلمة المرور في صفحة الدخول): نترك Enter يعمل طبيعياً (إرسال)
    if (move(el, e.shiftKey ? -1 : 1)) e.preventDefault();
  }, false);

  // واجهة عامة تستخدمها شاشات JSON
  window.EnterNav = {
    next:  function (el) { return move(el, 1); },
    // أول حقل يأتي بعد عنصر معيّن (مثل جدول السطور) في ترتيب الصفحة
    nextAfter: function (el) {
      var list = fieldsIn(scopeOf(el));
      for (var i = 0; i < list.length; i++) {
        if (!el.contains(list[i]) &&
            (el.compareDocumentPosition(list[i]) & Node.DOCUMENT_POSITION_FOLLOWING)) {
          focusField(list[i]); return true;
        }
      }
      return false;
    },
    prev:  function (el) { return move(el, -1); },
    focus: focusField,
    first: function (scope) {
      var list = fieldsIn(typeof scope === 'string' ? document.querySelector(scope) : (scope || document.body));
      focusField(list[0]);
    }
  };
})();
