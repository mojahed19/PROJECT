# =====================================================================
#  pages_master.pl - Ø§ÙØµÙØ­Ø© Ø§ÙØ¹Ø§ÙØ© 0Ø Ø´Ø¬Ø±Ø© Ø§ÙØ­Ø³Ø§Ø¨Ø§Øª 10Ø ÙØµÙØ­Ø§Øª Ø§ÙØ¨ÙØ§ÙØ§Øª Ø§ÙØ£Ø³Ø§Ø³ÙØ© (ÙØ§Ø¦ÙØ© + ÙÙÙØ°Ø¬)
# =====================================================================
use strict;
use warnings;
use utf8;
our %LOV;
our %T;

# ---------------------------------------------------------------- 0 Ø§ÙØµÙØ­Ø© Ø§ÙØ¹Ø§ÙØ©
page(id => 0, name => 'Global Page', alias => 'GLOBAL');
# Ø±Ø£Ø³ ÙØ¸ÙØ± Ø¹ÙØ¯ Ø·Ø¨Ø§Ø¹Ø© Ø£Ù ØµÙØ­Ø© Ø£Ù ØªÙØ±ÙØ±: Ø§ÙØ´Ø¹Ø§Ø± ÙØ§Ø³Ù Ø§ÙØ´Ø±ÙØ© ÙØ¨ÙØ§ÙØ§ØªÙØ§
region(name => 'print_head', title => 'print', type => 'static', no_header => 1, template => 'reg_blank', seq => 1,
       cond => ":APP_PAGE_ID NOT IN (53, 54, 57, 82, 9999)", html => <<'HTML');
<div class="print-only-head">
  <img src="#APP_FILES#logo.jpg" alt="">
  <div><div class="nm">&G_COMPANY_NAME.</div><div class="inf">&G_COMPANY_INFO.</div></div>
</div>
HTML
end_page();

