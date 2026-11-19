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
  my $sql = "SELECT " . join(",\n       ", @sel) . "\nFROM $tbl t" . ($c{order} ? "\nORDER BY $c{order}" : '');
  page(id => $L, name => $c{title}, alias => $c{alias}, auth => $c{auth},
       onload => "apex.jQuery(window).on('apexafterclosedialog', function () { location.reload(); });");
  region(name => 'ir', title => $c{title}, type => 'ir', sql => $sql, pk => 'ROWID',
         detail_link => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:RP:P${F}_ROWID:\\#ROWID#\\");
  button(name => 'CREATE', region => 'ir', label => 'إضافة', hot => 1, position => 'RIGHT_OF_IR_SEARCH_BAR',
         url => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:$F\::");
  end_page();

  # ---------- صفحة النموذج (Modal)
  my $fsql = "SELECT ROWID, " . join(', ', map { $_->[0] } @cols) . " FROM $tbl";
  page(id => $F, name => $c{title}, alias => "$c{alias}-FORM", modal => 1, auth => $c{auth});
  region(name => 'form', title => $c{title}, type => 'form', sql => $fsql, seq => 10);
  region(name => 'buttons', title => 'Buttons', type => 'static', html => '', template => 'reg_buttons', seq => 20, position => 'REGION_POSITION_03');
  item(name => "P${F}_ROWID", region => 'form', type => 'hidden', col => 'ROWID', dtype => 'ROWID', pk => 1, query_only => 1, protected => 1, seq => 1);
  my $seq = 10;
  for my $col (@cols) {
    my ($name, $label, $type, $lov, $req, $dtype) = @$col;
    $type //= 'text';
    $dtype //= $type eq 'date' ? 'DATE' : $type eq 'num' ? 'NUMBER' : 'VARCHAR2';
    item(name => "P${F}_$name", region => 'form', col => $name, dtype => $dtype, label => $label,
         type => $type eq 'num' ? 'text' : $type, lov => $lov, null => ($type eq 'select' && !$req) ? 1 : undef,
         required => $req, seq => ($seq += 10));
  }
  button(name => 'CANCEL', region => 'buttons', label => 'إلغاء', position => 'CLOSE', js => 'apex.navigation.dialog.cancel(true);', seq => 10);
  button(name => 'DELETE', region => 'buttons', label => 'حذف', position => 'DELETE', seq => 20, dml => 'DELETE',
         if_not_null => "P${F}_ROWID", novalidate => 1, confirm => '&APP_TEXT$DELETE_MSG!RAW.');
  button(name => 'SAVE', region => 'buttons', label => 'حفظ التعديلات', position => 'NEXT', seq => 30, hot => 1, dml => 'UPDATE', if_not_null => "P${F}_ROWID");
  button(name => 'CREATE', region => 'buttons', label => 'حفظ', position => 'NEXT', seq => 40, hot => 1, dml => 'INSERT', if_null => "P${F}_ROWID");
  process(name => 'Init form', point => 'BEFORE_HEADER', kind => 'form_init', region => 'form');
  process(name => 'Process form', seq => 10, kind => 'form_dml', region => 'form');
  process(name => 'Close Dialog', seq => 20, kind => 'close', when_req => 'CREATE,SAVE,DELETE');
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
my $terms    = "SELECT name_ar d, terminal_id r FROM pos_terminals ORDER BY name_ar";
my $roles    = "SELECT 'المدير العام' d, 'GM' r FROM dual UNION ALL SELECT 'محاسب', 'ACCOUNTANT' FROM dual UNION ALL SELECT 'موارد بشرية', 'HR' FROM dual UNION ALL SELECT 'أمين مخزن', 'STORE' FROM dual UNION ALL SELECT 'كاشير', 'CASHIER' FROM dual UNION ALL SELECT 'مستخدم', 'USER' FROM dual";
my $settings = "SELECT code || ' - ' || n d, code r FROM (SELECT 'SALES' code, 'مبيعات للشركات' n FROM dual UNION ALL SELECT 'SALES_RETURN', 'مردودات المبيعات' FROM dual UNION ALL SELECT 'INTERCO_AP', 'مستحق للشركة الأم' FROM dual UNION ALL SELECT 'PURCHASES', 'وارد من الأم (مخزون)' FROM dual UNION ALL SELECT 'INVENTORY', 'المخزون' FROM dual UNION ALL SELECT 'COGS', 'تكلفة المبيعات' FROM dual UNION ALL SELECT 'INVENTORY_ADJ', 'فروقات الجرد' FROM dual UNION ALL SELECT 'POS_SALES', 'مبيعات نقاط البيع' FROM dual UNION ALL SELECT 'CASH_DIFF', 'عجز وزيادة الصناديق' FROM dual UNION ALL SELECT 'SALARY_EXP', 'مصروف الرواتب' FROM dual UNION ALL SELECT 'INCENTIVE_EXP', 'مصروف الحوافز' FROM dual UNION ALL SELECT 'SALARY_DIFF', 'فروقات الرواتب' FROM dual UNION ALL SELECT 'SALARY_PAYABLE', 'رواتب مستحقة' FROM dual UNION ALL SELECT 'DEDUCTIONS', 'خصومات الموظفين' FROM dual)";

crud(list => 200, form => 201, title => 'الشركات', table => 'companies', alias => 'COMPANIES', auth => 'IS_GM', order => 't.company_code', cols => [
  ['COMPANY_CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي'],
  ['IS_PARENT', 'شركة أم؟', 'select', $yn, 1], ['PARENT_ID', 'الشركة الأم', 'select', $LOV{all_companies}, undef, 'NUMBER'],
  ['PRICE_LIST_ID', 'قائمة أسعار الصرف لها', 'select', $pls, undef, 'NUMBER'], ['POS_PRICE_LIST_ID', 'قائمة أسعار نقاط البيع', 'select', $pls, undef, 'NUMBER'],
  ['TAX_NO', 'الرقم الضريبي'], ['PHONE', 'الهاتف'], ['ADDRESS', 'العنوان'], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 202, form => 203, title => 'العملات', table => 'currencies', alias => 'CURRENCIES', auth => 'IS_ACCOUNTANT', order => 't.currency_code', cols => [
  ['CURRENCY_CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي'],
  ['SYMBOL', 'الرمز المختصر'], ['DECIMALS', 'الكسور', 'num', undef, 1], ['IS_BASE', 'العملة الأساسية', 'select', $yn, 1],
  ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 218, form => 219, title => 'أسعار الصرف', table => 'exchange_rates', alias => 'RATES', auth => 'IS_ACCOUNTANT', order => 't.rate_date DESC', cols => [
  ['CURRENCY_CODE', 'العملة', 'select', $LOV{currencies}, 1], ['RATE_DATE', 'التاريخ', 'date', undef, 1], ['RATE', 'السعر', 'num', undef, 1]]);

crud(list => 204, form => 205, title => 'السنوات المالية', table => 'fiscal_years', alias => 'FISCAL', auth => 'IS_GM', order => 't.fy_year DESC', cols => [
  ['FY_YEAR', 'السنة', 'num', undef, 1], ['START_DATE', 'البداية', 'date', undef, 1], ['END_DATE', 'النهاية', 'date', undef, 1],
  ['IS_CLOSED', 'مغلقة', 'select', $yn, 1]]);

crud(list => 206, form => 207, title => 'المستخدمون', table => 'app_users', alias => 'USERS', auth => 'IS_GM', order => 't.user_name', cols => [
  ['USER_NAME', 'اسم الدخول (بأحرف كبيرة)', 'text', undef, 1], ['FULL_NAME', 'الاسم', 'text', undef, 1],
  ['COMPANY_ID', 'الشركة', 'select', $LOV{all_companies}, 1, 'NUMBER'], ['USER_ROLE', 'الدور', 'select', $roles, 1],
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

crud(list => 238, form => 239, title => 'شركات المستخدمين', table => 'user_companies', alias => 'USER-COMPANIES', auth => 'IS_GM', cols => [
  ['USER_NAME', 'المستخدم', 'select', $users, 1], ['COMPANY_ID', 'الشركة', 'select', $LOV{all_companies}, 1, 'NUMBER']]);

crud(list => 208, form => 209, title => 'الحسابات الافتراضية', table => 'account_settings', alias => 'ACC-SETTINGS', auth => 'IS_GM', order => 't.company_id, t.setting_code', cols => [
  ['COMPANY_ID', 'الشركة', 'select', $LOV{all_companies}, 1, 'NUMBER'], ['SETTING_CODE', 'الإعداد', 'select', $settings, 1],
  ['ACCOUNT_ID', 'الحساب', 'popup', $LOV{accounts4}, 1, 'NUMBER']]);

crud(list => 240, form => 241, title => 'حسابات ذمم الشركات الفرعية', table => 'company_accounts', alias => 'COMPANY-AR', auth => 'IS_GM', cols => [
  ['COMPANY_ID', 'الشركة الفرعية', 'select', $LOV{subs}, 1, 'NUMBER'], ['AR_ACCOUNT_ID', 'حسابها لدى الأم', 'popup', $LOV{accounts4}, 1, 'NUMBER']]);

crud(list => 212, form => 213, title => 'الوحدات', table => 'units', alias => 'UNITS', auth => 'IS_STORE', order => 't.name_ar', cols => [
  ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي']]);

crud(list => 210, form => 211, title => 'الأصناف', table => 'items', alias => 'ITEMS', auth => 'IS_STORE', order => 't.item_code', cols => [
  ['ITEM_CODE', 'الكود', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['NAME_EN', 'الاسم الإنجليزي'],
  ['BASE_UNIT_ID', 'الوحدة الأساسية', 'select', $units, 1, 'NUMBER'], ['BARCODE', 'الباركود'],
  ['REORDER_LEVEL', 'حد الطلب', 'num'], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 236, form => 237, title => 'وحدات الأصناف', table => 'item_units', alias => 'ITEM-UNITS', auth => 'IS_STORE', order => 't.item_id, t.factor', cols => [
  ['ITEM_ID', 'الصنف', 'popup', $items, 1, 'NUMBER'], ['UNIT_ID', 'الوحدة', 'select', $units, 1, 'NUMBER'],
  ['FACTOR', 'عدد الوحدات الأساسية', 'num', undef, 1], ['BARCODE', 'الباركود']]);

crud(list => 214, form => 215, title => 'قوائم الأسعار', table => 'price_lists', alias => 'PRICE-LISTS', auth => 'IS_GM', order => 't.name_ar', cols => [
  ['NAME_AR', 'الاسم', 'text', undef, 1], ['CURRENCY_CODE', 'العملة', 'select', $LOV{currencies}, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 234, form => 235, title => 'أسعار الأصناف', table => 'price_list_items', alias => 'PRICES', auth => 'IS_GM', order => 't.price_list_id, t.item_id', cols => [
  ['PRICE_LIST_ID', 'قائمة الأسعار', 'select', $pls, 1, 'NUMBER'], ['ITEM_ID', 'الصنف', 'popup', $items, 1, 'NUMBER'],
  ['UNIT_ID', 'الوحدة', 'select', $units, 1, 'NUMBER'], ['PRICE', 'السعر', 'num', undef, 1]]);

crud(list => 216, form => 217, title => 'المخازن', table => 'warehouses', alias => 'WAREHOUSES', auth => 'IS_STORE', order => 't.company_id', cols => [
  ['COMPANY_ID', 'الشركة', 'select', $LOV{all_companies}, 1, 'NUMBER'], ['NAME_AR', 'الاسم', 'text', undef, 1], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

crud(list => 220, form => 221, title => 'الدرجات الوظيفية', table => 'job_grades', alias => 'GRADES', auth => 'IS_HR', order => 't.grade_code', cols => [
  ['GRADE_CODE', 'الرمز', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1], ['BASIC_SALARY', 'الراتب الأساسي', 'num', undef, 1],
  ['CURRENCY_CODE', 'العملة', 'select', $LOV{currencies}, 1]]);

crud(list => 222, form => 223, title => 'الموظفون', table => 'employees', alias => 'EMPLOYEES', auth => 'IS_HR', order => 't.emp_no', cols => [
  ['EMP_NO', 'الرقم', 'text', undef, 1], ['NAME_AR', 'الاسم', 'text', undef, 1],
  ['COMPANY_ID', 'الشركة (يُحمَّل عليها الراتب)', 'select', $LOV{all_companies}, 1, 'NUMBER'], ['GRADE_ID', 'الدرجة', 'select', $grades, 1, 'NUMBER'],
  ['HIRE_DATE', 'تاريخ التعيين', 'date'], ['BASIC_SALARY', 'أساسي خاص (فارغ = أساسي الدرجة)', 'num'],
  ['BANK_ACCOUNT', 'الحساب البنكي'], ['IS_ACTIVE', 'فعّال', 'select', $yn, 1]]);

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
my $tree = <<'PLSQL';
DECLARE
  TYPE t_b IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
  st    t_b;
  top   PLS_INTEGER := 0;
  l_lbl VARCHAR2(4000);
  PROCEDURE pop IS
  BEGIN
    IF st(top) THEN htp.p('</ul></details></li>'); ELSE htp.p('</li>'); END IF;
    top := top - 1;
  END;
BEGIN
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
      htp.p('<li><details' || CASE WHEN r.lvl < 3 THEN ' open' END || '><summary>' || l_lbl || '</summary><ul>');
    ELSE
      htp.p('<li>' || l_lbl);
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
apex.jQuery('#P10_PARENT_ID').on('change', function () {
  apex.server.process('SUGGEST', {pageItems: '#P10_PARENT_ID'}, {dataType: 'json'}).done(function (d) {
    apex.item('P10_ACC_LEVEL').setValue(d.level);
    document.getElementById('acc_level').textContent = d.level;
    if (!apex.item('P10_ACCOUNT_ID').getValue()) apex.item('P10_ACCOUNT_CODE').setValue(d.code);
    if (d.type) apex.item('P10_ACC_TYPE').setValue(d.type);
    if (d.nature) apex.item('P10_NATURE').setValue(d.nature);
  });
});
JS

page(id => 10, name => 'شجرة الحسابات', alias => 'ACCOUNTS', auth => 'IS_ACCOUNTANT', onload => $acc_js, css => <<'CSS');
.acc-tree, .acc-tree ul { list-style: none; margin: 0; padding-inline-start: 18px; }
.acc-tree > li { margin: 2px 0; }
.acc-tree summary { cursor: pointer; }
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
item(name => 'P10_ACCOUNT_CODE', region => 'form', label => 'رقم الحساب', seq => 20, required => 1);
item(name => 'P10_NAME_AR', region => 'form', label => 'الاسم', seq => 30, same_line => 1, required => 1);
item(name => 'P10_NAME_EN', region => 'form', label => 'الاسم الإنجليزي', seq => 40);
item(name => 'P10_ACC_TYPE', region => 'form', type => 'select', label => 'النوع', seq => 50, same_line => 1, required => 1,
     lov => "SELECT 'أصول' d, 'ASSET' r FROM dual UNION ALL SELECT 'خصوم', 'LIAB' FROM dual UNION ALL SELECT 'حقوق ملكية', 'EQUITY' FROM dual UNION ALL SELECT 'إيرادات', 'REV' FROM dual UNION ALL SELECT 'مصروفات', 'EXP' FROM dual");
item(name => 'P10_NATURE', region => 'form', type => 'select', label => 'الطبيعة', seq => 60, required => 1,
     lov => "SELECT 'مدين' d, 'D' r FROM dual UNION ALL SELECT 'دائن', 'C' FROM dual");
item(name => 'P10_CASH_BANK', region => 'form', type => 'select', label => 'صندوق / بنك (المستوى 4 فقط)', seq => 70, same_line => 1,
     lov => "SELECT 'لا' d, 'N' r FROM dual UNION ALL SELECT 'صندوق', 'C' FROM dual UNION ALL SELECT 'بنك', 'B' FROM dual");
item(name => 'P10_CURRENCY_CODE', region => 'form', type => 'select', label => 'عملة الحساب', lov => $LOV{currencies}, null => 'أي عملة', seq => 80);
item(name => 'P10_COMPANY_ID', region => 'form', type => 'select', label => 'الشركة', lov => $LOV{all_companies}, null => 'مشترك لكل الشركات', seq => 90, same_line => 1);
item(name => 'P10_IS_ACTIVE', region => 'form', type => 'select', label => 'فعّال', lov => $yn, seq => 100);
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
process(name => 'NEW_DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ':P10_ACCOUNT_ID IS NULL', code => <<'SQL');
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
    SELECT acc_level + 1 INTO l_lvl FROM accounts WHERE account_id = :P10_PARENT_ID;
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
ajax('SUGGEST', $suggest_ajax);
branch_self();
end_page();

# اقتراح رقم الحساب عند فتح "حساب فرعي": نستخدم نفس كود الاقتراح
{
  our $OUT;
  my $s = src('p10_suggest.sql');
  $s =~ s/;\s*\z/;/;
  $s =~ s/^DECLARE/DECLARE/;
  my $lit_block = main::txt($s);
  # استبدال العلامة داخل الكتلة المولّدة: الأسهل تشغيل الاقتراح كتلة متداخلة
  my $marker = main::lit('    __SUGGEST__');
  my $nested = join(",\n", map { main::lit("    $_") } split /\n/, $s);
  $OUT =~ s/\Q$marker\E/$nested/;
}

1;
