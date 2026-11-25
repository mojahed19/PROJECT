# =====================================================================
#  pages_master.pl - الصفحة العامة 0، شجرة الحسابات 10، وصفحات البيانات الأساسية (قائمة + نموذج)
# =====================================================================
use strict;
use warnings;
use utf8;
our %LOV;
our %T;

# ---------------------------------------------------------------- 0 الصفحة العامة
page(id => 0, name => 'Global Page', alias => 'GLOBAL');
# رأس يظهر عند طباعة أي صفحة أو تقرير: الشعار واسم الشركة وبياناتها
region(name => 'print_head', title => 'print', type => 'static', no_header => 1, template => 'reg_blank', seq => 1,
       cond => ":APP_PAGE_ID NOT IN (53, 54, 57, 82, 9999)", html => <<'HTML');
<div class="print-only-head">
  <img src="#APP_FILES#logo.jpg" alt="">
  <div><div class="nm">&G_COMPANY_NAME.</div><div class="inf">&G_COMPANY_INFO.</div></div>
</div>
HTML
end_page();

# ---------------------------------------------------------------- مولّد القائمة + النموذج
# cols: [COLUMN, label, type, lov, required, dtype]
sub crud {
  my %c = @_;
  my ($L, $F, $tbl) = ($c{list}, $c{form}, $c{table});
  my @cols = @{ $c{cols} };

  # ---------- صفحة القائمة
  my @sel = ('t.ROWID');
  for my $col (@cols) {
    my ($name, $label, $type, $lov) = @$col;
    if ($lov && ($type eq 'select' || $type eq 'popup')) {
      push @sel, "(SELECT x.d FROM ($lov) x WHERE x.r = t.$name AND ROWNUM = 1) AS \"$label\"";
    } elsif (($type // '') eq 'date') {
      push @sel, "TO_CHAR(t.$name, 'DD/MM/YYYY') AS \"$label\"";
    } else {
      push @sel, "t.$name AS \"$label\"";
    }
  }
  my $sql = "SELECT " . join(",\n       ", @sel) . "\nFROM $tbl t" . ($c{where} ? "\nWHERE $c{where}" : '') . ($c{order} ? "\nORDER BY $c{order}" : '');
  page(id => $L, name => $c{title}, alias => $c{alias}, auth => $c{auth},
       onload => "apex.jQuery(window).on('apexafterclosedialog', function () { location.reload(); });");
  region(name => 'ir', title => $c{title}, type => 'ir', sql => $sql, pk => 'ROWID',
         detail_link => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:RP:P${F}_ROWID:\\#ROWID#\\");
  button(name => 'CREATE', region => 'ir', label => 'إضافة', hot => 1, position => 'RIGHT_OF_IR_SEARCH_BAR',
         url => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:$F\::");
  end_page();

  # ---------- صفحة النموذج (Modal، أو صفحة كاملة عند full => 1)
  my $fsql = "SELECT ROWID, " . join(', ', map { $_->[0] } @cols) . " FROM $tbl";
  my $modal = !$c{full};
  page(id => $F, name => $c{title}, alias => "$c{alias}-FORM", modal => $modal, auth => $c{auth}, ($c{form_js} ? (js => $c{form_js}) : ()), ($c{form_onload} ? (onload => $c{form_onload}) : ()));
  region(name => 'form', title => $c{title}, type => 'form', sql => $fsql, seq => 10);
  region(name => 'buttons', title => 'Buttons', type => 'static', html => '', template => 'reg_buttons', seq => 20, ($modal ? (position => 'REGION_POSITION_03') : ()));
  item(name => "P${F}_ROWID", region => 'form', type => 'hidden', col => 'ROWID', dtype => 'ROWID', pk => 1, query_only => 1, protected => 1, seq => 1);
  my $seq = 10;
  for my $col (@cols) {
    my ($name, $label, $type, $lov, $req, $dtype, $o) = @$col;
    $o //= {};
    $type //= 'text';
    $dtype //= $type eq 'date' ? 'DATE' : $type eq 'num' ? 'NUMBER' : 'VARCHAR2';
    item(name => "P${F}_$name", region => 'form', col => $name, dtype => $dtype, label => $label,
         type => $type eq 'num' ? 'text' : $type, lov => $lov, null => $o->{null} // (($type eq 'select' && !$req) ? 1 : undef),
         required => $req, seq => ($seq += 10), same_line => $o->{same_line}, span => $o->{span}, readonly => $o->{readonly});
  }
  button(name => 'CANCEL', region => 'buttons', label => $modal ? 'إلغاء' : 'رجوع للقائمة', position => 'CLOSE', seq => 10,
         ($modal ? (js => 'apex.navigation.dialog.cancel(true);') : (url => "f?p=&APP_ID.:$L:&APP_SESSION.::&DEBUG.:::")));
  button(name => 'NEW', region => 'buttons', label => 'جديد', position => 'CLOSE', seq => 15, url => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:$F::") if !$modal;
  button(name => 'DELETE', region => 'buttons', label => 'حذف', position => 'DELETE', seq => 20, dml => 'DELETE',
         if_not_null => "P${F}_ROWID", novalidate => 1, confirm => '&APP_TEXT$DELETE_MSG!RAW.');
  button(name => 'SAVE', region => 'buttons', label => 'حفظ التعديلات', position => 'NEXT', seq => 30, hot => 1, dml => 'UPDATE', if_not_null => "P${F}_ROWID");
  button(name => 'CREATE', region => 'buttons', label => 'حفظ', position => 'NEXT', seq => 40, hot => 1, dml => 'INSERT', if_null => "P${F}_ROWID");
  process(name => 'Init form', point => 'BEFORE_HEADER', kind => 'form_init', region => 'form');
  process(name => 'Process form', seq => 10, kind => 'form_dml', region => 'form');
  if ($modal) {
    process(name => 'Close Dialog', seq => 20, kind => 'close', when_req => 'CREATE,SAVE,DELETE');
  } else {
    # صفحة كاملة: بعد الإضافة تبقى الصفحة فارغة للصنف التالي، وبعد التعديل أو الحذف رجوع للقائمة
    branch_to(seq => 10, when_req => 'CREATE', url => "f?p=&APP_ID.:$F:&SESSION.::&DEBUG.:$F::&success_msg=#SUCCESS_MSG#");
    branch_to(seq => 20, when_req => 'SAVE,DELETE', url => "f?p=&APP_ID.:$L:&SESSION.::&DEBUG.:::&success_msg=#SUCCESS_MSG#");
  }
  $c{extra}->($F) if $c{extra};
  end_page();
}

my $yn       = $LOV{yn};
my $units    = "SELECT name_ar d, unit_id r FROM units ORDER BY name_ar";
my $items    = "SELECT item_code || ' - ' || name_ar d, item_id r FROM items ORDER BY item_code";
my $pls      = "SELECT name_ar || ' (' || currency_code || ')' d, price_list_id r FROM price_lists ORDER BY name_ar";
my $grades   = "SELECT grade_code || ' - ' || name_ar d, grade_id r FROM job_grades ORDER BY grade_code";
my $emps     = "SELECT emp_no || ' - ' || name_ar d, employee_id r FROM employees ORDER BY emp_no";
my $allows   = "SELECT name_ar d, allowance_id r FROM allowance_types ORDER BY name_ar";
my $users    = "SELECT full_name || ' (' || user_name || ')' d, user_name r FROM app_users ORDER BY full_name";
my $whs      = "SELECT c.name_ar || ' / ' || w.name_ar d, w.warehouse_id r FROM warehouses w JOIN companies c ON c.company_id = w.company_id ORDER BY c.company_code, w.name_ar";
my $roles    = "SELECT 'مدير النظام' d, 'ADMIN' r FROM dual UNION ALL SELECT 'مدخل', 'ENTRY' FROM dual UNION ALL SELECT 'مراجع', 'REVIEWER' FROM dual UNION ALL SELECT 'معتمد', 'APPROVER' FROM dual";
my $settings = "SELECT code || ' - ' || n d, code r FROM (SELECT 'SALES_EXT' code, 'مبيعات للعملاء' n FROM dual UNION ALL SELECT 'SALES', 'مبيعات للشركات' FROM dual UNION ALL SELECT 'SALES_RETURN', 'مردودات المبيعات' FROM dual UNION ALL SELECT 'INTERCO_AP', 'مستحق للشركة الأم' FROM dual UNION ALL SELECT 'PURCHASES', 'وارد من الأم (مخزون)' FROM dual UNION ALL SELECT 'INVENTORY', 'المخزون' FROM dual UNION ALL SELECT 'COGS', 'تكلفة المبيعات' FROM dual UNION ALL SELECT 'INVENTORY_ADJ', 'فروقات الجرد' FROM dual UNION ALL SELECT 'POS_SALES', 'مبيعات نقاط البيع' FROM dual UNION ALL SELECT 'CASH_DIFF', 'عجز وزيادة الخزائن' FROM dual UNION ALL SELECT 'SALARY_EXP', 'مصروف الرواتب' FROM dual UNION ALL SELECT 'INCENTIVE_EXP', 'مصروف الحوافز' FROM dual UNION ALL SELECT 'SALARY_DIFF', 'فروقات الرواتب' FROM dual UNION ALL SELECT 'SALARY_PAYABLE', 'رواتب مستحقة' FROM dual UNION ALL SELECT 'DEDUCTIONS', 'خصومات الموظفين' FROM dual UNION ALL SELECT 'CHEQUES_IN', 'شيكات تحت التحصيل' FROM dual UNION ALL SELECT 'CHEQUES_OUT', 'شيكات تحت الصرف' FROM dual)";

crud(list => 204, form => 205, title => 'السنوات المالية', table => 'fiscal_years', alias => 'FISCAL', auth => 'IS_GM', order => 't.fy_year DESC', cols => [
  ['FY_YEAR', 'السنة', 'num', undef, 1], ['START_DATE', 'البداية', 'date', undef, 1], ['END_DATE', 'النهاية', 'date', undef, 1],
  ['IS_CLOSED', 'مغلقة', 'select', $yn, 1]]);

crud(list => 206, form => 207, title => 'المستخدمون', table => 'app_users', alias => 'USERS', auth => 'IS_GM', order => 't.user_name', cols => [
  ['USER_NAME', 'اسم الدخول (بأحرف كبيرة)', 'text', undef, 1], ['FULL_NAME', 'الاسم', 'text', undef, 1],
  ['USER_ROLE', 'الدور', 'select', $roles, 1],
  ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]],
  # كلمة المرور: حقل خارج الجدول، تُحفظ مُجزّأة (SHA256) بعد الحفظ
  extra => sub {
    my $F = shift;
    item(name => "P${F}_NEW_PASSWORD", region => 'form', type => 'password', seq => 200,
         label => 'كلمة المرور (اتركها فارغة لعدم التغيير)');
    item(name => "P${F}_CONFIRM_PASSWORD", region => 'form', type => 'password', seq => 210, same_line => 1,
         label => 'تأكيد كلمة المرور');
    process(name => 'CHECK_PASSWORD', seq => 1, when_req => 'CREATE,SAVE', code => <<"SQL");
DECLARE l_err VARCHAR2(200);
BEGIN
  l_err := CASE
  WHEN :P${F}_ROWID IS NULL AND :P${F}_NEW_PASSWORD IS NULL THEN 'أدخل كلمة المرور للمستخدم الجديد'
  WHEN :P${F}_NEW_PASSWORD IS NOT NULL AND LENGTH(:P${F}_NEW_PASSWORD) < 6 THEN 'كلمة المرور 6 أحرف على الأقل'
  WHEN NVL(:P${F}_NEW_PASSWORD, '#') <> NVL(:P${F}_CONFIRM_PASSWORD, '#') THEN 'كلمة المرور وتأكيدها غير متطابقين'
  END;
  IF l_err IS NOT NULL THEN raise_application_error(-20001, l_err); END IF;
END;
SQL
    process(name => 'UPPER_USER', seq => 5, when_req => 'CREATE,SAVE',
            code => "BEGIN\n  IF apex_error.have_errors_occurred THEN RETURN; END IF;\n  :P${F}_USER_NAME := UPPER(TRIM(:P${F}_USER_NAME));\nEND;");
    process(name => 'SET_PASSWORD', seq => 15, when_req => 'CREATE,SAVE', code => <<"SQL");
BEGIN
  IF apex_error.have_errors_occurred OR :P${F}_NEW_PASSWORD IS NULL THEN RETURN; END IF;
  UPDATE app_users
  SET    password_hash = (SELECT RAWTOHEX(STANDARD_HASH(UPPER(TRIM(:P${F}_USER_NAME)) || ':' || :P${F}_NEW_PASSWORD, 'SHA256')) FROM dual)
  WHERE  user_name = UPPER(TRIM(:P${F}_USER_NAME));
  :P${F}_NEW_PASSWORD := NULL;
  :P${F}_CONFIRM_PASSWORD := NULL;
END;
SQL
  });

crud(list => 208, form => 209, title => 'الحسابات الافتراضية', table => 'account_settings', alias => 'ACC-SETTINGS', auth => 'IS_GM', order => 't.setting_code', where => 't.company_id = :G_PARENT_ID', cols => [
  ['SETTING_CODE', 'الإعداد', 'select', $settings, 1],
  ['ACCOUNT_ID', 'الحساب', 'popup', $LOV{accounts4}, 1, 'NUMBER']]);

crud(list => 212, form => 213, title => 'الوحدات', table => 'units', alias => 'UNITS', auth => 'IS_STORE', order => 't.name_ar', cols => [
  ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي']]);

# الأصناف: صفحة كاملة (ليست نافذة). الكود متسلسل تلقائي، وسعر الوحدة الصغرى = سعر الكبرى ÷ ما تعادله (لأقرب خانتين)
#   السطر 1: الكود ، الاسم ، الاسم الإنجليزي ، الباركود
#   السطر 2: الوحدة الكبرى ، ما تعادله من الصغرى ، الوحدة الصغرى (يمكن أن تكون نفس الكبرى وتعادل 1)
#   السطر 3: سعر شراء الكبرى ، سعر شراء الصغرى (تلقائي)
#   السطر 4: سعر بيع الكبرى ، سعر بيع الصغرى (تلقائي)
#   السطر 5: تاريخ الصلاحية ، حد الطلب ، فعّال
my $item_js = <<'JS';
var itm = {
  num: function (n) {
    var v = String(apex.item(n).getValue() || '').replace(/,/g, '').trim();
    return v === '' || isNaN(v) ? null : Number(v);
  },
  // الوحدة الصغرى = الكبرى ← تعادل 1 ، ثم أسعار الصغرى = الكبرى ÷ التعادل
  calc: function () {
    var big = apex.item('P211_BIG_UNIT_ID').getValue(), small = apex.item('P211_BASE_UNIT_ID').getValue();
    if (big && small && big === small && itm.num('P211_BIG_FACTOR') !== 1) apex.item('P211_BIG_FACTOR').setValue('1');
    var f = itm.num('P211_BIG_FACTOR');
    [['P211_BIG_PURCHASE_PRICE', 'P211_PURCHASE_PRICE'], ['P211_BIG_SALE_PRICE', 'P211_SALE_PRICE']].forEach(function (p) {
      var b = itm.num(p[0]);
      apex.item(p[1]).setValue(b !== null && f > 0 ? (Math.round((b / f + 1e-9) * 100) / 100).toFixed(2) : '');
    });
  },
  init: function () {
    apex.jQuery('#P211_BIG_UNIT_ID, #P211_BASE_UNIT_ID, #P211_BIG_FACTOR, #P211_BIG_PURCHASE_PRICE, #P211_BIG_SALE_PRICE')
      .on('change input', itm.calc);
    itm.calc();
    var n = document.getElementById('P211_NAME_AR');
    if (n && window.EnterNav) EnterNav.focus(n);
  }
};
JS

crud(list => 210, form => 211, title => 'الأصناف وأسعارها', table => 'items', alias => 'ITEMS', auth => 'IS_STORE', order => 't.item_code',
  full => 1, form_js => $item_js, form_onload => 'itm.init();', cols => [
  ['ITEM_CODE', 'الكود', 'text', undef, 1, undef, {span => 2, readonly => 1}],
  ['NAME_AR', 'الاسم', 'text', undef, 1, undef, {span => 4, same_line => 1}],
  ['NAME_EN', 'الاسم الإنجليزي', 'text', undef, undef, undef, {span => 3, same_line => 1}],
  ['BARCODE', 'الباركود', 'text', undef, undef, undef, {span => 3, same_line => 1}],
  ['BIG_UNIT_ID', 'الوحدة الكبرى', 'select', $units, 1, 'NUMBER', {span => 4, null => '- اختر -'}],
  ['BIG_FACTOR', 'ما تعادله من الوحدة الصغرى', 'num', undef, 1, undef, {span => 4, same_line => 1}],
  ['BASE_UNIT_ID', 'الوحدة الصغرى', 'select', $units, 1, 'NUMBER', {span => 4, same_line => 1, null => '- اختر -'}],
  ['BIG_PURCHASE_PRICE', 'سعر الشراء للوحدة الكبرى', 'num', undef, 1, undef, {span => 6}],
  ['PURCHASE_PRICE', 'سعر الشراء للوحدة الصغرى (تلقائي)', 'num', undef, undef, undef, {span => 6, same_line => 1, readonly => 1}],
  ['BIG_SALE_PRICE', 'سعر البيع للوحدة الكبرى', 'num', undef, 1, undef, {span => 6}],
  ['SALE_PRICE', 'سعر البيع للوحدة الصغرى (تلقائي)', 'num', undef, undef, undef, {span => 6, same_line => 1, readonly => 1}],
  ['EXPIRY_DATE', 'تاريخ الصلاحية', 'date', undef, undef, undef, {span => 4}],
  ['REORDER_LEVEL', 'حد الطلب', 'num', undef, undef, undef, {span => 4, same_line => 1}],
  ['IS_ACTIVE', 'فعّال', 'checkbox', undef, undef, undef, {span => 4, same_line => 1}]],
  extra => sub {
    my $F = shift;
    # صنف جديد: الكود التالي في التسلسل ، وفعّال افتراضياً
    process(name => 'NEW_DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ":P${F}_ROWID IS NULL", code => <<"SQL");
BEGIN
  SELECT TO_CHAR(NVL(MAX(TO_NUMBER(item_code DEFAULT NULL ON CONVERSION ERROR)), 0) + 1) INTO :P${F}_ITEM_CODE FROM items;
  :P${F}_IS_ACTIVE := NVL(:P${F}_IS_ACTIVE, 'Y');
END;
SQL
    check(name => 'CHECK_UNITS', seq => 5, when_req => 'CREATE,SAVE', code => <<"SQL");
DECLARE
  FUNCTION n (p VARCHAR2) RETURN NUMBER IS BEGIN RETURN TO_NUMBER(REPLACE(p, ',')); EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
BEGIN
RETURN CASE
  WHEN NVL(n(:P${F}_BIG_FACTOR), 0) <= 0 THEN 'أدخل ما تعادله الوحدة الكبرى من الوحدات الصغرى'
  WHEN :P${F}_BIG_UNIT_ID = :P${F}_BASE_UNIT_ID AND n(:P${F}_BIG_FACTOR) <> 1 THEN 'الوحدة الكبرى هي نفسها الصغرى: ما تعادله يجب أن يكون 1'
  WHEN :P${F}_BIG_UNIT_ID <> :P${F}_BASE_UNIT_ID AND n(:P${F}_BIG_FACTOR) <= 1 THEN 'الوحدة الكبرى تعادل أكثر من وحدة صغرى واحدة'
  WHEN NVL(n(:P${F}_BIG_PURCHASE_PRICE), 0) <= 0 THEN 'أدخل سعر الشراء للوحدة الكبرى'
  WHEN NVL(n(:P${F}_BIG_SALE_PRICE), 0) <= 0 THEN 'أدخل سعر البيع للوحدة الكبرى'
END;
END;
SQL
    # قبل الحفظ: الكود التالي فعلياً (لو أضاف مستخدم آخر صنفاً في نفس الوقت) ، وأسعار الصغرى تُحسب في الخادم
    process(name => 'PREPARE', seq => 7, when_req => 'CREATE,SAVE', code => <<"SQL");
BEGIN
  IF :REQUEST = 'CREATE' THEN
    SELECT TO_CHAR(NVL(MAX(TO_NUMBER(item_code DEFAULT NULL ON CONVERSION ERROR)), 0) + 1) INTO :P${F}_ITEM_CODE FROM items;
  END IF;
  :P${F}_PURCHASE_PRICE := TO_CHAR(ROUND(TO_NUMBER(REPLACE(:P${F}_BIG_PURCHASE_PRICE, ',')) / TO_NUMBER(REPLACE(:P${F}_BIG_FACTOR, ',')), 2));
  :P${F}_SALE_PRICE     := TO_CHAR(ROUND(TO_NUMBER(REPLACE(:P${F}_BIG_SALE_PRICE, ','))     / TO_NUMBER(REPLACE(:P${F}_BIG_FACTOR, ',')), 2));
  :P${F}_IS_ACTIVE      := NVL(:P${F}_IS_ACTIVE, 'N');
END;
SQL
    process(name => 'SYNC_UNITS', seq => 15, when_req => 'CREATE,SAVE', success => 'تم حفظ الصنف &P211_ITEM_CODE.', code => <<"SQL");
DECLARE
  l_id NUMBER;
BEGIN
  SELECT item_id INTO l_id FROM items WHERE item_code = :P${F}_ITEM_CODE;
  MERGE INTO item_units u
  USING (SELECT item_id, base_unit_id unit_id, 1 factor FROM items WHERE item_id = l_id
         UNION ALL
         SELECT item_id, big_unit_id, big_factor FROM items WHERE item_id = l_id AND big_unit_id <> base_unit_id AND big_factor > 1) s
  ON (u.item_id = s.item_id AND u.unit_id = s.unit_id)
  WHEN MATCHED THEN UPDATE SET u.factor = s.factor
  WHEN NOT MATCHED THEN INSERT (item_id, unit_id, factor) VALUES (s.item_id, s.unit_id, s.factor);
END;
SQL
  });

crud(list => 236, form => 237, title => 'وحدات الأصناف', table => 'item_units', alias => 'ITEM-UNITS', auth => 'IS_STORE', order => 't.item_id, t.factor', cols => [
  ['ITEM_ID', 'الصنف', 'popup', $items, 1, 'NUMBER'], ['UNIT_ID', 'الوحدة', 'select', $units, 1, 'NUMBER'],
  ['FACTOR', 'عدد الوحدات الأساسية', 'num', undef, 1], ['BARCODE', 'الباركود']]);

crud(list => 214, form => 215, title => 'قوائم الأسعار', table => 'price_lists', alias => 'PRICE-LISTS', auth => 'IS_GM', order => 't.name_ar', cols => [
  ['NAME_AR', 'الاسم', 'text', undef, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 234, form => 235, title => 'أسعار الأصناف', table => 'price_list_items', alias => 'PRICES', auth => 'IS_GM', order => 't.price_list_id, t.item_id', cols => [
  ['PRICE_LIST_ID', 'قائمة الأسعار', 'select', $pls, 1, 'NUMBER'], ['ITEM_ID', 'الصنف', 'popup', $items, 1, 'NUMBER'],
  ['UNIT_ID', 'الوحدة', 'select', $units, 1, 'NUMBER'], ['PRICE', 'السعر', 'num', undef, 1]]);

crud(list => 216, form => 217, title => 'المخازن', table => 'warehouses', alias => 'WAREHOUSES', auth => 'IS_STORE', order => 't.company_id', cols => [
  ['NAME_AR', 'الاسم', 'text', undef, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 220, form => 221, title => 'الدرجات الوظيفية', table => 'job_grades', alias => 'GRADES', auth => 'IS_HR', order => 't.grade_code', cols => [
  ['GRADE_CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['BASIC_SALARY', 'الراتب الأساسي', 'num', undef, 1]]);

my $emp_types = "SELECT 'موظف' d, 'EMPLOYEE' r FROM dual UNION ALL SELECT 'عامل', 'WORKER' FROM dual UNION ALL SELECT 'عسكري', 'SOLDIER' FROM dual UNION ALL SELECT 'ضابط', 'OFFICER' FROM dual";
my $ranks = "SELECT DECODE(rank_type, 'SOLDIER', 'عسكري', 'ضابط') || ' - ' || name_ar d, rank_id r FROM military_ranks ORDER BY rank_type DESC, sort_order";
crud(list => 222, form => 223, title => 'الموظفون', table => 'employees', alias => 'EMPLOYEES', auth => 'IS_HR', order => 't.emp_no', cols => [
  ['EMP_NO', 'الرقم', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1],
  ['EMP_TYPE', 'النوع', 'select', $emp_types, 1], ['RANK_ID', 'الرتبة (للعسكري والضابط)', 'select', $ranks, undef, 'NUMBER'],
  ['GRADE_ID', 'الدرجة', 'select', $grades, 1, 'NUMBER'],
  ['HIRE_DATE', 'تاريخ التعيين', 'date'], ['BASIC_SALARY', 'أساسي خاص (فارغ = أساسي الدرجة)', 'num'],
  ['BANK_ACCOUNT', 'الحساب البنكي'], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]],
  extra => sub {
    my $F = shift;
    check(name => 'CHECK_RANK', seq => 5, when_req => 'CREATE,SAVE', code => <<"SQL");
DECLARE l_type VARCHAR2(10);
BEGIN
  IF :P${F}_EMP_TYPE IN ('SOLDIER','OFFICER') THEN
    IF :P${F}_RANK_ID IS NULL THEN RETURN 'اختر الرتبة للعسكري أو الضابط'; END IF;
    SELECT rank_type INTO l_type FROM military_ranks WHERE rank_id = :P${F}_RANK_ID;
    IF l_type <> :P${F}_EMP_TYPE THEN RETURN 'الرتبة لا تناسب نوع الموظف (رتب العسكريين غير رتب الضباط)'; END IF;
  ELSIF :P${F}_RANK_ID IS NOT NULL THEN
    RETURN 'الرتبة للعسكري والضابط فقط';
  END IF;
  RETURN NULL;
END;
SQL
  });

crud(list => 230, form => 231, title => 'الرتب العسكرية', table => 'military_ranks', alias => 'RANKS', auth => 'IS_HR', order => 't.rank_type DESC, t.sort_order', cols => [
  ['RANK_TYPE', 'النوع', 'select', "SELECT 'عسكري' d, 'SOLDIER' r FROM dual UNION ALL SELECT 'ضابط', 'OFFICER' FROM dual", 1],
  ['NAME_AR', 'الرتبة', 'text', undef, 1], ['SORT_ORDER', 'الترتيب', 'num', undef, 1]]);

crud(list => 224, form => 225, title => 'بنود العلاوات والحوافز والخصومات', table => 'allowance_types', alias => 'ALLOWANCES', auth => 'IS_HR', order => 't.code', cols => [
  ['CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1],
  ['KIND', 'النوع', 'select', "SELECT 'علاوة' d, 'ALLOWANCE' r FROM dual UNION ALL SELECT 'حافز', 'INCENTIVE' FROM dual UNION ALL SELECT 'خصم', 'DEDUCTION' FROM dual", 1],
  ['CALC_METHOD', 'طريقة الحساب', 'select', "SELECT 'مبلغ ثابت' d, 'FIXED' r FROM dual UNION ALL SELECT 'نسبة من الأساسي', 'PERCENT' FROM dual", 1],
  ['ACCOUNT_ID', 'الحساب (اختياري)', 'popup', $LOV{accounts4}, undef, 'NUMBER']]);

crud(list => 226, form => 227, title => 'علاوات الدرجات', table => 'grade_allowances', alias => 'GRADE-ALLOW', auth => 'IS_HR', order => 't.grade_id', cols => [
  ['GRADE_ID', 'الدرجة', 'select', $grades, 1, 'NUMBER'], ['ALLOWANCE_ID', 'البند', 'select', $allows, 1, 'NUMBER'], ['VALUE', 'القيمة', 'num', undef, 1]]);

crud(list => 228, form => 229, title => 'علاوات الموظفين الخاصة', table => 'emp_allowances', alias => 'EMP-ALLOW', auth => 'IS_HR', order => 't.employee_id', cols => [
  ['EMPLOYEE_ID', 'الموظف', 'popup', $emps, 1, 'NUMBER'], ['ALLOWANCE_ID', 'البند', 'select', $allows, 1, 'NUMBER'],
  ['VALUE', 'القيمة', 'num', undef, 1], ['FROM_DATE', 'من تاريخ', 'date'], ['TO_DATE', 'إلى تاريخ', 'date']]);

crud(list => 20, form => 21, title => 'أنواع القيود', table => 'journal_types', alias => 'JOURNAL-TYPES', auth => 'IS_ACCOUNTANT', order => 't.sort_order', cols => [
  ['JT_CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي'],
  ['PREFIX', 'البادئة', 'text', undef, 1], ['MANUAL_ALLOWED', 'يُدخل يدوياً', 'select', $yn, 1],
  ['IS_ACTIVE', 'فعّال', 'select', $yn, 1], ['SORT_ORDER', 'الترتيب', 'num']]);

# =====================================================================
# 10 شجرة الحسابات
# =====================================================================
# شجرة منزلقة: + يفتح فروع الحساب ، − يطويه مع كل فروعه ، وأزرار لتوسيع / طي الشجرة كلها
# تفتح تلقائياً على مسار الحساب المختار (أو الحساب الأب عند إضافة حساب فرعي) ، وباقي الشجرة مطوية
my $tree = <<'PLSQL';
DECLARE
  TYPE t_b IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
  st    t_b;
  top   PLS_INTEGER := 0;
  l_lbl VARCHAR2(4000);
  l_open BOOLEAN;
  TYPE t_set IS TABLE OF BOOLEAN INDEX BY VARCHAR2(40);
  on_path t_set;                       -- الحسابات على مسار الحساب المختار (تُفتح)
  PROCEDURE pop IS
  BEGIN
    IF st(top) THEN htp.p('</ul></li>'); ELSE htp.p('</li>'); END IF;
    top := top - 1;
  END;
BEGIN
  FOR p IN (SELECT account_id FROM accounts
            START WITH account_id = TO_NUMBER(NVL(:P10_ACCOUNT_ID, :P10_PARENT_ID))
            CONNECT BY PRIOR parent_id = account_id) LOOP
    on_path(TO_CHAR(p.account_id)) := TRUE;
  END LOOP;
  htp.p('<div class="acc-tree-tools">'
     || '<button type="button" class="t-Button t-Button--small" data-tree="open"><span class="tg-ic">+</span> توسيع الكل</button> '
     || '<button type="button" class="t-Button t-Button--small" data-tree="close"><span class="tg-ic">&minus;</span> طي الكل</button></div>');
  htp.p('<ul class="acc-tree">');
  FOR r IN (SELECT LEVEL lvl, a.account_id, a.account_code, a.name_ar, a.is_active, CONNECT_BY_ISLEAF leaf
            FROM accounts a
            START WITH a.parent_id IS NULL
            CONNECT BY PRIOR a.account_id = a.parent_id
            ORDER SIBLINGS BY a.account_code) LOOP
    WHILE top >= r.lvl LOOP pop; END LOOP;
    top := top + 1;
    st(top) := (r.leaf = 0);
    l_lbl := '<a href="' || apex_page.get_url(p_page => 10, p_items => 'P10_ACCOUNT_ID', p_values => r.account_id) || '"'
          || CASE WHEN TO_CHAR(r.account_id) = :P10_ACCOUNT_ID THEN ' class="sel"' END
          || CASE WHEN r.is_active = 'N' THEN ' style="opacity:.5"' END || '>'
          || '<span class="fa ' || CASE WHEN r.leaf = 1 THEN 'fa-file-text-o' ELSE 'fa-folder-o' END || '"></span> '
          || apex_escape.html(r.account_code || ' - ' || r.name_ar) || '</a>';
    IF r.leaf = 0 THEN
      l_open := on_path.EXISTS(TO_CHAR(r.account_id));
      htp.p('<li class="nd' || CASE WHEN l_open THEN ' open' END || '"><span class="tg" role="button" title="فتح / طي">'
            || CASE WHEN l_open THEN '&minus;' ELSE '+' END || '</span>' || l_lbl
            || '<ul' || CASE WHEN NOT l_open THEN ' style="display:none"' END || '>');
    ELSE
      htp.p('<li class="lf"><span class="tg-sp"></span>' || l_lbl);
    END IF;
  END LOOP;
  WHILE top > 0 LOOP pop; END LOOP;
  htp.p('</ul>');
END;
PLSQL

my $suggest = src('p10_suggest.sql');
$suggest =~ s/^DECLARE/PROCEDURE s IS/;
$suggest =~ s/;\s*\z/;/;
my $suggest_ajax = "DECLARE\n$suggest\nBEGIN\n  s;\n  apex_json.open_object;\n  apex_json.write('level', :P10_ACC_LEVEL);\n  apex_json.write('code', :P10_ACCOUNT_CODE);\n  apex_json.write('type', :P10_ACC_TYPE);\n  apex_json.write('nature', :P10_NATURE);\n  apex_json.close_object;\nEND;";

my $acc_js = <<'JS';
// النوع يُورث من الحساب الأب: يظهر فقط للحساب الرئيسي (بدون أب)
var accTypeToggle = function () {
  if (apex.item('P10_PARENT_ID').getValue()) apex.item('P10_ACC_TYPE').hide(); else apex.item('P10_ACC_TYPE').show();
};
accTypeToggle();
apex.jQuery('#P10_PARENT_ID').on('change', accTypeToggle);
apex.jQuery('#P10_PARENT_ID').on('change', function () {
  apex.server.process('SUGGEST', {pageItems: '#P10_PARENT_ID'}, {dataType: 'json'}).done(function (d) {
    apex.item('P10_ACC_LEVEL').setValue(d.level);
    document.getElementById('acc_level').textContent = d.level;
    apex.item('P10_ACCOUNT_CODE').setValue(d.code);   // رقم الحساب مخفي: يُعاد توليده عند تغيير الأب
    if (d.type) apex.item('P10_ACC_TYPE').setValue(d.type);
    if (d.nature) apex.item('P10_NATURE').setValue(d.nature);
  });
});
// الشجرة المنزلقة: + يفتح الفرع ، − يطويه مع كل فروعه الداخلية
var $t = apex.jQuery;
var accTreeSet = function (li, open, anim) {
  li.toggleClass('open', open);
  li.children('.tg').html(open ? '&minus;' : '+');
  var ul = li.children('ul');
  if (open) { anim ? ul.stop(true, true).slideDown(150) : ul.show(); }
  else      { anim ? ul.stop(true, true).slideUp(150)   : ul.hide(); }
};
$t(document).on('click', '.acc-tree .tg', function () {
  var li = $t(this).closest('li');
  if (li.hasClass('open')) {
    li.find('li.nd').each(function () { accTreeSet($t(this), false, false); });   // طي كل الفروع الداخلية
    accTreeSet(li, false, true);
  } else {
    accTreeSet(li, true, true);
  }
});
$t(document).on('click', '.acc-tree-tools [data-tree]', function () {
  var open = $t(this).attr('data-tree') === 'open';
  $t('.acc-tree li.nd').each(function () { accTreeSet($t(this), open, false); });
});
JS

page(id => 10, name => 'شجرة الحسابات', alias => 'ACCOUNTS', auth => 'IS_ACCOUNTANT', onload => $acc_js, css => <<'CSS');
.acc-tree, .acc-tree ul { list-style: none; margin: 0; padding-inline-start: 18px; }
.acc-tree > li { margin: 2px 0; }
.acc-tree li { margin: 1px 0; }
.acc-tree .tg, .acc-tree-tools .tg-ic { display: inline-block; width: 18px; height: 18px; line-height: 15px; text-align: center;
  border: 1px solid #8a8a8a; border-radius: 3px; font-weight: 700; font-size: 14px; background: #fff; vertical-align: middle; }
.acc-tree .tg { cursor: pointer; margin-inline-end: 4px; user-select: none; }
.acc-tree .tg:hover { background: #eef5ee; border-color: #146b2d; color: #146b2d; }
.acc-tree .tg-sp { display: inline-block; width: 22px; }
.acc-tree-tools { margin-bottom: 8px; }
.acc-tree-tools .tg-ic { width: 16px; height: 16px; line-height: 13px; font-size: 13px; margin-inline-end: 2px; }
.acc-tree a { text-decoration: none; padding: 2px 4px; border-radius: 3px; display: inline-block; }
.acc-tree a.sel { background: var(--ut-palette-primary, #0572ce); color: #fff; }
CSS
region(name => 'tree', title => 'شجرة الحسابات', type => 'plsql', plsql => $tree, seq => 10, span => 5);
region(name => 'form', title => 'بيانات الحساب', type => 'static', seq => 20, span => 7, same_row => 1,
       html => '<div style="margin-bottom:8px">المستوى: <b id="acc_level">&P10_ACC_LEVEL.</b> (الحساب التحليلي في المستوى 4 فقط يقبل القيود)</div>');
item(name => 'P10_ACCOUNT_ID', region => 'form', type => 'hidden', seq => 1);
item(name => 'P10_ACC_LEVEL', region => 'form', type => 'hidden', seq => 2);
item(name => 'P10_PARENT_ID', region => 'form', type => 'popup', label => 'الحساب الأب (فارغ = حساب رئيسي)', seq => 10,
     lov => "SELECT LPAD(' ', (acc_level - 1) * 3) || account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE acc_level < 4 ORDER BY account_code");
# رقم الحساب يُولَّد تلقائياً من الحساب الأب ولا يُدخل يدوياً
item(name => 'P10_ACCOUNT_CODE', region => 'form', type => 'hidden', seq => 20);
item(name => 'P10_NAME_AR', region => 'form', label => 'الاسم', seq => 30, same_line => 1, required => 1);
item(name => 'P10_NAME_EN', region => 'form', label => 'الاسم الإنجليزي', seq => 40);
item(name => 'P10_ACC_TYPE', region => 'form', type => 'select', label => 'النوع', seq => 90, same_line => 1, required => 1,
     lov => "SELECT 'أصول' d, 'ASSET' r FROM dual UNION ALL SELECT 'خصوم', 'LIAB' FROM dual UNION ALL SELECT 'حقوق ملكية', 'EQUITY' FROM dual UNION ALL SELECT 'إيرادات', 'REV' FROM dual UNION ALL SELECT 'مصروفات', 'EXP' FROM dual");
item(name => 'P10_NATURE', region => 'form', type => 'select', label => 'الطبيعة', seq => 50, same_line => 1, required => 1,
     lov => "SELECT 'مدين' d, 'D' r FROM dual UNION ALL SELECT 'دائن', 'C' FROM dual");
item(name => 'P10_CASH_BANK', region => 'form', type => 'select', label => 'خزينة / بنك (المستوى 4 فقط)', seq => 80,
     lov => "SELECT 'لا' d, 'N' r FROM dual UNION ALL SELECT 'خزينة', 'C' FROM dual UNION ALL SELECT 'بنك', 'B' FROM dual");
item(name => 'P10_CURRENCY_CODE', region => 'form', type => 'select', label => 'عملة الحساب', lov => $LOV{currencies}, null => 'أي عملة', seq => 100);
item(name => 'P10_COMPANY_ID', region => 'form', type => 'select', label => 'الشركة', lov => $LOV{all_companies}, null => 'مشترك لكل الشركات', seq => 110, same_line => 1);
item(name => 'P10_IS_ACTIVE', region => 'form', type => 'select', label => 'فعّال', lov => $yn, seq => 120, same_line => 1);
button(name => 'SAVE', region => 'form', label => 'حفظ', hot => 1, seq => 10);
button(name => 'DELETE', region => 'form', label => 'حذف', position => 'PREVIOUS', seq => 20, if_not_null => 'P10_ACCOUNT_ID', novalidate => 1, confirm => 'حذف الحساب؟');
button(name => 'NEW', region => 'form', label => 'جديد', position => 'PREVIOUS', seq => 30, url => 'f?p=&APP_ID.:10:&SESSION.::&DEBUG.:10::');
button(name => 'CHILD', region => 'form', label => 'حساب فرعي', position => 'PREVIOUS', seq => 40,
       url => 'f?p=&APP_ID.:10:&SESSION.::&DEBUG.:10:P10_PARENT_ID:&P10_ACCOUNT_ID.', cond => ':P10_ACCOUNT_ID IS NOT NULL AND :P10_ACC_LEVEL < 4');
process(name => 'LOAD', point => 'BEFORE_HEADER', seq => 10, cond => ':P10_ACCOUNT_ID IS NOT NULL', code => <<'SQL');
DECLARE a accounts%ROWTYPE;
BEGIN
  SELECT * INTO a FROM accounts WHERE account_id = :P10_ACCOUNT_ID;
  :P10_PARENT_ID := a.parent_id; :P10_ACC_LEVEL := a.acc_level; :P10_ACCOUNT_CODE := a.account_code;
  :P10_NAME_AR := a.name_ar; :P10_NAME_EN := a.name_en; :P10_ACC_TYPE := a.acc_type; :P10_NATURE := a.nature;
  :P10_CASH_BANK := a.cash_bank; :P10_CURRENCY_CODE := a.currency_code; :P10_COMPANY_ID := a.company_id;
  :P10_IS_ACTIVE := a.is_active;
END;
SQL
process(name => 'NEW_DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ':P10_ACCOUNT_ID IS NULL', code => (<<'SQL' =~ s{__SUGGEST__}{src('p10_suggest.sql')}er));
DECLARE
  PROCEDURE s IS
  BEGIN
    NULL;
  END;
BEGIN
  IF :P10_IS_ACTIVE IS NULL THEN :P10_IS_ACTIVE := 'Y'; END IF;
  IF :P10_CASH_BANK IS NULL THEN :P10_CASH_BANK := 'N'; END IF;
  IF :P10_ACCOUNT_CODE IS NULL THEN
    __SUGGEST__
  END IF;
END;
SQL
check(name => 'CHECK_PARENT', seq => 10, button => 'SAVE', code => src('p10_val1.sql'));
check(name => 'CHECK_CODE',   seq => 20, button => 'SAVE', code => src('p10_val2.sql'));
check(name => 'CHECK_MOVES',  seq => 30, button => 'SAVE', code => src('p10_val3.sql'));
check(name => 'CHECK_MOVE_PARENT', seq => 40, button => 'SAVE', code => src('p10_val5.sql'));
check(name => 'CHECK_DELETE', seq => 50, button => 'DELETE', code => src('p10_val4.sql'));
process(name => 'SAVE_ACCOUNT', seq => 60, button => 'SAVE', success => 'تم حفظ الحساب', code => <<'SQL');
DECLARE
  l_lvl NUMBER := 1;
BEGIN
  IF apex_error.have_errors_occurred THEN RETURN; END IF;
  IF :P10_PARENT_ID IS NOT NULL THEN
    -- المستوى والنوع من الحساب الأب
    SELECT acc_level + 1, acc_type INTO l_lvl, :P10_ACC_TYPE FROM accounts WHERE account_id = :P10_PARENT_ID;
  END IF;
  IF :P10_ACCOUNT_ID IS NULL THEN
    INSERT INTO accounts (account_code, name_ar, name_en, parent_id, acc_level, acc_type, nature,
                          cash_bank, currency_code, company_id, is_active)
    VALUES (:P10_ACCOUNT_CODE, :P10_NAME_AR, :P10_NAME_EN, :P10_PARENT_ID, l_lvl, :P10_ACC_TYPE, :P10_NATURE,
            CASE WHEN l_lvl = 4 THEN NVL(:P10_CASH_BANK, 'N') ELSE 'N' END,
            :P10_CURRENCY_CODE, :P10_COMPANY_ID, NVL(:P10_IS_ACTIVE, 'Y'))
    RETURNING account_id INTO :P10_ACCOUNT_ID;
  ELSE
    UPDATE accounts
    SET account_code = :P10_ACCOUNT_CODE, name_ar = :P10_NAME_AR, name_en = :P10_NAME_EN,
        parent_id = :P10_PARENT_ID, acc_level = l_lvl, acc_type = :P10_ACC_TYPE, nature = :P10_NATURE,
        cash_bank = CASE WHEN l_lvl = 4 THEN NVL(:P10_CASH_BANK, 'N') ELSE 'N' END,
        currency_code = :P10_CURRENCY_CODE, company_id = :P10_COMPANY_ID, is_active = NVL(:P10_IS_ACTIVE, 'Y')
    WHERE account_id = :P10_ACCOUNT_ID;
  END IF;
END;
SQL
process(name => 'DELETE_ACCOUNT', seq => 70, button => 'DELETE', success => 'تم حذف الحساب', code => <<'SQL');
BEGIN
  IF apex_error.have_errors_occurred THEN RETURN; END IF;
  DELETE FROM accounts WHERE account_id = :P10_ACCOUNT_ID;
  :P10_ACCOUNT_ID := NULL;
END;
SQL
# قائمة حسابات المستوى 4 (التحليلية) مع رابط التعديل
region(name => 'l4', title => 'الحسابات التحليلية (المستوى 4) - اضغط رقم الحساب لتعديله', type => 'ir', seq => 30, sql => <<'SQL',
SELECT a.account_id,
       a.account_code AS "رقم الحساب",
       a.name_ar      AS "اسم الحساب",
       p.account_code || ' - ' || p.name_ar AS "الحساب الأب (مستوى 3)",
       DECODE(a.acc_type,'ASSET','أصول','LIAB','خصوم','EQUITY','حقوق ملكية','REV','إيرادات','EXP','مصروفات') AS "النوع",
       DECODE(a.nature,'D','مدين','دائن') AS "الطبيعة",
       DECODE(a.cash_bank,'C','خزينة','B','بنك') AS "خزينة / بنك",
       DECODE(a.is_active,'Y','فعّال','موقوف') AS "الحالة"
FROM   accounts a
JOIN   accounts p ON p.account_id = a.parent_id
WHERE  a.acc_level = 4
SQL
       links => { 'رقم الحساب' => 'f?p=&APP_ID.:10:&SESSION.::&DEBUG.::P10_ACCOUNT_ID:#ACCOUNT_ID#' });
ajax('SUGGEST', $suggest_ajax);
branch_self();
end_page();


# =====================================================================
# 199 بيانات الشركة (شركة واحدة): الاسم يظهر في رأس الصفحات وكل التقارير والمطبوعات
# =====================================================================
page(id => 199, name => 'بيانات الشركة', alias => 'COMPANY', auth => 'IS_GM');
region(name => 'f', title => 'بيانات الشركة', type => 'static', seq => 10,
       html => '<div class="jl-hint">يظهر اسم الشركة وعنوانها وهاتفها ورقمها الضريبي في رأس الصفحات وفي كل التقارير والفواتير المطبوعة.</div>');
item(name => 'P199_NAME_AR', region => 'f', label => 'اسم الشركة', seq => 10, max => 150);
item(name => 'P199_NAME_EN', region => 'f', label => 'الاسم بالإنجليزية', seq => 20, same_line => 1, max => 150);
item(name => 'P199_ADDRESS', region => 'f', label => 'العنوان', seq => 30, max => 300);
item(name => 'P199_PHONE', region => 'f', label => 'الهاتف', seq => 40, max => 50);
item(name => 'P199_TAX_NO', region => 'f', label => 'الرقم الضريبي', seq => 50, same_line => 1, max => 50);
button(name => 'SAVE', region => 'f', label => 'حفظ', hot => 1);
process(name => 'LOAD', point => 'BEFORE_HEADER', code => <<'SQL');
BEGIN
  SELECT name_ar, name_en, address, phone, tax_no
  INTO   :P199_NAME_AR, :P199_NAME_EN, :P199_ADDRESS, :P199_PHONE, :P199_TAX_NO
  FROM   companies WHERE is_parent = 'Y';
END;
SQL
process(name => 'SAVE', button => 'SAVE', success => 'تم حفظ بيانات الشركة', code => <<'SQL');
BEGIN
  IF TRIM(:P199_NAME_AR) IS NULL THEN raise_application_error(-20001, 'أدخل اسم الشركة'); END IF;
  UPDATE companies
  SET    name_ar = TRIM(:P199_NAME_AR), name_en = :P199_NAME_EN, address = :P199_ADDRESS,
         phone = :P199_PHONE, tax_no = :P199_TAX_NO
  WHERE  is_parent = 'Y';
  -- تحديث الاسم المعروض في الجلسة الحالية
  :G_COMPANY_NAME := TRIM(:P199_NAME_AR);
  :G_COMPANY_INFO := LTRIM(:P199_ADDRESS || NVL2(:P199_PHONE, ' | هاتف: ' || :P199_PHONE, NULL)
                           || NVL2(:P199_TAX_NO, ' | الرقم الضريبي: ' || :P199_TAX_NO, NULL), ' |');
END;
SQL
branch_self();
end_page();

# =====================================================================
# 252 زيادة أسعار كل الأصناف بنسبة (سعر البيع أو الشراء أو الاثنين)
# =====================================================================
page(id => 252, name => 'زيادة الأسعار بنسبة', alias => 'PRICE-UP', auth => 'IS_GM');
region(name => 'f', title => 'زيادة الأسعار بنسبة', type => 'static', seq => 10,
       html => '<div class="jl-hint">تُطبَّق النسبة على كل الأصناف الفعّالة. اكتب نسبة سالبة للتخفيض (مثال: -5).</div>');
item(name => 'P252_TARGET', region => 'f', type => 'select', label => 'السعر', seq => 10,
     lov => "SELECT 'سعر البيع' d, 'SALE' r FROM dual UNION ALL SELECT 'سعر الشراء', 'PURCHASE' FROM dual UNION ALL SELECT 'سعر البيع والشراء', 'BOTH' FROM dual");
item(name => 'P252_PERCENT', region => 'f', label => 'النسبة %', seq => 20, same_line => 1);
item(name => 'P252_ROUND', region => 'f', type => 'select', label => 'التقريب', seq => 30, same_line => 1,
     lov => "SELECT 'لأقرب قرشين (0.01)' d, '2' r FROM dual UNION ALL SELECT 'لأقرب جنيه' d, '0' r FROM dual");
button(name => 'APPLY', region => 'f', label => 'تطبيق الزيادة', hot => 1, confirm => 'تطبيق النسبة على أسعار كل الأصناف؟');
region(name => 'ir', title => 'أسعار الأصناف الحالية', type => 'ir', seq => 20, sql => <<'SQL');
SELECT i.item_code AS "الكود", i.name_ar AS "الصنف", u.name_ar AS "الوحدة الأساسية",
       i.purchase_price AS "سعر الشراء", i.sale_price AS "سعر البيع",
       CASE WHEN NVL(i.purchase_price, 0) > 0
            THEN ROUND(100 * (i.sale_price - i.purchase_price) / i.purchase_price, 1) END AS "نسبة الربح %"
FROM   items i JOIN units u ON u.unit_id = i.base_unit_id
WHERE  i.is_active = 'Y'
ORDER  BY i.item_code
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P252_TARGET IS NULL THEN :P252_TARGET := 'SALE'; END IF;",
  "IF :P252_ROUND IS NULL THEN :P252_ROUND := '2'; END IF;"));
process(name => 'APPLY', button => 'APPLY', code => <<'SQL');
DECLARE
  l_pct NUMBER;
  l_dec NUMBER := TO_NUMBER(NVL(:P252_ROUND, '2'));
  l_n   NUMBER;
BEGIN
  BEGIN
    l_pct := TO_NUMBER(REPLACE(:P252_PERCENT, ',', ''));
  EXCEPTION WHEN OTHERS THEN
    raise_application_error(-20001, 'أدخل النسبة رقماً، مثل 10 أو 2.5');
  END;
  IF l_pct IS NULL OR l_pct = 0 THEN raise_application_error(-20001, 'أدخل النسبة'); END IF;
  IF l_pct <= -100 OR l_pct > 1000 THEN raise_application_error(-20001, 'النسبة غير منطقية'); END IF;

  UPDATE items
  SET    sale_price     = CASE WHEN :P252_TARGET IN ('SALE','BOTH')
                               THEN ROUND(NVL(sale_price, 0) * (1 + l_pct / 100), l_dec) ELSE sale_price END,
         purchase_price = CASE WHEN :P252_TARGET IN ('PURCHASE','BOTH')
                               THEN ROUND(NVL(purchase_price, 0) * (1 + l_pct / 100), l_dec) ELSE purchase_price END
  WHERE  is_active = 'Y';
  l_n := SQL%ROWCOUNT;
  apex_application.g_print_success_message := 'تم تعديل أسعار ' || l_n || ' صنفاً بنسبة ' || l_pct || '%';
  :P252_PERCENT := NULL;
END;
SQL
branch_self();
end_page();

# مقاسات ومواضع طباعة الشيك لكل بنك (بالمليمتر من أعلى ويمين الشيك) - الصف بدون بنك هو المقاس الافتراضي
crud(list => 240, form => 241, title => 'مقاسات طباعة الشيك', table => 'cheque_layouts', alias => 'CHEQUE-LAYOUTS', auth => 'IS_GM', order => 't.layout_name', cols => [
  ['LAYOUT_NAME', 'الاسم', 'text', undef, 1],
  ['BANK_ACCOUNT_ID', 'البنك (فارغ = الافتراضي)', 'select', "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE cash_bank = 'B' ORDER BY account_code", undef, 'NUMBER'],
  ['WIDTH_MM', 'عرض الشيك (مم)', 'num', undef, 1], ['HEIGHT_MM', 'ارتفاع الشيك (مم)', 'num', undef, 1],
  ['DATE_TOP', 'التاريخ: من الأعلى', 'num', undef, 1], ['DATE_RIGHT', 'التاريخ: من اليمين', 'num', undef, 1],
  ['PAYEE_TOP', 'المستفيد: من الأعلى', 'num', undef, 1], ['PAYEE_RIGHT', 'المستفيد: من اليمين', 'num', undef, 1],
  ['WORDS_TOP', 'المبلغ كتابة: من الأعلى', 'num', undef, 1], ['WORDS_RIGHT', 'المبلغ كتابة: من اليمين', 'num', undef, 1],
  ['WORDS_WIDTH', 'عرض سطر المبلغ كتابة', 'num', undef, 1],
  ['AMOUNT_TOP', 'المبلغ رقماً: من الأعلى', 'num', undef, 1], ['AMOUNT_RIGHT', 'المبلغ رقماً: من اليمين', 'num', undef, 1],
  ['FONT_SIZE', 'حجم الخط (px)', 'num', undef, 1]]);

# الإدارات وبنود الميزانية (لكل بند رقم إيضاح)
crud(list => 242, form => 243, title => 'الإدارات', table => 'departments', alias => 'DEPARTMENTS', auth => 'IS_GM', order => 't.dept_code', cols => [
  ['DEPT_CODE', 'الكود', 'text', undef, 1], ['NAME_AR', 'اسم الإدارة', 'text', undef, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);
crud(list => 244, form => 245, title => 'بنود الميزانية والإيضاحات', table => 'budget_items', alias => 'BUDGET-ITEMS', auth => 'IS_GM', order => 't.sort_order, t.note_no', cols => [
  ['NOTE_NO', 'رقم الإيضاح', 'text', undef, 1], ['NAME_AR', 'البند', 'text', undef, 1],
  ['ITEM_TYPE', 'النوع', 'select', "SELECT 'مصروفات' d, 'EXP' r FROM dual UNION ALL SELECT 'إيرادات', 'REV' FROM dual", 1],
  ['ACCOUNT_ID', 'الحساب (لحساب الفعلي، يشمل ما تحته)', 'popup', $LOV{accounts_all}, undef, 'NUMBER'],
  ['SORT_ORDER', 'الترتيب', 'num', undef, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

1;