# ---------------------------------------------------------------- ÙÙÙÙØ¯ Ø§ÙÙØ§Ø¦ÙØ© + Ø§ÙÙÙÙØ°Ø¬
# cols: [COLUMN, label, type, lov, required, dtype]
sub crud {
  my %c = @_;
  my ($L, $F, $tbl) = ($c{list}, $c{form}, $c{table});
  my @cols = @{ $c{cols} };

  # ---------- ØµÙØ­Ø© Ø§ÙÙØ§Ø¦ÙØ©
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
  button(name => 'CREATE', region => 'ir', label => 'Ø¥Ø¶Ø§ÙØ©', hot => 1, position => 'RIGHT_OF_IR_SEARCH_BAR',
         url => "f?p=&APP_ID.:$F:&APP_SESSION.::&DEBUG.:$F\::");
  end_page();

  # ---------- ØµÙØ­Ø© Ø§ÙÙÙÙØ°Ø¬ (Modal)
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
  button(name => 'CANCEL', region => 'buttons', label => 'Ø¥ÙØºØ§Ø¡', position => 'CLOSE', js => 'apex.navigation.dialog.cancel(true);', seq => 10);
  button(name => 'DELETE', region => 'buttons', label => 'Ø­Ø°Ù', position => 'DELETE', seq => 20, dml => 'DELETE',
         if_not_null => "P${F}_ROWID", novalidate => 1, confirm => '&APP_TEXT$DELETE_MSG!RAW.');
  button(name => 'SAVE', region => 'buttons', label => 'Ø­ÙØ¸ Ø§ÙØªØ¹Ø¯ÙÙØ§Øª', position => 'NEXT', seq => 30, hot => 1, dml => 'UPDATE', if_not_null => "P${F}_ROWID");
  button(name => 'CREATE', region => 'buttons', label => 'Ø­ÙØ¸', position => 'NEXT', seq => 40, hot => 1, dml => 'INSERT', if_null => "P${F}_ROWID");
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
my $roles    = "SELECT 'Ø§ÙÙØ¯ÙØ± Ø§ÙØ¹Ø§Ù' d, 'GM' r FROM dual UNION ALL SELECT 'ÙØ­Ø§Ø³Ø¨', 'ACCOUNTANT' FROM dual UNION ALL SELECT 'ÙÙØ§Ø±Ø¯ Ø¨Ø´Ø±ÙØ©', 'HR' FROM dual UNION ALL SELECT 'Ø£ÙÙÙ ÙØ®Ø²Ù', 'STORE' FROM dual UNION ALL SELECT 'ÙØ§Ø´ÙØ±', 'CASHIER' FROM dual UNION ALL SELECT 'ÙØ³ØªØ®Ø¯Ù', 'USER' FROM dual";
my $settings = "SELECT code || ' - ' || n d, code r FROM (SELECT 'SALES' code, 'ÙØ¨ÙØ¹Ø§Øª ÙÙØ´Ø±ÙØ§Øª' n FROM dual UNION ALL SELECT 'SALES_RETURN', 'ÙØ±Ø¯ÙØ¯Ø§Øª Ø§ÙÙØ¨ÙØ¹Ø§Øª' FROM dual UNION ALL SELECT 'INTERCO_AP', 'ÙØ³ØªØ­Ù ÙÙØ´Ø±ÙØ© Ø§ÙØ£Ù' FROM dual UNION ALL SELECT 'PURCHASES', 'ÙØ§Ø±Ø¯ ÙÙ Ø§ÙØ£Ù (ÙØ®Ø²ÙÙ)' FROM dual UNION ALL SELECT 'INVENTORY', 'Ø§ÙÙØ®Ø²ÙÙ' FROM dual UNION ALL SELECT 'COGS', 'ØªÙÙÙØ© Ø§ÙÙØ¨ÙØ¹Ø§Øª' FROM dual UNION ALL SELECT 'INVENTORY_ADJ', 'ÙØ±ÙÙØ§Øª Ø§ÙØ¬Ø±Ø¯' FROM dual UNION ALL SELECT 'POS_SALES', 'ÙØ¨ÙØ¹Ø§Øª ÙÙØ§Ø· Ø§ÙØ¨ÙØ¹' FROM dual UNION ALL SELECT 'CASH_DIFF', 'Ø¹Ø¬Ø² ÙØ²ÙØ§Ø¯Ø© Ø§ÙØµÙØ§Ø¯ÙÙ' FROM dual UNION ALL SELECT 'SALARY_EXP', 'ÙØµØ±ÙÙ Ø§ÙØ±ÙØ§ØªØ¨' FROM dual UNION ALL SELECT 'INCENTIVE_EXP', 'ÙØµØ±ÙÙ Ø§ÙØ­ÙØ§ÙØ²' FROM dual UNION ALL SELECT 'SALARY_DIFF', 'ÙØ±ÙÙØ§Øª Ø§ÙØ±ÙØ§ØªØ¨' FROM dual UNION ALL SELECT 'SALARY_PAYABLE', 'Ø±ÙØ§ØªØ¨ ÙØ³ØªØ­ÙØ©' FROM dual UNION ALL SELECT 'DEDUCTIONS', 'Ø®ØµÙÙØ§Øª Ø§ÙÙÙØ¸ÙÙÙ' FROM dual)";

crud(list => 204, form => 205, title => 'Ø§ÙØ³ÙÙØ§Øª Ø§ÙÙØ§ÙÙØ©', table => 'fiscal_years', alias => 'FISCAL', auth => 'IS_GM', order => 't.fy_year DESC', cols => [
  ['FY_YEAR', 'Ø§ÙØ³ÙØ©', 'num', undef, 1], ['START_DATE', 'Ø§ÙØ¨Ø¯Ø§ÙØ©', 'date', undef, 1], ['END_DATE', 'Ø§ÙÙÙØ§ÙØ©', 'date', undef, 1],
  ['IS_CLOSED', 'ÙØºÙÙØ©', 'select', $yn, 1]]);

crud(list => 206, form => 207, title => 'Ø§ÙÙØ³ØªØ®Ø¯ÙÙÙ', table => 'app_users', alias => 'USERS', auth => 'IS_GM', order => 't.user_name', cols => [
  ['USER_NAME', 'Ø§Ø³Ù Ø§ÙØ¯Ø®ÙÙ (Ø¨Ø£Ø­Ø±Ù ÙØ¨ÙØ±Ø©)', 'text', undef, 1], ['FULL_NAME', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1],
  ['USER_ROLE', 'Ø§ÙØ¯ÙØ±', 'select', $roles, 1],
  ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1]],
  # ÙÙÙØ© Ø§ÙÙØ±ÙØ±: Ø­ÙÙ Ø®Ø§Ø±Ø¬ Ø§ÙØ¬Ø¯ÙÙØ ØªÙØ­ÙØ¸ ÙÙØ¬Ø²ÙØ£Ø© (SHA256) Ø¨Ø¹Ø¯ Ø§ÙØ­ÙØ¸
  extra => sub {
    my $F = shift;
    item(name => "P${F}_NEW_PASSWORD", region => 'form', type => 'password', seq => 200,
         label => 'ÙÙÙØ© Ø§ÙÙØ±ÙØ± (Ø§ØªØ±ÙÙØ§ ÙØ§Ø±ØºØ© ÙØ¹Ø¯Ù Ø§ÙØªØºÙÙØ±)');
    item(name => "P${F}_CONFIRM_PASSWORD", region => 'form', type => 'password', seq => 210, same_line => 1,
         label => 'ØªØ£ÙÙØ¯ ÙÙÙØ© Ø§ÙÙØ±ÙØ±');
    process(name => 'CHECK_PASSWORD', seq => 1, when_req => 'CREATE,SAVE', code => <<"SQL");
DECLARE l_err VARCHAR2(200);
BEGIN
  l_err := CASE
  WHEN :P${F}_ROWID IS NULL AND :P${F}_NEW_PASSWORD IS NULL THEN 'Ø£Ø¯Ø®Ù ÙÙÙØ© Ø§ÙÙØ±ÙØ± ÙÙÙØ³ØªØ®Ø¯Ù Ø§ÙØ¬Ø¯ÙØ¯'
  WHEN :P${F}_NEW_PASSWORD IS NOT NULL AND LENGTH(:P${F}_NEW_PASSWORD) < 6 THEN 'ÙÙÙØ© Ø§ÙÙØ±ÙØ± 6 Ø£Ø­Ø±Ù Ø¹ÙÙ Ø§ÙØ£ÙÙ'
  WHEN NVL(:P${F}_NEW_PASSWORD, '#') <> NVL(:P${F}_CONFIRM_PASSWORD, '#') THEN 'ÙÙÙØ© Ø§ÙÙØ±ÙØ± ÙØªØ£ÙÙØ¯ÙØ§ ØºÙØ± ÙØªØ·Ø§Ø¨ÙÙÙ'
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

crud(list => 208, form => 209, title => 'Ø§ÙØ­Ø³Ø§Ø¨Ø§Øª Ø§ÙØ§ÙØªØ±Ø§Ø¶ÙØ©', table => 'account_settings', alias => 'ACC-SETTINGS', auth => 'IS_GM', order => 't.setting_code', where => 't.company_id = :G_PARENT_ID', cols => [
  ['SETTING_CODE', 'Ø§ÙØ¥Ø¹Ø¯Ø§Ø¯', 'select', $settings, 1],
  ['ACCOUNT_ID', 'Ø§ÙØ­Ø³Ø§Ø¨', 'popup', $LOV{accounts4}, 1, 'NUMBER']]);

crud(list => 212, form => 213, title => 'Ø§ÙÙØ­Ø¯Ø§Øª', table => 'units', alias => 'UNITS', auth => 'IS_STORE', order => 't.name_ar', cols => [
  ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['NAME_EN', 'Ø§ÙØ§Ø³Ù Ø§ÙØ¥ÙØ¬ÙÙØ²Ù']]);

crud(list => 210, form => 211, title => 'Ø§ÙØ£ØµÙØ§Ù ÙØ£Ø³Ø¹Ø§Ø±ÙØ§', table => 'items', alias => 'ITEMS', auth => 'IS_STORE', order => 't.item_code', cols => [
  ['ITEM_CODE', 'Ø§ÙÙÙØ¯', 'text', undef, 1], ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['NAME_EN', 'Ø§ÙØ§Ø³Ù Ø§ÙØ¥ÙØ¬ÙÙØ²Ù'],
  ['BASE_UNIT_ID', 'Ø§ÙÙØ­Ø¯Ø© Ø§ÙØ£Ø³Ø§Ø³ÙØ©', 'select', $units, 1, 'NUMBER'], ['BARCODE', 'Ø§ÙØ¨Ø§Ø±ÙÙØ¯'],
  ['PURCHASE_PRICE', 'Ø³Ø¹Ø± Ø§ÙØ´Ø±Ø§Ø¡ (ÙÙÙØ­Ø¯Ø© Ø§ÙØ£Ø³Ø§Ø³ÙØ©)', 'num'], ['SALE_PRICE', 'Ø³Ø¹Ø± Ø§ÙØ¨ÙØ¹ (ÙÙÙØ­Ø¯Ø© Ø§ÙØ£Ø³Ø§Ø³ÙØ©)', 'num'],
  ['REORDER_LEVEL', 'Ø­Ø¯ Ø§ÙØ·ÙØ¨', 'num'], ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1]]);

crud(list => 236, form => 237, title => 'ÙØ­Ø¯Ø§Øª Ø§ÙØ£ØµÙØ§Ù', table => 'item_units', alias => 'ITEM-UNITS', auth => 'IS_STORE', order => 't.item_id, t.factor', cols => [
  ['ITEM_ID', 'Ø§ÙØµÙÙ', 'popup', $items, 1, 'NUMBER'], ['UNIT_ID', 'Ø§ÙÙØ­Ø¯Ø©', 'select', $units, 1, 'NUMBER'],
  ['FACTOR', 'Ø¹Ø¯Ø¯ Ø§ÙÙØ­Ø¯Ø§Øª Ø§ÙØ£Ø³Ø§Ø³ÙØ©', 'num', undef, 1], ['BARCODE', 'Ø§ÙØ¨Ø§Ø±ÙÙØ¯']]);

crud(list => 214, form => 215, title => 'ÙÙØ§Ø¦Ù Ø§ÙØ£Ø³Ø¹Ø§Ø±', table => 'price_lists', alias => 'PRICE-LISTS', auth => 'IS_GM', order => 't.name_ar', cols => [
  ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1]]);

crud(list => 234, form => 235, title => 'Ø£Ø³Ø¹Ø§Ø± Ø§ÙØ£ØµÙØ§Ù', table => 'price_list_items', alias => 'PRICES', auth => 'IS_GM', order => 't.price_list_id, t.item_id', cols => [
  ['PRICE_LIST_ID', 'ÙØ§Ø¦ÙØ© Ø§ÙØ£Ø³Ø¹Ø§Ø±', 'select', $pls, 1, 'NUMBER'], ['ITEM_ID', 'Ø§ÙØµÙÙ', 'popup', $items, 1, 'NUMBER'],
  ['UNIT_ID', 'Ø§ÙÙØ­Ø¯Ø©', 'select', $units, 1, 'NUMBER'], ['PRICE', 'Ø§ÙØ³Ø¹Ø±', 'num', undef, 1]]);

crud(list => 216, form => 217, title => 'Ø§ÙÙØ®Ø§Ø²Ù', table => 'warehouses', alias => 'WAREHOUSES', auth => 'IS_STORE', order => 't.company_id', cols => [
  ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1]]);

crud(list => 220, form => 221, title => 'Ø§ÙØ¯Ø±Ø¬Ø§Øª Ø§ÙÙØ¸ÙÙÙØ©', table => 'job_grades', alias => 'GRADES', auth => 'IS_HR', order => 't.grade_code', cols => [
  ['GRADE_CODE', 'Ø§ÙØ±ÙØ²', 'text', undef, 1], ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['BASIC_SALARY', 'Ø§ÙØ±Ø§ØªØ¨ Ø§ÙØ£Ø³Ø§Ø³Ù', 'num', undef, 1]]);

crud(list => 222, form => 223, title => 'Ø§ÙÙÙØ¸ÙÙÙ', table => 'employees', alias => 'EMPLOYEES', auth => 'IS_HR', order => 't.emp_no', cols => [
  ['EMP_NO', 'Ø§ÙØ±ÙÙ', 'text', undef, 1], ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1],
  ['GRADE_ID', 'Ø§ÙØ¯Ø±Ø¬Ø©', 'select', $grades, 1, 'NUMBER'],
  ['HIRE_DATE', 'ØªØ§Ø±ÙØ® Ø§ÙØªØ¹ÙÙÙ', 'date'], ['BASIC_SALARY', 'Ø£Ø³Ø§Ø³Ù Ø®Ø§Øµ (ÙØ§Ø±Øº = Ø£Ø³Ø§Ø³Ù Ø§ÙØ¯Ø±Ø¬Ø©)', 'num'],
  ['BANK_ACCOUNT', 'Ø§ÙØ­Ø³Ø§Ø¨ Ø§ÙØ¨ÙÙÙ'], ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1]]);

crud(list => 224, form => 225, title => 'Ø¨ÙÙØ¯ Ø§ÙØ¹ÙØ§ÙØ§Øª ÙØ§ÙØ­ÙØ§ÙØ² ÙØ§ÙØ®ØµÙÙØ§Øª', table => 'allowance_types', alias => 'ALLOWANCES', auth => 'IS_HR', order => 't.code', cols => [
  ['CODE', 'Ø§ÙØ±ÙØ²', 'text', undef, 1], ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1],
  ['KIND', 'Ø§ÙÙÙØ¹', 'select', "SELECT 'Ø¹ÙØ§ÙØ©' d, 'ALLOWANCE' r FROM dual UNION ALL SELECT 'Ø­Ø§ÙØ²', 'INCENTIVE' FROM dual UNION ALL SELECT 'Ø®ØµÙ', 'DEDUCTION' FROM dual", 1],
  ['CALC_METHOD', 'Ø·Ø±ÙÙØ© Ø§ÙØ­Ø³Ø§Ø¨', 'select', "SELECT 'ÙØ¨ÙØº Ø«Ø§Ø¨Øª' d, 'FIXED' r FROM dual UNION ALL SELECT 'ÙØ³Ø¨Ø© ÙÙ Ø§ÙØ£Ø³Ø§Ø³Ù', 'PERCENT' FROM dual", 1],
  ['ACCOUNT_ID', 'Ø§ÙØ­Ø³Ø§Ø¨ (Ø§Ø®ØªÙØ§Ø±Ù)', 'popup', $LOV{accounts4}, undef, 'NUMBER']]);

crud(list => 226, form => 227, title => 'Ø¹ÙØ§ÙØ§Øª Ø§ÙØ¯Ø±Ø¬Ø§Øª', table => 'grade_allowances', alias => 'GRADE-ALLOW', auth => 'IS_HR', order => 't.grade_id', cols => [
  ['GRADE_ID', 'Ø§ÙØ¯Ø±Ø¬Ø©', 'select', $grades, 1, 'NUMBER'], ['ALLOWANCE_ID', 'Ø§ÙØ¨ÙØ¯', 'select', $allows, 1, 'NUMBER'], ['VALUE', 'Ø§ÙÙÙÙØ©', 'num', undef, 1]]);

crud(list => 228, form => 229, title => 'Ø¹ÙØ§ÙØ§Øª Ø§ÙÙÙØ¸ÙÙÙ Ø§ÙØ®Ø§ØµØ©', table => 'emp_allowances', alias => 'EMP-ALLOW', auth => 'IS_HR', order => 't.employee_id', cols => [
  ['EMPLOYEE_ID', 'Ø§ÙÙÙØ¸Ù', 'popup', $emps, 1, 'NUMBER'], ['ALLOWANCE_ID', 'Ø§ÙØ¨ÙØ¯', 'select', $allows, 1, 'NUMBER'],
  ['VALUE', 'Ø§ÙÙÙÙØ©', 'num', undef, 1], ['FROM_DATE', 'ÙÙ ØªØ§Ø±ÙØ®', 'date'], ['TO_DATE', 'Ø¥ÙÙ ØªØ§Ø±ÙØ®', 'date']]);

crud(list => 20, form => 21, title => 'Ø£ÙÙØ§Ø¹ Ø§ÙÙÙÙØ¯', table => 'journal_types', alias => 'JOURNAL-TYPES', auth => 'IS_ACCOUNTANT', order => 't.sort_order', cols => [
  ['JT_CODE', 'Ø§ÙØ±ÙØ²', 'text', undef, 1], ['NAME_AR', 'Ø§ÙØ§Ø³Ù', 'text', undef, 1], ['NAME_EN', 'Ø§ÙØ§Ø³Ù Ø§ÙØ¥ÙØ¬ÙÙØ²Ù'],
  ['PREFIX', 'Ø§ÙØ¨Ø§Ø¯Ø¦Ø©', 'text', undef, 1], ['MANUAL_ALLOWED', 'ÙÙØ¯Ø®Ù ÙØ¯ÙÙØ§Ù', 'select', $yn, 1],
  ['IS_ACTIVE', 'ÙØ¹ÙØ§Ù', 'select', $yn, 1], ['SORT_ORDER', 'Ø§ÙØªØ±ØªÙØ¨', 'num']]);

# =====================================================================
# 10 Ø´Ø¬Ø±Ø© Ø§ÙØ­Ø³Ø§Ø¨Ø§Øª
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
      htp.p('<li><details' || ' open' || '><summary>' || l_lbl || '</summary><ul>');
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

page(id => 10, name => 'Ø´Ø¬Ø±Ø© Ø§ÙØ­Ø³Ø§Ø¨Ø§Øª', alias => 'ACCOUNTS', auth => 'IS_ACCOUNTANT', onload => $acc_js, css => <<'CSS');
.acc-tree, .acc-tree ul { list-style: none; margin: 0; padding-inline-start: 18px; }
.acc-tree > li { margin: 2px 0; }
.acc-tree summary { cursor: pointer; }
.acc-tree a { text-decoration: none; padding: 2px 4px; border-radius: 3px; display: inline-block; }
.acc-tree a.sel { background: var(--ut-palette-primary, #0572ce); color: #fff; }
CSS
region(name => 'tree', title => 'Ø´Ø¬Ø±Ø© Ø§ÙØ­Ø³Ø§Ø¨Ø§Øª', type => 'plsql', plsql => $tree, seq => 10, span => 5);
region(name => 'form', title => 'Ø¨ÙØ§ÙØ§Øª Ø§ÙØ­Ø³Ø§Ø¨', type => 'static', seq => 20, span => 7, same_row => 1,
       html => '<div style="margin-bottom:8px">Ø§ÙÙØ³ØªÙÙ: <b id="acc_level">&P10_ACC_LEVEL.</b> (Ø§ÙØ­Ø³Ø§Ø¨ Ø§ÙØªØ­ÙÙÙÙ ÙÙ Ø§ÙÙØ³ØªÙÙ 4 ÙÙØ· ÙÙØ¨Ù Ø§ÙÙÙÙØ¯)</div>');
item(name => 'P10_ACCOUNT_ID', region => 'form', type => 'hidden', seq => 1);
item(name => 'P10_ACC_LEVEL', region => 'form', type => 'hidden', seq => 2);
item(name => 'P10_PARENT_ID', region => 'form', type => 'popup', label => 'Ø§ÙØ­Ø³Ø§Ø¨ Ø§ÙØ£Ø¨ (ÙØ§Ø±Øº = Ø­Ø³Ø§Ø¨ Ø±Ø¦ÙØ³Ù)', seq => 10,
     lov => "SELECT LPAD(' ', (acc_level - 1) * 3) || account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE acc_level < 4 ORDER BY account_code");
item(name => 'P10_ACCOUNT_CODE', region => 'form', label => 'Ø±ÙÙ Ø§ÙØ­Ø³Ø§Ø¨', seq => 20, required => 1);
item(name => 'P10_NAME_AR', region => 'form', label => 'Ø§ÙØ§Ø³Ù', seq => 30, same_line => 1, required => 1);
item(name => 'P10_NAME_EN', region => 'form', label => 'Ø§ÙØ§Ø³Ù Ø§ÙØ¥ÙØ¬ÙÙØ²Ù', seq => 40);
item(name => 'P10_ACC_TYPE', region => 'form', type => 'select', label => 'Ø§ÙÙÙØ¹', seq => 50, same_line => 1, required => 1,
     lov => "SELECT 'Ø£ØµÙÙ' d, 'ASSET' r FROM dual UNION ALL SELECT 'Ø®ØµÙÙ', 'LIAB' FROM dual UNION ALL SELECT 'Ø­ÙÙÙ ÙÙÙÙØ©', 'EQUITY' FROM dual UNION ALL SELECT 'Ø¥ÙØ±Ø§Ø¯Ø§Øª', 'REV' FROM dual UNION ALL SELECT 'ÙØµØ±ÙÙØ§Øª', 'EXP' FROM dual");
item(name => 'P10_NATURE', region => 'form', type => 'select', label => 'Ø§ÙØ·Ø¨ÙØ¹Ø©', seq => 60, required => 1,
     lov => "SELECT 'ÙØ¯ÙÙ' d, 'D' r FROM dual UNION ALL SELECT 'Ø¯Ø§Ø¦Ù', 'C' FROM dual");
item(name => 'P10_CASH_BANK', region => 'form', type => 'select', label => 'ØµÙØ¯ÙÙ / Ø¨ÙÙ (Ø§ÙÙØ³ØªÙÙ 4 ÙÙØ·)', seq => 70, same_line => 1,
     lov => "SELECT 'ÙØ§' d, 'N' r FROM dual UNION ALL SELECT 'ØµÙØ¯ÙÙ', 'C' FROM dual UNION ALL SELECT 'Ø¨ÙÙ', 'B' FROM dual");
item(name => 'P10_CURRENCY_CODE', region => 'form', type => 'select', label => 'Ø¹ÙÙØ© Ø§ÙØ­Ø³Ø§Ø¨', lov => $LOV{currencies}, null => 'Ø£Ù Ø¹ÙÙØ©', seq => 80);
item(name => 'P10_COMPANY_ID', region => 'form', type => 'select', label => 'Ø§ÙØ´Ø±ÙØ©', lov => $LOV{all_companies}, null => 'ÙØ´ØªØ±Ù ÙÙÙ Ø§ÙØ´Ø±ÙØ§Øª', seq => 90, same_line => 1);
item(name => 'P10_IS_ACTIVE', region => 'form', type => 'select', label => 'ÙØ¹ÙØ§Ù', lov => $yn, seq => 100);
button(name => 'SAVE', region => 'form', label => 'Ø­ÙØ¸', hot => 1, seq => 10);
button(name => 'DELETE', region => 'form', label => 'Ø­Ø°Ù', position => 'PREVIOUS', seq => 20, if_not_null => 'P10_ACCOUNT_ID', novalidate => 1, confirm => 'Ø­Ø°Ù Ø§ÙØ­Ø³Ø§Ø¨Ø');
button(name => 'NEW', region => 'form', label => 'Ø¬Ø¯ÙØ¯', position => 'PREVIOUS', seq => 30, url => 'f?p=&APP_ID.:10:&SESSION.::&DEBUG.:10::');
button(name => 'CHILD', region => 'form', label => 'Ø­Ø³Ø§Ø¨ ÙØ±Ø¹Ù', position => 'PREVIOUS', seq => 40,
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
process(name => 'SAVE_ACCOUNT', seq => 60, button => 'SAVE', success => 'ØªÙ Ø­ÙØ¸ Ø§ÙØ­Ø³Ø§Ø¨', code => <<'SQL');
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
process(name => 'DELETE_ACCOUNT', seq => 70, button => 'DELETE', success => 'ØªÙ Ø­Ø°Ù Ø§ÙØ­Ø³Ø§Ø¨', code => <<'SQL');
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
       DECODE(a.cash_bank,'C','صندوق','B','بنك') AS "صندوق / بنك",
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

1;
