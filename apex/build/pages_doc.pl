# =====================================================================
#  pages_doc.pl - صفحات المستندات والتقارير
# =====================================================================
use strict;
use warnings;
use utf8;

our %LOV = (
  companies  => "SELECT name_ar d, company_id r FROM companies c WHERE is_active = 'Y' AND (:G_USER_ROLE = 'ADMIN' OR company_id = :G_COMPANY_ID OR EXISTS (SELECT 1 FROM user_companies u WHERE u.user_name = UPPER(:APP_USER) AND u.company_id = c.company_id)) ORDER BY is_parent DESC, company_code",
  all_companies => "SELECT name_ar d, company_id r FROM companies WHERE is_active = 'Y' ORDER BY is_parent DESC, company_code",
  subs       => "SELECT name_ar d, company_id r FROM companies WHERE is_parent = 'N' AND is_active = 'Y' ORDER BY company_code",
  currencies => "SELECT currency_code || ' - ' || name_ar d, currency_code r FROM currencies WHERE is_active = 'Y' ORDER BY is_base DESC, currency_code",
  jt_manual  => "SELECT name_ar d, jt_code r FROM journal_types WHERE (manual_allowed = 'Y' AND is_active = 'Y') OR jt_code = :P30_JT_CODE ORDER BY sort_order",
  periods    => "SELECT TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYY-MM') d, TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYYMM') r FROM dual CONNECT BY LEVEL <= 13",
  years      => "SELECT fy_year d, fy_year r FROM fiscal_years ORDER BY 1 DESC",
  warehouses => "SELECT c.name_ar || ' / ' || w.name_ar d, w.warehouse_id r FROM warehouses w JOIN companies c ON c.company_id = w.company_id WHERE w.is_active = 'Y' AND (:G_USER_ROLE = 'ADMIN' OR w.company_id = :G_COMPANY_ID) ORDER BY c.company_code, w.name_ar",
  accounts4  => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_postable = 'Y' AND is_active = 'Y' ORDER BY account_code",
  accounts_all => "SELECT LPAD(' ', (acc_level - 1) * 3) || account_code || ' - ' || name_ar d, account_id r FROM accounts ORDER BY account_code",
  cash       => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE cash_bank IN ('C','B') AND is_active = 'Y' ORDER BY account_code",
  yn         => "SELECT 'نعم' d, 'Y' r FROM dual UNION ALL SELECT 'لا', 'N' FROM dual",
  wf_status  => "SELECT 'مسودة' d, 'DRAFT' r FROM dual UNION ALL SELECT 'معاد للمدخل', 'RETURNED' FROM dual UNION ALL SELECT 'مُراجَع', 'REVIEWED' FROM dual UNION ALL SELECT 'معتمد', 'APPROVED' FROM dual UNION ALL SELECT 'مرحّل', 'POSTED' FROM dual UNION ALL SELECT 'معكوس', 'REVERSED' FROM dual",
  accounts_party => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_postable = 'Y' AND is_active = 'Y' AND cash_bank = 'N' ORDER BY account_code",
);

# الحقول تُقفل إذا لم يكن للمستخدم حق التعديل (المدخل/مدير النظام في حالة مسودة أو معاد للمدخل)
my $SAVE_KEYS = "if (apex.item('%1\$s').getValue() && !DocUtil.canEdit(apex.item('%1\$s').getValue())) { %4\$s.forEach(function (n) { apex.item(n).disable(); }); }";

sub doc_status_html {
  my ($no_item, $status_item, $no_label, $pfx) = @_;
  my $extra = $pfx ? "<span class=\"doc-wf\">&${pfx}_WF_INFO.</span><span class=\"doc-note\">&${pfx}_RETURN_NOTE.</span>" : '';
  return "<div class=\"doc-meta\" style=\"margin:4px 0 10px\">$no_label: <b id=\"doc_no\">&$no_item.</b> &nbsp;&nbsp; الحالة: "
       . "<span class=\"doc-status doc-status--&$status_item.\">&$status_item.</span>$extra</div>";
}

# عبارة PL/SQL تملأ معلومات المراجعة/الاعتماد وسبب الإعادة عند تحميل المستند (r = سجل المستند)
sub wf_load {
  my $p = shift;
  return ":${p}_RETURN_NOTE := CASE WHEN r.status IN ('RETURNED','DRAFT') THEN r.return_note END;\n"
       . ":${p}_WF_INFO := TRIM(CASE WHEN r.reviewed_by IS NOT NULL THEN 'راجعه ' || r.reviewed_by || ' ' || TO_CHAR(r.reviewed_on, 'DD/MM/YYYY HH24:MI') END"
       . " || CASE WHEN r.approved_by IS NOT NULL THEN ' - اعتمده ' || r.approved_by || ' ' || TO_CHAR(r.approved_on, 'DD/MM/YYYY HH24:MI') END);";
}

# أزرار وعملية دورة المستند (مراجعة / اعتماد / إعادة / ترحيل)
#   page, region, table, idcol, id (عنصر المعرّف), status (عنصر الحالة), doc, post (كود الترحيل أو undef)
sub wf_setup {
  my %a = @_;
  my $p = "P$a{page}";
  item(name => "${p}_WF_NOTE",     region => $a{region}, type => 'hidden', seq => 97);
  item(name => "${p}_WF_INFO",     region => $a{region}, type => 'hidden', seq => 98);
  item(name => "${p}_RETURN_NOTE", region => $a{region}, type => 'hidden', seq => 99);
  my ($id, $st) = (":$a{id} IS NOT NULL" . ($a{extra} ? " AND $a{extra}" : ''), ":$a{status}");
  my $r = sub { "$id AND :G_USER_ROLE IN ('ADMIN','$_[0]')" };
  button(name => 'WF_REVIEW',    region => $a{region}, label => 'مراجعة', js => "DocUtil.wf('REVIEW');", hot => 1, seq => 61,
         cond => $r->('REVIEWER') . " AND $st = 'DRAFT'");
  button(name => 'WF_UNREVIEW',  region => $a{region}, label => 'إلغاء المراجعة', js => "DocUtil.wf('UNREVIEW');", seq => 62,
         cond => $r->('REVIEWER') . " AND $st = 'REVIEWED'");
  button(name => 'WF_APPROVE',   region => $a{region}, label => 'اعتماد', js => "DocUtil.wf('APPROVE');", hot => 1, seq => 63,
         cond => $r->('APPROVER') . " AND $st = 'REVIEWED'");
  # المستند الذي يُرحّل عند الاعتماد لا يُلغى اعتماده (التصحيح بالعكس من المعتمد)
  button(name => 'WF_UNAPPROVE', region => $a{region}, label => 'إلغاء الاعتماد', js => "DocUtil.wf('UNAPPROVE');", seq => 64,
         cond => $r->('APPROVER') . " AND $st = 'APPROVED'") unless $a{post};
  button(name => 'WF_RETURN',    region => $a{region}, label => 'إعادة للمدخل', js => "DocUtil.wf('RETURN');", seq => 65,
         cond => "$id AND ((:G_USER_ROLE IN ('ADMIN','REVIEWER') AND $st IN ('DRAFT','REVIEWED')) OR (:G_USER_ROLE IN ('ADMIN','APPROVER') AND $st IN ('REVIEWED','APPROVED')))");
  my $code = src('wf_action.sql');
  my %rep = (__ITEM__ => $a{id}, __NOTE__ => "${p}_WF_NOTE", __TABLE__ => $a{table}, __IDCOL__ => $a{idcol},
             __DOC__ => $a{doc}, __CANPOST__ => ($a{post} ? 'Y' : 'N'), __POST__ => ($a{post} // 'NULL;'),
             __PRECHECK__ => ($a{precheck} // 'NULL;'));
  for my $k (keys %rep) { my $v = $rep{$k}; $code =~ s/\Q$k\E/$v/g; }
  process(name => 'WORKFLOW', seq => 50, when_req => 'REVIEW,UNREVIEW,APPROVE,UNAPPROVE,RETURN,POST', code => $code);
}

# مصدر تحميل مستند مع معلومات دورة المراجعة
sub src_wf { my ($f, $p) = @_; my $c = src($f); my $w = wf_load($p); $c =~ s/__WF__/$w/; return $c }

# شرط إظهار زر الحفظ: المدخل أو مدير النظام والمستند جديد أو مسودة أو معاد للمدخل
# مصدر يحتوي دالة التفقيط
sub src_t { my $c = src(shift); my $t = src('tafqeet.sql'); $c =~ s/__TAFQEET__/$t/; return $c }

sub can_save { my $st = shift; return ":G_USER_ROLE IN ('ADMIN','ENTRY') AND (:$st IS NULL OR :$st IN ('DRAFT','RETURNED'))" }

sub date_default { my $i = shift; return "IF :$i IS NULL THEN :$i := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;" }
sub base_cur_default {
  my ($cur, $rate) = @_;
  return "IF :$cur IS NULL THEN SELECT currency_code INTO :$cur FROM currencies WHERE is_base = 'Y'; :$rate := 1; END IF;";
}

# =====================================================================
# 30 قيد اليومية + 31 القائمة
# =====================================================================
page(id => 30, name => 'قيد يومية', alias => 'JOURNAL', auth => 'IS_ACCOUNTANT',
     js => src('p30.js'),
     onload => "jv.init();\n" . sprintf($SAVE_KEYS, 'P30_STATUS', 'P30_STATUS', 'DRAFT',
       "['P30_COMPANY_ID','P30_JT_CODE','P30_JOURNAL_DATE','P30_CURRENCY_CODE','P30_EXCHANGE_RATE','P30_REF_NO','P30_DESCRIPTION']", ) );
region(name => 'head', title => 'رأس القيد', type => 'static', html => doc_status_html('P30_JOURNAL_NO', 'P30_STATUS', 'رقم القيد', 'P30'));
item(name => 'P30_JOURNAL_ID', region => 'head', type => 'hidden', seq => 1);
item(name => 'P30_JOURNAL_NO', region => 'head', type => 'hidden', seq => 2);
item(name => 'P30_STATUS',     region => 'head', type => 'hidden', seq => 3);
item(name => 'P30_SOURCE_TYPE',region => 'head', type => 'hidden', seq => 4);
item(name => 'P30_COMPANY_ID', region => 'head', type => 'select', label => 'الشركة', lov => $LOV{companies}, seq => 10, required => 1);
item(name => 'P30_JT_CODE',    region => 'head', type => 'select', label => 'نوع القيد', lov => $LOV{jt_manual}, extra => 1, seq => 30, same_line => 1, required => 1);
item(name => 'P30_JOURNAL_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P30_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 50, required => 1);
item(name => 'P30_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 60, same_line => 1);
item(name => 'P30_REF_NO',     region => 'head', type => 'hidden', protected => 1, no_checksum => 1, seq => 70);   # أخفاه المستخدم
item(name => 'P30_DESCRIPTION', region => 'head', label => 'البيان', seq => 80, same_line => 1, max => 500);
region(name => 'lines', title => 'سطور القيد', type => 'static', seq => 20,
       html => "<div id=\"jv_lines\"></div>\n<div style=\"margin-top:8px\">الفرق: <span id=\"jv_diff\" class=\"jv-diff ok\">0.00</span></div>");
my $draft = can_save('P30_STATUS') . " AND NVL(:P30_SOURCE_TYPE, 'MANUAL') IN ('MANUAL','CHEQUE')";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ (Ctrl+S)', js => "jv.save('DRAFT');", hot => 1, seq => 10, cond => $draft);
button(name => 'DELETE_DOC', region => 'lines', label => 'حذف', js => 'jv.remove();', position => 'PREVIOUS', seq => 30,
       cond => ":P30_JOURNAL_ID IS NOT NULL AND " . can_save('P30_STATUS') . " AND NVL(:P30_SOURCE_TYPE, 'MANUAL') = 'MANUAL'");
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30::', position => 'PREVIOUS', seq => 40);
button(name => 'PRINT', region => 'lines', label => 'طباعة', position => 'PREVIOUS', seq => 45, if_not_null => 'P30_JOURNAL_ID',
       js => "window.open(apex.util.makeApplicationUrl({pageId: 32, itemNames: ['P32_JOURNAL_ID'], itemValues: [apex.item('P30_JOURNAL_ID').getValue()]}), '_blank');");
button(name => 'REVERSE', region => 'lines', label => 'عكس القيد', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P30_JOURNAL_ID.',
       position => 'PREVIOUS', seq => 50, cond => ":P30_STATUS = 'POSTED' AND :G_USER_ROLE IN ('ADMIN','APPROVER')");
wf_setup(page => 30, region => 'lines', table => 'journals', idcol => 'journal_id', id => 'P30_JOURNAL_ID',
         status => 'P30_STATUS', doc => 'JOURNAL', extra => "NVL(:P30_SOURCE_TYPE, 'MANUAL') IN ('MANUAL','CHEQUE')", post => <<'PLSQL');
UPDATE journals SET posted_by = :APP_USER, posted_on = SYSDATE WHERE journal_id = l_id;
PLSQL
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p30_load.sql', 'P30'), cond => ':P30_JOURNAL_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ':P30_JOURNAL_ID IS NULL', code => join("\n",
  'IF :P30_COMPANY_ID IS NULL THEN :P30_COMPANY_ID := :G_COMPANY_ID; END IF;',
  "IF :P30_JT_CODE IS NULL THEN :P30_JT_CODE := 'JV'; END IF;", "IF :P30_STATUS IS NULL THEN :P30_STATUS := 'DRAFT'; END IF;",
  date_default('P30_JOURNAL_DATE'), base_cur_default('P30_CURRENCY_CODE', 'P30_EXCHANGE_RATE')));
ajax('INIT_DATA', src('p30_init.sql'));
ajax('SAVE_DOC',  src('p30_save.sql'));
ajax('DELETE_DOC', src('p30_delete.sql'));
branch_self('P30_JOURNAL_ID');
end_page();

page(id => 31, name => 'قائمة القيود', alias => 'JOURNALS', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P31_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات', submit => 1);
item(name => 'P31_FROM', region => 'f', type => 'date', label => 'من', seq => 20, same_line => 1);
item(name => 'P31_TO',   region => 'f', type => 'date', label => 'إلى', seq => 30, same_line => 1);
button(name => 'GO', region => 'f', label => 'عرض', seq => 10, hot => 1);
region(name => 'ir', title => 'القيود', type => 'ir', sql => src('p31_ir.sql'), seq => 10,
       links => { 'رقم القيد' => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:#JOURNAL_ID#' });
branch_self('P31_COMPANY_ID', 'P31_FROM', 'P31_TO');
end_page();

# =====================================================================
# 40 إذن توريد / صرف نقدي (الحساب المقابل والمبلغ والبيان في الرأس) + 41 القائمة
# =====================================================================
# رقم المستند المتوقع (يظهر عند الضغط على "جديد") - كله أرقام: النوع + السنة + 5 خانات
sub next_no_sql {
  my ($id_item, $no_item, $code_expr, $date_item) = @_;
  my $y = "EXTRACT(YEAR FROM NVL(TO_DATE(:$date_item, 'DD/MM/YYYY'), SYSDATE))";
  return "IF :$id_item IS NULL THEN\n"
       . "  SELECT $code_expr || $y || LPAD(NVL(MAX(last_no), 0) + 1, 5, '0') INTO :$no_item FROM doc_sequences\n"
       . "  WHERE company_id = NVL(:G_COMPANY_ID, :G_PARENT_ID) AND doc_type = $code_expr AND fy_year = $y;\n"
       . "END IF;";
}
my $print_js = sub {
  my ($page, $item, $src) = @_;
  return "window.open(apex.util.makeApplicationUrl({pageId: $page, itemNames: ['$item'], itemValues: [apex.item('$src').getValue()]}), '_blank');";
};

page(id => 40, name => 'إذن نقدي', alias => 'VOUCHER', title => '&P40_TITLE.', auth => 'IS_ACCOUNTANT',
     onload => "EnterNav.first('#main');\n" . sprintf($SAVE_KEYS, 'P40_STATUS', '', '',
       "['P40_VOUCHER_DATE','P40_CASH_ACCOUNT_ID','P40_COUNTER_ACCOUNT_ID','P40_AMOUNT','P40_PARTY_NAME','P40_DESCRIPTION']"));
region(name => 'head', title => '&P40_TITLE.', type => 'static', html => doc_status_html('P40_VOUCHER_NO', 'P40_STATUS', 'رقم الإذن', 'P40'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1])
  for (['P40_VOUCHER_ID',1],['P40_VOUCHER_TYPE',2],['P40_VOUCHER_NO',3],['P40_STATUS',4],['P40_JOURNAL_ID',5],['P40_TITLE',6]);
item(name => 'P40_VOUCHER_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, required => 1);
item(name => 'P40_CASH_ACCOUNT_ID', region => 'head', type => 'select', label => 'الخزينة', lov => $LOV{cash}, null => 1, seq => 30, same_line => 1, required => 1);
item(name => 'P40_COUNTER_ACCOUNT_ID', region => 'head', type => 'popup', label => 'الحساب المقابل', lov => $LOV{accounts4}, seq => 40, same_line => 1, required => 1);
item(name => 'P40_AMOUNT', region => 'head', label => 'المبلغ', seq => 50, required => 1);
item(name => 'P40_PARTY_NAME', region => 'head', label => '&P40_PARTY_LABEL.', seq => 60, same_line => 1);
item(name => 'P40_PARTY_LABEL', region => 'head', type => 'hidden', seq => 7);
item(name => 'P40_DESCRIPTION', region => 'head', label => 'البيان', seq => 70, same_line => 1, max => 500, required => 1);
button(name => 'SAVE', region => 'head', label => 'حفظ', hot => 1, seq => 10, cond => can_save('P40_STATUS'));
button(name => 'NEW', region => 'head', label => 'جديد', url => 'f?p=&APP_ID.:40:&SESSION.::&DEBUG.:40:P40_VOUCHER_TYPE:&P40_VOUCHER_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'PRINT', region => 'head', label => 'طباعة', position => 'PREVIOUS', seq => 35, if_not_null => 'P40_VOUCHER_ID',
       js => $print_js->(42, 'P42_VOUCHER_ID', 'P40_VOUCHER_ID'));
button(name => 'SHOW_JV', region => 'head', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P40_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P40_STATUS IN ('POSTED','REVERSED')");
button(name => 'REVERSE', region => 'head', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P40_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P40_STATUS = 'POSTED' AND :G_USER_ROLE IN ('ADMIN','APPROVER')");
wf_setup(page => 40, region => 'head', table => 'vouchers', idcol => 'voucher_id', id => 'P40_VOUCHER_ID',
         status => 'P40_STATUS', doc => 'VOUCHER', post => src('voucher_post.sql'));
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p40_load.sql', 'P40'), cond => ':P40_VOUCHER_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P40_VOUCHER_TYPE IS NULL OR :P40_VOUCHER_TYPE NOT IN ('R','P') THEN :P40_VOUCHER_TYPE := 'R'; END IF;",
  "IF :P40_VOUCHER_ID IS NULL THEN",
  "  :P40_STATUS := NULL;",
  '  ' . date_default('P40_VOUCHER_DATE'),
  'END IF;',
  next_no_sql('P40_VOUCHER_ID', 'P40_VOUCHER_NO', "CASE :P40_VOUCHER_TYPE WHEN 'R' THEN '11' ELSE '12' END", 'P40_VOUCHER_DATE'),
  ":P40_TITLE := CASE :P40_VOUCHER_TYPE WHEN 'R' THEN 'إذن توريد نقدي' ELSE 'إذن صرف نقدي' END;",
  ":P40_PARTY_LABEL := CASE :P40_VOUCHER_TYPE WHEN 'R' THEN 'استلمنا من' ELSE 'صرفنا إلى' END;"));
process(name => 'SAVE_DOC', seq => 10, button => 'SAVE', code => src('p40_save.sql'));
branch_self('P40_VOUCHER_ID', 'P40_VOUCHER_TYPE');
end_page();

page(id => 41, name => 'قائمة الأذونات النقدية', alias => 'VOUCHERS', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P41_TYPE', region => 'f', type => 'select', label => 'النوع', null => 'الكل', submit => 1,
     lov => "SELECT 'توريد نقدي' d, 'R' r FROM dual UNION ALL SELECT 'صرف نقدي', 'P' FROM dual");
item(name => 'P41_STATUS', region => 'f', type => 'select', label => 'الحالة', null => 'الكل', submit => 1, seq => 20, same_line => 1, lov => $LOV{wf_status});
region(name => 'ir', title => 'الأذونات النقدية', type => 'ir', sql => src('p41_ir.sql'), seq => 10, hide => ['VOUCHER_TYPE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:40:&SESSION.::&DEBUG.:40:P40_VOUCHER_ID,P40_VOUCHER_TYPE:#VOUCHER_ID#,#VOUCHER_TYPE#' });
branch_self('P41_TYPE', 'P41_STATUS');   # الفلاتر تبقى بعد اختيارها
end_page();

# =====================================================================
# 45 إذن توريد / صرف شيكات (عدة شيكات بتواريخ استحقاق) + 46 القائمة
# =====================================================================
page(id => 45, name => 'إذن شيكات', alias => 'CHEQUE-VOUCHER', title => '&P45_TITLE.', auth => 'IS_ACCOUNTANT',
     js => src('p45.js'),
     onload => "chq.init();\n" . sprintf($SAVE_KEYS, 'P45_STATUS', '', '',
       "['P45_VOUCHER_DATE','P45_BANK_ACCOUNT_ID','P45_COUNTER_ACCOUNT_ID','P45_PARTY_NAME','P45_DESCRIPTION']"));
region(name => 'head', title => '&P45_TITLE.', type => 'static', html => doc_status_html('P45_VOUCHER_NO', 'P45_STATUS', 'رقم الإذن', 'P45'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1])
  for (['P45_VOUCHER_ID',1],['P45_VOUCHER_TYPE',2],['P45_VOUCHER_NO',3],['P45_STATUS',4],['P45_JOURNAL_ID',5],['P45_TITLE',6],['P45_TOTAL',7],['P45_CHQ_COUNT',8]);
item(name => 'P45_VOUCHER_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, required => 1);
item(name => 'P45_BANK_ACCOUNT_ID', region => 'head', type => 'select', label => '&P45_BANK_LABEL.', null => 1, seq => 25, same_line => 1, required => 1,
     lov => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE cash_bank = 'B' AND is_active = 'Y' ORDER BY account_code");
item(name => 'P45_BANK_LABEL', region => 'head', type => 'hidden', seq => 10);
item(name => 'P45_COUNTER_ACCOUNT_ID', region => 'head', type => 'popup', label => '&P45_ACC_LABEL.', lov => $LOV{accounts_party}, seq => 30, required => 1);
item(name => 'P45_ACC_LABEL', region => 'head', type => 'hidden', seq => 8);
item(name => 'P45_PARTY_LABEL', region => 'head', type => 'hidden', seq => 9);
item(name => 'P45_PARTY_NAME', region => 'head', label => '&P45_PARTY_LABEL.', seq => 40, same_line => 1, required => 1);
item(name => 'P45_DESCRIPTION', region => 'head', label => 'البيان', seq => 50, same_line => 1, max => 500, required => 1);
region(name => 'lines', title => 'الشيكات', type => 'static', seq => 20,
       html => "<div id=\"chq_lines\"></div>\n<div style=\"margin-top:8px\"><b>إجمالي الشيكات:</b> <span id=\"chq_total\">0.00</span></div>");
button(name => 'SAVE', region => 'lines', label => 'حفظ (Ctrl+S)', js => 'chq.save();', hot => 1, seq => 10, cond => can_save('P45_STATUS'));
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:45:&SESSION.::&DEBUG.:45:P45_VOUCHER_TYPE:&P45_VOUCHER_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'PRINT', region => 'lines', label => 'طباعة الإذن', position => 'PREVIOUS', seq => 35, if_not_null => 'P45_VOUCHER_ID',
       js => $print_js->(42, 'P42_VOUCHER_ID', 'P45_VOUCHER_ID'));
button(name => 'SHOW_JV', region => 'lines', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P45_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P45_STATUS IN ('POSTED','REVERSED')");
button(name => 'SCHEDULE', region => 'lines', label => 'جدولة الشيكات', url => 'f?p=&APP_ID.:47:&SESSION.::&DEBUG.:47::', position => 'PREVIOUS', seq => 45);
button(name => 'REVERSE', region => 'lines', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P45_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P45_STATUS = 'POSTED' AND :G_USER_ROLE IN ('ADMIN','APPROVER')");
wf_setup(page => 45, region => 'lines', table => 'vouchers', idcol => 'voucher_id', id => 'P45_VOUCHER_ID',
         status => 'P45_STATUS', doc => 'VOUCHER', extra => 'NVL(:P45_CHQ_COUNT, 0) > 0', 
         precheck => "SELECT CASE WHEN COUNT(*) = 0 THEN 'لا يُراجع إذن الشيكات قبل جدولة شيكاته' END INTO l_err FROM cheques WHERE voucher_id = l_id;",
         post => src('voucher_post.sql'));
# روابط طباعة الشيكات الصادرة بعد الاعتماد (كل شيك بمقاس الشيك البنكي)
region(name => 'prints', title => 'طباعة الشيكات', type => 'plsql', seq => 30,
       cond => ":P45_VOUCHER_TYPE = 'P' AND NVL(:P45_CHQ_COUNT, 0) > 0", plsql => <<'PLSQL');
BEGIN
  FOR c IN (SELECT cheque_id, cheque_serial, cheque_no, amount, TO_CHAR(due_date, 'DD/MM/YYYY') due FROM cheques
            WHERE voucher_id = :P45_VOUCHER_ID ORDER BY line_no) LOOP
    htp.p('<a class="t-Button t-Button--small" style="margin:3px" target="_blank" href="'
          || apex_page.get_url(p_page => 48, p_items => 'P48_CHEQUE_ID', p_values => c.cheque_id)
          || '">طباعة الشيك ' || apex_escape.html(c.cheque_no) || ' (' || c.cheque_serial || ')' || ' - ' || TO_CHAR(c.amount, 'FM999G999G999G990D00')
          || ' - ' || c.due || '</a>');
  END LOOP;
END;
PLSQL
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p45_load.sql', 'P45'), cond => ':P45_VOUCHER_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P45_VOUCHER_TYPE IS NULL OR :P45_VOUCHER_TYPE NOT IN ('R','P') THEN :P45_VOUCHER_TYPE := 'R'; END IF;",
  "IF :P45_VOUCHER_ID IS NULL THEN",
  "  :P45_STATUS := NULL;",
  '  ' . date_default('P45_VOUCHER_DATE'),
  'END IF;',
  next_no_sql('P45_VOUCHER_ID', 'P45_VOUCHER_NO', "CASE :P45_VOUCHER_TYPE WHEN 'R' THEN '13' ELSE '14' END", 'P45_VOUCHER_DATE'),
  ":P45_TITLE := CASE :P45_VOUCHER_TYPE WHEN 'R' THEN 'إذن توريد شيكات' ELSE 'إذن صرف شيكات' END;",
  ":P45_ACC_LABEL := CASE :P45_VOUCHER_TYPE WHEN 'R' THEN 'الحساب المقابل (العميل / الجهة)' ELSE 'الحساب المقابل (المورد / الجهة)' END;",
  ":P45_PARTY_LABEL := CASE :P45_VOUCHER_TYPE WHEN 'R' THEN 'استلمنا من' ELSE 'اسم المستفيد (يُطبع على الشيكات)' END;",
  ":P45_BANK_LABEL := CASE :P45_VOUCHER_TYPE WHEN 'R' THEN 'البنك المودَع فيه' ELSE 'البنك المسحوب عليه' END;"));
ajax('INIT_DATA', src('p45_init.sql'));
ajax('SAVE_DOC',  src('p45_save.sql'));
branch_self('P45_VOUCHER_ID', 'P45_VOUCHER_TYPE');
end_page();

page(id => 46, name => 'قائمة أذونات الشيكات', alias => 'CHEQUE-VOUCHERS', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P46_TYPE', region => 'f', type => 'select', label => 'النوع', null => 'الكل', submit => 1,
     lov => "SELECT 'توريد شيكات' d, 'R' r FROM dual UNION ALL SELECT 'صرف شيكات', 'P' FROM dual");
item(name => 'P46_STATUS', region => 'f', type => 'select', label => 'الحالة', null => 'الكل', submit => 1, seq => 20, same_line => 1, lov => $LOV{wf_status});
region(name => 'ir', title => 'أذونات الشيكات', type => 'ir', sql => src('p46_ir.sql'), seq => 10, hide => ['VOUCHER_TYPE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:45:&SESSION.::&DEBUG.:45:P45_VOUCHER_ID,P45_VOUCHER_TYPE:#VOUCHER_ID#,#VOUCHER_TYPE#' });
branch_self('P46_TYPE', 'P46_STATUS');   # الفلاتر تبقى بعد اختيارها
end_page();

# =====================================================================
# 47 جدولة الشيكات: الاستحقاقات + الصرف / التحصيل / الارتداد (ينشئ قيد تسوية يمر بالمراجعة والاعتماد)
# =====================================================================
page(id => 47, name => 'جدولة الشيكات', alias => 'CHEQUES', auth => 'IS_ACCOUNTANT');
table_region(name => 'alerts', title => 'تنبيهات الاستحقاق', seq => 3, sql => src('p47_alerts.sql'));
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P47_TYPE', region => 'f', type => 'select', label => 'النوع', null => 'الكل', submit => 1,
     lov => "SELECT 'شيكات واردة (تحصيل)' d, 'R' r FROM dual UNION ALL SELECT 'شيكات صادرة (صرف)', 'P' FROM dual");
item(name => 'P47_STATUS', region => 'f', type => 'select', label => 'حالة الشيك', null => 'الكل', submit => 1, seq => 20, same_line => 1,
     lov => "SELECT 'قائم (لم يُسوَّ)' d, 'PENDING' r FROM dual UNION ALL SELECT 'تم الصرف / التحصيل', 'CLEARED' FROM dual UNION ALL SELECT 'مرتد', 'BOUNCED' FROM dual");
item(name => 'P47_FROM', region => 'f', type => 'date', label => 'استحقاق من', seq => 30, same_line => 1);
item(name => 'P47_TO',   region => 'f', type => 'date', label => 'إلى', seq => 40, same_line => 1);
button(name => 'GO', region => 'f', label => 'عرض', seq => 10, hot => 1);
region(name => 'ir', title => 'الشيكات حسب تاريخ الاستحقاق', type => 'ir', sql => src('p47_ir.sql'), seq => 10,
       links => { 'إجراء' => 'f?p=&APP_ID.:47:&SESSION.::&DEBUG.::P47_CHEQUE_ID,P47_TYPE,P47_STATUS,P47_FROM,P47_TO:#CHEQUE_ID#,&P47_TYPE.,&P47_STATUS.,&P47_FROM.,&P47_TO.' });
region(name => 'act', title => 'تسوية الشيك المختار', type => 'static', seq => 20, cond => ':P47_CHEQUE_ID IS NOT NULL',
       html => '<div class="doc-meta">&P47_INFO.</div>');
item(name => 'P47_CHEQUE_ID', region => 'act', type => 'hidden', seq => 1);
item(name => 'P47_INFO', region => 'act', type => 'hidden', seq => 2);
item(name => 'P47_KIND', region => 'act', type => 'hidden', seq => 3);
item(name => 'P47_CHQ_STATUS', region => 'act', type => 'hidden', seq => 4);
item(name => 'P47_SETTLE_DATE', region => 'act', type => 'date', label => 'تاريخ الصرف / التحصيل', seq => 10, required => 1);
item(name => 'P47_SETTLE_BANK_ID', region => 'act', type => 'select', label => 'البنك المودع فيه (للشيكات الواردة)', seq => 20, same_line => 1,
     null => 1, lov => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE cash_bank = 'B' AND is_active = 'Y' ORDER BY account_code",
     cond => ":P47_KIND = 'R'");
my $entry = ":G_USER_ROLE IN ('ADMIN','ENTRY')";
button(name => 'CLEAR', region => 'act', label => '&P47_CLEAR_LABEL.', hot => 1, seq => 10,
       cond => "$entry AND :P47_CHQ_STATUS = 'PENDING'", confirm => 'سيُرحّل قيد التسوية مباشرة (الشيك معتمد مع إذنه). متابعة؟');
item(name => 'P47_CLEAR_LABEL', region => 'act', type => 'hidden', seq => 5);
button(name => 'BOUNCE', region => 'act', label => 'شيك مرتد', seq => 20,
       cond => "$entry AND :P47_CHQ_STATUS = 'PENDING'", confirm => 'تسجيل الشيك مرتداً وترحيل قيد الارتداد مباشرة؟');
button(name => 'UNSETTLE', region => 'act', label => 'إلغاء التسوية', seq => 30, position => 'PREVIOUS',
       cond => ":G_USER_ROLE IN ('ADMIN','APPROVER') AND :P47_CHQ_STATUS IN ('CLEARED','BOUNCED') AND NVL(:P47_JNL_STATUS, 'X') <> 'REVERSED'",
       confirm => 'حذف قيد التسوية وإرجاع الشيك قائماً (لتصحيح تسوية خاطئة)؟');
button(name => 'PRINT', region => 'act', label => 'طباعة الشيك', seq => 40, position => 'PREVIOUS', cond => ":P47_KIND = 'P'",
       js => $print_js->(48, 'P48_CHEQUE_ID', 'P47_CHEQUE_ID'));
button(name => 'SHOW_JV', region => 'act', label => 'عرض قيد التسوية', seq => 50, position => 'PREVIOUS',
       cond => ":P47_CHQ_STATUS IN ('CLEARED','BOUNCED')",
       url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P47_JOURNAL_ID.');
item(name => 'P47_JOURNAL_ID', region => 'act', type => 'hidden', seq => 6);
item(name => 'P47_JNL_STATUS', region => 'act', type => 'hidden', seq => 7);
process(name => 'LOAD_CHEQUE', point => 'BEFORE_HEADER', seq => 10, cond => ':P47_CHEQUE_ID IS NOT NULL', code => src('p47_load.sql'));
process(name => 'SETTLE', seq => 10, when_req => 'CLEAR,BOUNCE,UNSETTLE', code => src('p47_settle.sql'));
branch_self('P47_CHEQUE_ID', 'P47_TYPE', 'P47_STATUS', 'P47_FROM', 'P47_TO');
end_page();

# =====================================================================
# 48 طباعة الشيك بمقاس الشيك البنكي
# =====================================================================
page(id => 48, name => 'طباعة شيك', alias => 'PRINT-CHEQUE', template => 'page_minimal', css => <<'CSS');
body, .t-Body, .t-Body-main, .t-Body-content { background: #fff !important; }
.t-Header, .t-Footer, .t-Body-nav, #t_Header, .t-Breadcrumb, .t-Body-title { display: none !important; }
.chq { position: relative; border: 1px dashed #999; margin: 10px auto; box-sizing: border-box; font-family: "Arial", sans-serif; color: #000; }
.chq div { position: absolute; white-space: nowrap; }
.chq .w { white-space: normal; line-height: 1.6; }
.no-print { text-align: center; margin: 10px 0; }
@media print {
  .no-print { display: none !important; }
  .chq { border: 0; margin: 0; }
  .t-Body-content, .t-Body-contentInner, .container { padding: 0 !important; margin: 0 !important; }
}
CSS
region(name => 'chq', title => 'chq', type => 'plsql', no_header => 1, seq => 10, plsql => src_t('p48_print.sql'));
item(name => 'P48_CHEQUE_ID', region => 'chq', type => 'hidden');
end_page();

# =====================================================================
# 35 المستندات بانتظار المراجعة / الاعتماد / الترحيل / المعادة للمدخل
# =====================================================================
page(id => 35, name => 'بانتظار المراجعة والاعتماد', alias => 'PENDING', auth => 'IS_ACCOUNTANT');
region(name => 'ir', title => 'المستندات حسب دورها في المراجعة والاعتماد', type => 'ir', sql => src('p35_ir.sql'), seq => 10,
       hide => ['VOUCHER_TYPE', 'ADJ_TYPE'],
       links => { 'قيد'       => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:#JOURNAL_ID#',
                  'إذن نقدي'  => 'f?p=&APP_ID.:40:&SESSION.::&DEBUG.:40:P40_VOUCHER_ID,P40_VOUCHER_TYPE:#CASH_VOUCHER_ID#,#VOUCHER_TYPE#',
                  'إذن شيكات' => 'f?p=&APP_ID.:45:&SESSION.::&DEBUG.:45:P45_VOUCHER_ID,P45_VOUCHER_TYPE:#CHQ_VOUCHER_ID#,#VOUCHER_TYPE#',
                  'تسوية رواتب' => 'f?p=&APP_ID.:70:&SESSION.::&DEBUG.:70:P70_ADJ_ID,P70_ADJ_TYPE:#ADJ_ID#,#ADJ_TYPE#' });
end_page();

# =====================================================================
# 50 فاتورة مبيعات / مرتجع مبيعات (الشركة الأم) لفرع أو عميل خارجي + 51 القائمة
# =====================================================================
my $acc_lov_cash = "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_active = 'Y' AND is_postable = 'Y' AND (company_id IS NULL OR company_id = :G_PARENT_ID) AND cash_bank = CASE :%s WHEN 'BANK' THEN 'B' ELSE 'C' END ORDER BY account_code";
my $acc_lov_credit = "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_active = 'Y' AND is_postable = 'Y' AND cash_bank = 'N' AND (company_id IS NULL OR company_id = :G_PARENT_ID) ORDER BY account_code";

page(id => 50, name => 'فاتورة مبيعات', alias => 'SALES', title => '&P50_TITLE.', auth => 'IS_STORE',
     js => src('p50.js'),
     onload => "inv.init();\n" . sprintf($SAVE_KEYS, 'P50_STATUS', 'P50_STATUS', 'DRAFT',
       "['P50_PAY_TYPE','P50_ACCOUNT_ID','P50_CUSTOMER_NAME','P50_INVOICE_DATE','P50_WAREHOUSE_ID','P50_PRICE_LIST_ID','P50_CURRENCY_CODE','P50_EXCHANGE_RATE','P50_DISCOUNT_AMOUNT','P50_DESCRIPTION']"));
region(name => 'head', title => '&P50_TITLE.', type => 'static', html => doc_status_html('P50_INVOICE_NO', 'P50_STATUS', 'رقم الفاتورة'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P50_INVOICE_ID',1],['P50_INVOICE_TYPE',2],['P50_INVOICE_NO',3],['P50_STATUS',4],['P50_JOURNAL_ID',5],['P50_TITLE',6]);
item(name => 'P50_INVOICE_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 10, required => 1);
item(name => 'P50_PAY_TYPE', region => 'head', type => 'select', label => 'طريقة الدفع', seq => 20, same_line => 1,
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'آجل' d, 'CREDIT' r FROM dual");
# الخيارات تُبنى بالمتصفح حسب طريقة الدفع ، والاستعلام هنا يعرض الحساب المحفوظ فقط
item(name => 'P50_ACCOUNT_ID', region => 'head', type => 'select', label => 'الحساب', seq => 30, same_line => 1, null => '- اختر -',
     lov => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE account_id = :P50_ACCOUNT_ID");
item(name => 'P50_CUSTOMER_NAME', region => 'head', type => 'hidden', protected => 1, no_checksum => 1, seq => 40);   # أخفاه المستخدم
item(name => 'P50_WAREHOUSE_ID', region => 'head', type => 'select', label => 'المخزن', seq => 80, same_line => 1, required => 1,
     lov => "SELECT name_ar d, warehouse_id r FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y' ORDER BY name_ar");
item(name => 'P50_PRICE_LIST_ID', region => 'head', type => 'hidden', protected => 1, no_checksum => 1, seq => 90);   # أخفاه المستخدم
item(name => 'P50_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 100);
item(name => 'P50_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 110, same_line => 1);
item(name => 'P50_DISCOUNT_AMOUNT', region => 'head', type => 'hidden', protected => 1, no_checksum => 1, seq => 120);   # أخفاه المستخدم
item(name => 'P50_DESCRIPTION', region => 'head', type => 'hidden', protected => 1, no_checksum => 1, seq => 130);   # أخفاه المستخدم
region(name => 'lines', title => 'الأصناف', type => 'static', seq => 20, html => <<'HTML');
<div class="jl-hint">ابحث بالكود أو بجزء من الاسم أو بالباركود. الأسهم للتنقل في النتائج و Enter للاختيار.</div>
<div id="inv_lines"></div>
<div style="margin-top:10px;font-weight:600">
  الإجمالي: <span id="inv_gross">0.00</span> &nbsp;&nbsp;
  الصافي بعد الخصم الإضافي: <span id="inv_net">0.00</span>
</div>
HTML
$draft = "(:P50_STATUS IS NULL OR :P50_STATUS = 'DRAFT') AND :P50_SHIFT_ID IS NOT NULL AND :G_USER_ROLE IN ('ADMIN','ENTRY')";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "inv.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ الفاتورة', js => "inv.save('POST');", hot => 1, seq => 20, cond => $draft);
# البيع داخل وردية مفتوحة
region(name => 'noshift', title => 'لا توجد وردية مفتوحة', type => 'static', seq => 1, cond => ':P50_SHIFT_ID IS NULL AND :P50_INVOICE_ID IS NULL',
       html => '<div class="doc-warn">لا يمكن البيع قبل فتح وردية. <a href="f?p=&APP_ID.:58:&SESSION.::&DEBUG.:58::">افتح وردية من هنا</a></div>');
item(name => 'P50_SHIFT_ID', region => 'lines', type => 'hidden', seq => 99);
button(name => 'PRINT_A4', region => 'lines', label => 'طباعة A4', js => "inv.print('A4');", seq => 25, cond => ':P50_INVOICE_ID IS NOT NULL');
button(name => 'PRINT_80', region => 'lines', label => 'طباعة إيصال (إبسون)', js => "inv.print('80');", seq => 26, cond => ':P50_INVOICE_ID IS NOT NULL');
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:50:&SESSION.::&DEBUG.:50:P50_INVOICE_TYPE:&P50_INVOICE_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'SHOW_JV', region => 'lines', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P50_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P50_STATUS IN ('POSTED','REVERSED')");
button(name => 'REVERSE', region => 'lines', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P50_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P50_STATUS = 'POSTED'");
item(name => 'P50_LOADED_ID', region => 'head', type => 'hidden', seq => 8);
# يُقرأ الرأس من القاعدة مرة واحدة لكل فاتورة، حتى لا يضيع تغيير المستخدم عند إعادة تحميل الصفحة
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10,
        cond => ":P50_INVOICE_ID IS NOT NULL AND :P50_INVOICE_ID <> NVL(:P50_LOADED_ID, 'x')", code => <<'SQL');
DECLARE i invoices%ROWTYPE;
BEGIN
  :P50_LOADED_ID := :P50_INVOICE_ID;
  SELECT * INTO i FROM invoices WHERE invoice_id = :P50_INVOICE_ID;
  :P50_INVOICE_TYPE := i.invoice_type; :P50_INVOICE_NO := i.invoice_no;
  :P50_INVOICE_DATE := TO_CHAR(i.invoice_date, 'DD/MM/YYYY');
  :P50_PAY_TYPE := i.pay_type; :P50_ACCOUNT_ID := i.account_id;
  :P50_CUSTOMER_NAME := i.customer_name; :P50_WAREHOUSE_ID := i.warehouse_id; :P50_PRICE_LIST_ID := i.price_list_id;
  :P50_CURRENCY_CODE := i.currency_code; :P50_EXCHANGE_RATE := i.exchange_rate;
  :P50_DISCOUNT_AMOUNT := i.discount_amount; :P50_DESCRIPTION := i.description;
  :P50_STATUS := i.status; :P50_JOURNAL_ID := i.journal_id;
END;
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P50_INVOICE_TYPE IS NULL THEN :P50_INVOICE_TYPE := 'SALE'; END IF;",
  "SELECT MAX(shift_id) INTO :P50_SHIFT_ID FROM sales_shifts WHERE user_name = :APP_USER AND status = 'OPEN';",
  "IF :P50_PAY_TYPE IS NULL THEN :P50_PAY_TYPE := 'CASH'; END IF;",
  "IF :P50_INVOICE_ID IS NULL THEN",
  "  IF :P50_STATUS IS NULL THEN :P50_STATUS := 'DRAFT'; END IF;",
  "  IF :P50_WAREHOUSE_ID IS NULL THEN SELECT MIN(warehouse_id) INTO :P50_WAREHOUSE_ID FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y'; END IF;",
  '  ' . date_default('P50_INVOICE_DATE'), '  ' . base_cur_default('P50_CURRENCY_CODE', 'P50_EXCHANGE_RATE'),
  'END IF;',
  ":P50_TITLE := CASE :P50_INVOICE_TYPE WHEN 'SALE' THEN 'فاتورة مبيعات' ELSE 'مرتجع مبيعات' END;"));
ajax('INIT_DATA', src('p50_init.sql'));
ajax('SAVE_DOC',  src('p50_save.sql'));
ajax('NEXT_NO', src('next_no.sql'));
ajax('PAY_ACCOUNTS', src('pay_accounts.sql'));
branch_self('P50_INVOICE_ID', 'P50_INVOICE_TYPE');
end_page();

page(id => 51, name => 'قائمة المبيعات', alias => 'INVOICES', auth => 'IS_STORE');
region(name => 'ir', title => 'فواتير المبيعات والمرتجعات', type => 'ir', sql => src('p51_ir.sql'), hide => ['INVOICE_TYPE_CODE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:50:&SESSION.::&DEBUG.:50:P50_INVOICE_ID:#INVOICE_ID#', 'طباعة A4' => 'f?p=&APP_ID.:53:&SESSION.::&DEBUG.:53:P53_INVOICE_ID:#INVOICE_ID#', 'إيصال' => 'f?p=&APP_ID.:54:&SESSION.::&DEBUG.:54:P54_INVOICE_ID:#INVOICE_ID#' });
end_page();

# =====================================================================
# 55 فاتورة مشتريات / مرتجع مشتريات (الشركة الأم) + 56 القائمة
# =====================================================================
page(id => 55, name => 'فاتورة مشتريات', alias => 'PURCHASE', title => '&P55_TITLE.', auth => 'IS_STORE',
     js => src('p55.js'),
     onload => "pur.init();\n" . sprintf($SAVE_KEYS, 'P55_STATUS', 'P55_STATUS', 'DRAFT',
       "['P55_INVOICE_DATE','P55_SUPPLIER_INV_NO','P55_PAY_TYPE','P55_SUPPLIER_ACCOUNT_ID','P55_SUPPLIER_NAME','P55_WAREHOUSE_ID','P55_CURRENCY_CODE','P55_EXCHANGE_RATE','P55_DISCOUNT_AMOUNT','P55_DESCRIPTION']"));
region(name => 'head', title => '&P55_TITLE.', type => 'static', html => doc_status_html('P55_INVOICE_NO', 'P55_STATUS', 'رقم الفاتورة', 'P55'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P55_PINV_ID',1],['P55_INVOICE_TYPE',2],['P55_INVOICE_NO',3],['P55_STATUS',4],['P55_JOURNAL_ID',5],['P55_TITLE',6]);
item(name => 'P55_COMPANY_ID', region => 'head', type => 'hidden', seq => 7);
item(name => 'P55_LOADED_ID', region => 'head', type => 'hidden', seq => 8);
item(name => 'P55_INVOICE_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, required => 1);
item(name => 'P55_SUPPLIER_INV_NO', region => 'head', label => 'رقم فاتورة المورد', seq => 30, same_line => 1, max => 50);
item(name => 'P55_PAY_TYPE', region => 'head', type => 'select', label => 'طريقة الدفع', seq => 40,
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'آجل' d, 'CREDIT' r FROM dual");
item(name => 'P55_SUPPLIER_ACCOUNT_ID', region => 'head', type => 'select', label => 'الحساب', seq => 50, same_line => 1, null => '- اختر -',
     lov => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE account_id = :P55_SUPPLIER_ACCOUNT_ID");
item(name => 'P55_SUPPLIER_NAME', region => 'head', label => 'اسم المورد', seq => 60, same_line => 1, max => 150);
item(name => 'P55_WAREHOUSE_ID', region => 'head', type => 'select', label => 'المخزن', seq => 70, null => 1, required => 1,
     lov => "SELECT name_ar d, warehouse_id r FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y' ORDER BY name_ar");
item(name => 'P55_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 80, same_line => 1);
item(name => 'P55_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 90, same_line => 1);
item(name => 'P55_DISCOUNT_AMOUNT', region => 'head', label => 'خصم إضافي', seq => 100);
item(name => 'P55_DESCRIPTION', region => 'head', label => 'البيان', seq => 110, same_line => 1, max => 500);
region(name => 'lines', title => 'الأصناف', type => 'static', seq => 20, html => <<'HTML');
<div class="jl-hint">ابحث بالكود أو بجزء من الاسم أو بالباركود. الأسهم للتنقل في النتائج و Enter للاختيار.</div>
<div id="pur_lines"></div>
<div style="margin-top:10px;font-weight:600">
  الإجمالي: <span id="pur_gross">0.00</span> &nbsp;&nbsp;
  الصافي بعد الخصم الإضافي: <span id="pur_net">0.00</span>
</div>
HTML
$draft = can_save('P55_STATUS');
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ (Ctrl+S)', js => "pur.save('DRAFT');", hot => 1, seq => 10, cond => $draft);
wf_setup(page => 55, region => 'lines', table => 'purchase_invoices', idcol => 'pinv_id', id => 'P55_PINV_ID',
         status => 'P55_STATUS', doc => 'PURCHASE', post => src('p55_post.sql'));
button(name => 'PRINT_A4', region => 'lines', label => 'طباعة A4', js => 'pur.print();', seq => 25, cond => ':P55_PINV_ID IS NOT NULL');
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:55:&SESSION.::&DEBUG.:55:P55_INVOICE_TYPE:&P55_INVOICE_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'SHOW_JV', region => 'lines', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P55_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P55_STATUS IN ('POSTED','REVERSED')");
button(name => 'REVERSE', region => 'lines', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P55_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P55_STATUS = 'POSTED' AND :G_USER_ROLE IN ('ADMIN','APPROVER')");
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10,
        cond => ":P55_PINV_ID IS NOT NULL AND :P55_PINV_ID <> NVL(:P55_LOADED_ID, 'x')", code => <<'SQL');
DECLARE p purchase_invoices%ROWTYPE; r purchase_invoices%ROWTYPE;
BEGIN
  :P55_LOADED_ID := :P55_PINV_ID;
  SELECT * INTO p FROM purchase_invoices WHERE pinv_id = :P55_PINV_ID;
  r := p;
  __WF55__
  IF NOT (:G_USER_ROLE = 'ADMIN' OR p.company_id = :G_COMPANY_ID) THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الفاتورة');
  END IF;
  :P55_INVOICE_TYPE := p.invoice_type; :P55_INVOICE_NO := p.invoice_no; :P55_COMPANY_ID := p.company_id;
  :P55_INVOICE_DATE := TO_CHAR(p.invoice_date, 'DD/MM/YYYY'); :P55_SUPPLIER_INV_NO := p.supplier_inv_no;
  :P55_PAY_TYPE := p.pay_type; :P55_SUPPLIER_ACCOUNT_ID := p.supplier_account_id; :P55_SUPPLIER_NAME := p.supplier_name;
  :P55_WAREHOUSE_ID := p.warehouse_id; :P55_CURRENCY_CODE := p.currency_code; :P55_EXCHANGE_RATE := p.exchange_rate;
  :P55_DISCOUNT_AMOUNT := p.discount_amount; :P55_DESCRIPTION := p.description; :P55_STATUS := p.status;
  :P55_JOURNAL_ID := p.journal_id;
END;
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P55_INVOICE_TYPE IS NULL THEN :P55_INVOICE_TYPE := 'PURCHASE'; END IF;",
  "IF :P55_PINV_ID IS NULL THEN",
  '  :P55_COMPANY_ID := :G_PARENT_ID;',
  "  IF :P55_WAREHOUSE_ID IS NULL THEN SELECT MIN(warehouse_id) INTO :P55_WAREHOUSE_ID FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y'; END IF;",
  "  IF :P55_STATUS IS NULL THEN :P55_STATUS := 'DRAFT'; END IF;",
  "  IF :P55_PAY_TYPE IS NULL THEN :P55_PAY_TYPE := 'CREDIT'; END IF;",
  '  ' . date_default('P55_INVOICE_DATE'), '  ' . base_cur_default('P55_CURRENCY_CODE', 'P55_EXCHANGE_RATE'),
  'END IF;',
  ":P55_TITLE := CASE :P55_INVOICE_TYPE WHEN 'PURCHASE' THEN 'فاتورة مشتريات' ELSE 'مرتجع مشتريات' END;"));
ajax('INIT_DATA', src('p55_init.sql'));
ajax('SAVE_DOC',  src('p55_save.sql'));
ajax('NEXT_NO', src('next_no.sql'));
ajax('PAY_ACCOUNTS', src('pay_accounts.sql'));
branch_self('P55_PINV_ID', 'P55_INVOICE_TYPE');
end_page();

page(id => 56, name => 'قائمة المشتريات', alias => 'PURCHASES', auth => 'IS_STORE');
region(name => 'ir', title => 'فواتير المشتريات والمرتجعات', type => 'ir', sql => src('p56_ir.sql'), hide => ['INVOICE_TYPE_CODE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:55:&SESSION.::&DEBUG.:55:P55_PINV_ID,P55_INVOICE_TYPE:#PINV_ID#,#INVOICE_TYPE_CODE#', 'طباعة A4' => 'f?p=&APP_ID.:57:&SESSION.::&DEBUG.:57:P57_PINV_ID:#PINV_ID#' });
end_page();

# =====================================================================
# 53 / 54 / 57 طباعة الفواتير: مبيعات A4 ، مبيعات إيصال 80 مم (إبسون) ، مشتريات A4
# =====================================================================
my $print_css = <<'CSS';
.t-Header, .t-Body-nav, .t-Footer, #apexDevToolbar { display: none !important; }
.t-Body, .t-Body-main, .t-Body-content, .t-Body-contentInner { margin: 0 !important; padding: 0 !important; background: #fff !important; }
.t-Region { border: 0 !important; box-shadow: none !important; margin: 0 !important; }
.t-Region-header { display: none !important; }
body { background: #fff !important; color: #000; }
.inv-brand { text-align: center; margin-bottom: 6px; }
.inv-brand img { width: 90px; height: 90px; }
.inv-brand .nm { font-size: 20px; font-weight: 700; color: #2e2a83; }
.inv-brand .ln { height: 4px; margin: 6px auto 0; width: 60%;
  background: linear-gradient(to left, #1d1d1b 0 33.3%, #d9232d 33.3% 66.6%, #2e2a83 66.6% 100%); }
.inv { direction: rtl; font-family: 'Cairo', Tahoma, Arial, sans-serif; color: #000; }
.inv-title { text-align: center; font-size: 18px; font-weight: 700; margin: 8px 0; color: #146b2d; }
.inv-draft { color: #d9232d; font-size: 14px; }
.inv table { width: 100%; border-collapse: collapse; }
.inv-head th, .inv-head td { border: 1px solid #999; padding: 4px 6px; text-align: right; }
.inv-head th { background: #eef6f0; width: 18%; white-space: nowrap; }
.inv-no { font-weight: 700; font-size: 15px; letter-spacing: 1px; direction: ltr; text-align: right; }
.inv-lines { margin-top: 10px; }
.inv-lines th { background: #146b2d; color: #fff; padding: 5px; border: 1px solid #146b2d; }
.inv-lines td { border: 1px solid #bbb; padding: 4px 6px; }
.inv .n { text-align: left; direction: ltr; white-space: nowrap; }
.inv .c { text-align: center; }
.inv-totals { width: 45% !important; margin-top: 8px; margin-inline-start: auto; }
.inv-totals th, .inv-totals td { border: 1px solid #999; padding: 4px 6px; }
.inv-totals th { background: #eef6f0; text-align: right; }
.inv-net th, .inv-net td { font-weight: 700; font-size: 15px; background: #e8f5ec; }
.inv-desc { margin-top: 8px; }
.inv-sign { margin-top: 40px; text-align: center; }
.inv-sign td { width: 33%; padding: 6px; }
.inv-foot { margin-top: 14px; font-size: 11px; color: #555; text-align: center; }
.no-print { text-align: center; margin: 10px 0; }
/* إيصال إبسون 80 مم */
.inv-80 { width: 72mm; margin: 0 auto; font-size: 12px; }
.inv-80 .inv-title { font-size: 14px; }
.inv-80 .inv-head th { width: 32%; }
.inv-80 .inv-lines th { background: #000; border-color: #000; font-size: 11px; padding: 3px; }
.inv-80 .inv-lines td { border: 0; border-bottom: 1px dashed #999; padding: 3px 2px; font-size: 11px; }
.inv-80 .inv-totals { width: 100% !important; }
@media print {
  .no-print { display: none !important; }
  .inv-lines th { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
}
CSS
for my $pp (['53', 'SALE', 'A4', 'P53_INVOICE_ID', 'طباعة فاتورة مبيعات A4'],
            ['54', 'SALE', '80', 'P54_INVOICE_ID', 'طباعة إيصال مبيعات'],
            ['57', 'PURCHASE', 'A4', 'P57_PINV_ID', 'طباعة فاتورة مشتريات A4'],
            ['95', 'STOCK', 'A4', 'P95_TRANS_ID', 'طباعة حركة مخزون A4']) {
  my ($pid, $kind, $size, $itm, $name) = @$pp;
  my $page_css = $print_css . ($size eq '80'
      ? "\@page { size: 80mm auto; margin: 2mm; }\n.inv-brand img { width: 60px; height: 60px; }\n.inv-brand .nm { font-size: 14px; }\n.inv-brand { width: 72mm; margin: 0 auto; }\n"
      : "\@page { size: A4; margin: 12mm; }\n");
  page(id => $pid, name => $name, alias => "PRINT-$pid", template => 'page_minimal', css => $page_css,
       onload => 'setTimeout(function () { window.print(); }, 600);');
  region(name => 'brand', title => 'brand', type => 'static', no_header => 1, seq => 5, html => <<'HTML');
<div class="no-print"><button type="button" class="t-Button t-Button--hot" onclick="window.print()">طباعة</button></div>
<div class="inv-brand"><img src="#APP_FILES#logo.jpg" alt=""><div class="nm">&G_COMPANY_NAME.</div><div class="inf">&G_COMPANY_INFO.</div><div class="ln"></div></div>
HTML
  item(name => $itm, region => 'brand', type => 'hidden');
  my $code = src('print_invoice.sql');
  $code =~ s/__KIND__/$kind/g; $code =~ s/__SIZE__/$size/g; $code =~ s/__ITEM__/$itm/g;
  region(name => 'body', title => 'body', type => 'plsql', no_header => 1, seq => 10, plsql => $code);
  end_page();
}

# =====================================================================
# 42 طباعة الإذن (نقدي أو شيكات) - 32 طباعة القيد
# =====================================================================
for my $pp ([42, 'طباعة إذن', 'PRINT-VOUCHER', 'P42_VOUCHER_ID', 'p42_print.sql'],
            [32, 'طباعة قيد يومية', 'PRINT-JOURNAL', 'P32_JOURNAL_ID', 'p32_print.sql']) {
  my ($pid, $name, $alias, $itm, $file) = @$pp;
  page(id => $pid, name => $name, alias => $alias, template => 'page_minimal', css => $print_css . "\@page { size: A4; margin: 12mm; }\n",
       onload => 'setTimeout(function () { window.print(); }, 600);');
  region(name => 'brand', title => 'brand', type => 'static', no_header => 1, seq => 5, html => <<'HTML');
<div class="no-print"><button type="button" class="t-Button t-Button--hot" onclick="window.print()">طباعة</button></div>
<div class="inv-brand"><img src="#APP_FILES#logo.jpg" alt=""><div class="nm">&G_COMPANY_NAME.</div><div class="inf">&G_COMPANY_INFO.</div><div class="ln"></div></div>
HTML
  item(name => $itm, region => 'brand', type => 'hidden');
  region(name => 'body', title => 'body', type => 'plsql', no_header => 1, seq => 10, plsql => src_t($file));
  end_page();
}


# =====================================================================
# 60 عكس القيود
# =====================================================================
page(id => 60, name => 'عكس القيود', alias => 'REVERSE', auth => 'IS_ACCOUNTANT');
region(name => 'ir', title => 'القيود المرحّلة القابلة للعكس', type => 'ir', sql => src('p60_ir.sql'), seq => 10,
       links => { 'اختيار' => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:#JOURNAL_ID#' });
table_region(name => 'lines', title => 'القيد المختار وسطوره بعد العكس', sql => src('p60_lines.sql'), seq => 20, cond => ':P60_JOURNAL_ID IS NOT NULL');
region(name => 'rev', title => 'بيانات العكس', type => 'static', seq => 30, cond => ':P60_JOURNAL_ID IS NOT NULL',
       html => '<div>القيد: <b>&P60_JOURNAL_INFO.</b></div>');
item(name => 'P60_JOURNAL_ID', region => 'rev', type => 'hidden', seq => 1);
item(name => 'P60_JOURNAL_INFO', region => 'rev', type => 'hidden', seq => 2);
item(name => 'P60_REV_DATE', region => 'rev', type => 'date', label => 'تاريخ العكس', seq => 10, required => 1);
item(name => 'P60_REASON', region => 'rev', label => 'سبب العكس', seq => 20, same_line => 1, max => 500, required => 1);
button(name => 'REVERSE', region => 'rev', label => 'عكس القيد', hot => 1, confirm => 'عكس القيد؟ القيود اليدوية وقيود الشيكات والأذونات تعود مسودة للتصحيح ثم المراجعة والاعتماد، والفواتير تُعكس بقيد عكسي', cond => ":G_USER_ROLE IN ('ADMIN','APPROVER')");
table_region(name => 'done', title => 'القيود المعكوسة', sql => src('p60_reversed.sql'), seq => 40);
process(name => 'INFO', point => 'BEFORE_HEADER', seq => 10, code => join("\n",
  "IF :P60_REV_DATE IS NULL THEN :P60_REV_DATE := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P60_JOURNAL_ID IS NOT NULL THEN",
  "  SELECT journal_no || ' - ' || TO_CHAR(journal_date, 'DD/MM/YYYY') || ' - ' || description INTO :P60_JOURNAL_INFO",
  "  FROM journals WHERE journal_id = :P60_JOURNAL_ID;",
  "END IF;"));
check(name => 'CHECK_STATUS', seq => 10, button => 'REVERSE', code => src('p60_val1.sql'));
check(name => 'CHECK_DATE',   seq => 20, button => 'REVERSE', code => src('p60_val2.sql'));
check(name => 'CHECK_REASON', seq => 30, button => 'REVERSE', code => "RETURN CASE WHEN :P60_REASON IS NULL THEN 'سبب العكس مطلوب' END;");
process(name => 'REVERSE_JOURNAL', seq => 40, button => 'REVERSE', code => guard(src('p60_reverse.sql')));
branch_self();
end_page();

# =====================================================================
# 70 خصم / فرق / حافز + 71
# =====================================================================
page(id => 70, name => 'خصم / فرق مبلغ / حافز', alias => 'PAYADJ', title => '&P70_TITLE.', auth => 'IS_HR',
     js => src('p70.js'),
     onload => "adj.init();\n" . sprintf($SAVE_KEYS, 'P70_STATUS', 'P70_STATUS', 'DRAFT',
       "['P70_ADJ_DATE','P70_PAY_PERIOD','P70_ALLOWANCE_ID','P70_CURRENCY_CODE','P70_EXCHANGE_RATE','P70_REASON']"));
region(name => 'head', title => '&P70_TITLE.', type => 'static', html => doc_status_html('P70_ADJ_NO', 'P70_STATUS', 'الرقم', 'P70'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P70_ADJ_ID',1],['P70_ADJ_TYPE',2],['P70_ADJ_NO',3],['P70_STATUS',4],['P70_TITLE',5]);
item(name => 'P70_ADJ_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 10, required => 1);
item(name => 'P70_PAY_PERIOD', region => 'head', type => 'select', label => 'شهر الراتب', lov => $LOV{periods}, seq => 20, same_line => 1, required => 1);
item(name => 'P70_ALLOWANCE_ID', region => 'head', type => 'select', label => 'البند', lov => src('p70_allow_lov.sql'), null => 1, seq => 30, same_line => 1);
item(name => 'P70_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 40);
item(name => 'P70_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 50, same_line => 1);
item(name => 'P70_REASON', region => 'head', label => 'السبب', seq => 60, same_line => 1, max => 500, required => 1);
region(name => 'lines', title => 'الموظفون', type => 'static', seq => 20, html => '<div id="adj_lines"></div>');
$draft = can_save('P70_STATUS');
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ (Ctrl+S)', js => "adj.save('DRAFT');", hot => 1, seq => 10, cond => $draft);
button(name => 'CANCEL_DOC', region => 'lines', label => 'إلغاء المستند', js => "adj.save('CANCEL');", position => 'PREVIOUS', seq => 30,
       cond => ":P70_ADJ_ID IS NOT NULL AND $draft");
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:70:&SESSION.::&DEBUG.:70:P70_ADJ_TYPE:&P70_ADJ_TYPE.', position => 'PREVIOUS', seq => 40);
# الاعتماد هو المرحلة النهائية (يُطبَّق في مسير الرواتب) - لا يوجد ترحيل
wf_setup(page => 70, region => 'lines', table => 'payroll_adj', idcol => 'adj_id', id => 'P70_ADJ_ID',
         status => 'P70_STATUS', doc => 'PAYADJ');
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, cond => ':P70_ADJ_ID IS NOT NULL', code => (my $p70load = <<'SQL') =~ s/__WF__/wf_load('P70')/er);
DECLARE r payroll_adj%ROWTYPE;
BEGIN
  SELECT * INTO r FROM payroll_adj WHERE adj_id = :P70_ADJ_ID;
  __WF__
  :P70_ADJ_TYPE      := r.adj_type;
  :P70_ADJ_NO        := r.adj_no;
  :P70_ADJ_DATE      := TO_CHAR(r.adj_date, 'DD/MM/YYYY');
  :P70_PAY_PERIOD    := r.pay_period;
  :P70_ALLOWANCE_ID  := r.allowance_id;
  :P70_CURRENCY_CODE := r.currency_code;
  :P70_EXCHANGE_RATE := r.exchange_rate;
  :P70_REASON        := r.reason;
  :P70_STATUS        := r.status;
END;
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P70_ADJ_TYPE IS NULL THEN :P70_ADJ_TYPE := 'DED'; END IF;",
  "IF :P70_ADJ_ID IS NULL THEN",
  "  IF :P70_STATUS IS NULL THEN :P70_STATUS := 'DRAFT'; END IF;",
  "  IF :P70_PAY_PERIOD IS NULL THEN :P70_PAY_PERIOD := TO_CHAR(SYSDATE, 'YYYYMM'); END IF;",
  '  ' . date_default('P70_ADJ_DATE'), '  ' . base_cur_default('P70_CURRENCY_CODE', 'P70_EXCHANGE_RATE'),
  'END IF;',
  ":P70_TITLE := CASE :P70_ADJ_TYPE WHEN 'DED' THEN 'خصم' WHEN 'DIFF' THEN 'فرق مبلغ' ELSE 'حافز' END;"));
ajax('INIT_DATA', src('p70_init.sql'));
ajax('SAVE_DOC',  src('p70_save.sql'));
branch_self('P70_ADJ_ID', 'P70_ADJ_TYPE');
end_page();

page(id => 71, name => 'الخصومات والفروقات والحوافز', alias => 'PAYADJS', auth => 'IS_HR');
my $p71 = src('p71_ir.sql');
$p71 =~ s/^SELECT a\.adj_id,/SELECT a.adj_id, a.adj_type AS adj_type_code,/;
region(name => 'ir', title => 'المستندات', type => 'ir', sql => $p71, seq => 10, hide => ['ADJ_TYPE_CODE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:70:&SESSION.::&DEBUG.:70:P70_ADJ_ID,P70_ADJ_TYPE:#ADJ_ID#,#ADJ_TYPE_CODE#' });
region(name => 'f', title => 'صافي التعديلات لكل موظف', type => 'static', html => '', seq => 20);
item(name => 'P71_PERIOD', region => 'f', type => 'select', label => 'الشهر', lov => $LOV{periods}, null => 'الكل', submit => 1);
item(name => 'P71_COMPANY', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{all_companies}, null => 'الكل', submit => 1, seq => 20, same_line => 1);
table_region(name => 'sum', title => 'الصافي حسب الموظف', sql => src('p71_summary.sql'), seq => 30);
end_page();

# =====================================================================
# 80 ميزان المراجعة / 81 كشف حساب
# =====================================================================
page(id => 80, name => 'ميزان المراجعة', alias => 'TRIAL', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P80_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات (مجمّع)');
item(name => 'P80_FROM', region => 'f', type => 'date', label => 'من', seq => 20, same_line => 1);
item(name => 'P80_TO', region => 'f', type => 'date', label => 'إلى', seq => 30, same_line => 1);
item(name => 'P80_LEVEL', region => 'f', type => 'select', label => 'المستوى', seq => 40, same_line => 1,
     lov => "SELECT 'المستوى ' || LEVEL d, LEVEL r FROM dual CONNECT BY LEVEL <= 4");
item(name => 'P80_EXCLUDE_INTERCO', region => 'f', type => 'select', label => 'استبعاد المعاملات البينية', lov => $LOV{yn}, seq => 50);
item(name => 'P80_SEPARATE', region => 'f', type => 'select', label => 'كل شركة منفصلة', lov => $LOV{yn}, seq => 60, same_line => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => "apex.page.submit({request: 'PRINT', showWait: true});");
region(name => 'ir', title => 'ميزان المراجعة', type => 'ir', sql => src('p80_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P80_FROM IS NULL THEN :P80_FROM := TO_CHAR(TRUNC(SYSDATE,'YYYY'), 'DD/MM/YYYY'); END IF;",
  "IF :P80_TO IS NULL THEN :P80_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P80_LEVEL IS NULL THEN :P80_LEVEL := 4; END IF;",
  "IF :P80_EXCLUDE_INTERCO IS NULL THEN :P80_EXCLUDE_INTERCO := 'N'; END IF;",
  "IF :P80_SEPARATE IS NULL THEN :P80_SEPARATE := 'N'; END IF;"));
# زر الطباعة يحفظ الخيارات ثم يفتح صفحة الطباعة
out("wwv_flow_imp_page.create_page_branch(\n" . args(id => wid(nid()), branch_name => "'Print'",
    branch_action => "'f?p=&APP_ID.:82:&SESSION.::&DEBUG.::P80_FROM,P80_TO,P80_LEVEL,P80_EXCLUDE_INTERCO,P80_SEPARATE:&P80_FROM.,&P80_TO.,&P80_LEVEL.,&P80_EXCLUDE_INTERCO.,&P80_SEPARATE.'", branch_point => "'AFTER_PROCESSING'",
    branch_type => "'REDIRECT_URL'", branch_sequence => 5, branch_condition_type => "'REQUEST_EQUALS_CONDITION'",
    branch_condition => "'PRINT'") . "\n);\n");
branch_self('P80_FROM', 'P80_TO', 'P80_LEVEL', 'P80_EXCLUDE_INTERCO', 'P80_SEPARATE');
end_page();

# بدون size في @page حتى يعمل اختيار الاتجاه (Portrait / Landscape) والمقاس من نافذة الطباعة
page(id => 82, name => 'طباعة ميزان المراجعة', alias => 'PRINT-TRIAL', template => 'page_minimal', css => $print_css . "\@page { margin: 10mm; }
.cons-table, .jl-table { font-size: 12px; width: 100%; }
",
     onload => 'setTimeout(function () { window.print(); }, 600);');
region(name => 'brand', title => 'brand', type => 'static', no_header => 1, seq => 5, html => <<'HTML');
<div class="no-print"><button type="button" class="t-Button t-Button--hot" onclick="window.print()">طباعة</button></div>
<div class="inv-brand"><img src="#APP_FILES#logo.jpg" alt=""><div class="nm">&G_COMPANY_NAME.</div><div class="inf">&G_COMPANY_INFO.</div><div class="ln"></div></div>
<div class="inv-title">ميزان المراجعة من &P80_FROM. إلى &P80_TO. - المستوى &P80_LEVEL.</div>
HTML
table_region(name => 'tb', title => 'tb', no_header => 1, sql => src('p80_ir.sql'), seq => 10);
end_page();

# =====================================================================
# 84 القوائم المالية: المركز المالي ، تكلفة المبيعات ، قائمة الدخل (من شجرة الحسابات مباشرة)
# =====================================================================
# خانات الإيضاح: تُحفظ تلقائياً عند الخروج من الخانة (أو Enter)
my $fs_notes_js = <<'JS';
apex.jQuery(document).on('change', '.fs-note-in', function () {
  var el = this;
  apex.server.process('SAVE_NOTE', {x01: el.getAttribute('data-key'), x02: el.value}, {dataType: 'json'})
    .done(function (d) { el.classList.toggle('saved', !!d.ok); if (!d.ok) apex.message.alert(d.error || 'تعذّر الحفظ'); });
});
// المركز المالي يملأ ورقة A4 عند الطباعة: أكبر خط يجعل القائمة تسع ورقة واحدة
// (نسخة مخفية بعرض A4 الصافي 190 مم ≈ 718px ، والارتفاع المتاح 277 مم ≈ 1047px مع هامش أمان)
function fsFitBs() {
  var bs = document.querySelector('.fs-bs'); if (!bs) return;
  var c = bs.cloneNode(true);
  c.classList.add('bs-fit');
  c.style.cssText = 'position:absolute;left:-5000px;top:0;width:718px;max-width:none;margin:0';
  document.body.appendChild(c);
  var lo = 9, hi = 24, best = 9;
  while (hi - lo > 0.2) {
    var mid = (lo + hi) / 2;
    c.style.setProperty('--bs', mid + 'px');
    if (c.getBoundingClientRect().height <= 1005) { best = mid; lo = mid; } else { hi = mid; }
  }
  c.remove();
  document.documentElement.style.setProperty('--bs', best.toFixed(2) + 'px');
}
fsFitBs();
window.addEventListener('beforeprint', fsFitBs);
JS
# قواعد حجم المركز المالي عند الطباعة تعتمد على المتغير --bs (يحسبه fsFitBs) ، وتُستخدم أيضاً للقياس (.bs-fit)
my $bs_rules = sub {
  my $s = shift;
  return join("\n",
    "  $s .fs-title { font-size: calc(var(--bs, 14px) * 1.25); margin: 0 0 calc(var(--bs, 14px) * 0.6); }",
    "  $s .fs { font-size: var(--bs, 14px); line-height: 1.3; }",
    "  $s .fs th { padding: calc(var(--bs, 14px) * 0.4) 6px; }",
    "  $s .fs td { padding: calc(var(--bs, 14px) * 0.32) 6px; }",
    "  $s .fs tr.main td.lbl { font-size: calc(var(--bs, 14px) * 1.12); padding-top: calc(var(--bs, 14px) * 0.6); }",
    "  $s .fs tr.grand td { font-size: calc(var(--bs, 14px) * 1.06); }",
    "  $s .fs tr:not(.sec):not(.main):not(.tot):not(.grand) td.lbl { padding-inline-start: calc(var(--bs, 14px) * 1.4); }") . "\n";
};
my $fs_css = <<'CSS';
.fs-page { max-width: 820px; margin: 0 auto 28px; direction: rtl; }
.fs-gap { height: 26px; }
.fs-title { text-align: center; font-size: 17px; font-weight: 700; text-decoration: underline; margin: 4px 0 10px; }
.fs { width: 100%; border-collapse: collapse; font-size: 14px; }
.fs th { border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 6px; text-align: center; }
.fs td { padding: 4px 6px; }
.fs td.n { text-align: left; direction: ltr; white-space: nowrap; width: 22%; }
.fs td.nt { text-align: center; color: #555; width: 10%; }
.fs tr.main td.lbl { font-size: 16px; font-weight: 700; text-decoration: underline; padding-top: 10px; }
.fs tr.sec td.lbl { font-weight: 700; text-decoration: underline; }
.fs tr:not(.sec):not(.main):not(.tot):not(.grand) td.lbl { padding-inline-start: 22px; }
.fs tr.tot td { font-weight: 700; }
.fs tr.tot td.n:last-child { border-top: 1px solid #000; }
.fs tr.grand td { font-weight: 700; font-size: 15px; }
.fs tr.grand td.n:last-child { border-top: 1px solid #000; border-bottom: 3px double #000; }
.fs-warn { color: #b00; font-weight: 700; margin-top: 6px; }
.fs-note-in { width: 100%; max-width: 70px; text-align: center; font: inherit; border: 1px dashed #bbb; border-radius: 3px; padding: 1px 2px; background: #fffef5; }
.fs-note-in:focus { border: 1px solid #146b2d; outline: none; background: #fff; }
.fs-note-in.saved { border-color: #9c9; }
/* الطباعة: الورقة 1 تكلفة المبيعات وقائمة الدخل ، الورقة 2 المركز المالي يملأ ورقة A4 واحدة */
@page { size: A4; margin: 10mm; }
@media print {
  .no-print { display: none !important; }
  .fs-page { max-width: none; margin: 0; }
  .fs-page:not(.fs-bs) { page-break-after: always; break-after: page; }
  .fs-gap { height: 14px; }
  .fs-bs { page-break-inside: avoid; break-inside: avoid; }
  .fs-note-in { border: none !important; background: transparent !important; padding: 0; color: #000; }
CSS
$fs_css .= $bs_rules->('.fs-bs') . "}\n" . $bs_rules->('.bs-fit');
page(id => 84, name => 'القوائم المالية', alias => 'FIN-STATEMENTS', auth => 'IS_ACCOUNTANT', onload => $fs_notes_js, css => $fs_css);
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P84_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 10, required => 1);
item(name => 'P84_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 20, same_line => 1, required => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
region(name => 'fs', title => 'القوائم المالية', type => 'plsql', no_header => 1, seq => 10, plsql => src('p84_fs.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P84_FROM IS NULL THEN :P84_FROM := '01/01/' || TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P84_TO IS NULL THEN :P84_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;"));
ajax('SAVE_NOTE', <<'SQL');
BEGIN
  -- حفظ رقم الإيضاح لسطر في القوائم المالية (فارغ = حذف)
  IF apex_application.g_x01 IS NULL OR LENGTH(apex_application.g_x01) > 40 THEN
    apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('error', 'سطر غير صحيح'); apex_json.close_object; RETURN;
  END IF;
  IF TRIM(apex_application.g_x02) IS NULL THEN
    DELETE FROM fs_notes WHERE line_key = apex_application.g_x01;
  ELSE
    MERGE INTO fs_notes n
    USING (SELECT apex_application.g_x01 k, SUBSTR(TRIM(apex_application.g_x02), 1, 50) t FROM dual) s
    ON (n.line_key = s.k)
    WHEN MATCHED THEN UPDATE SET n.note_text = s.t, n.updated_by = :APP_USER, n.updated_on = SYSDATE
    WHEN NOT MATCHED THEN INSERT (line_key, note_text, updated_by, updated_on) VALUES (s.k, s.t, :APP_USER, SYSDATE);
  END IF;
  apex_json.open_object; apex_json.write('ok', TRUE); apex_json.close_object;
EXCEPTION WHEN OTHERS THEN
  apex_json.open_object; apex_json.write('ok', FALSE); apex_json.write('error', SQLERRM); apex_json.close_object;
END;
SQL
branch_self('P84_FROM', 'P84_TO');
end_page();

# =====================================================================
# 85 الإيضاحات للفترة تجميعياً حسب مستوى شجرة الحسابات (مدين ، دائن ، الرصيد) مع الطباعة
# =====================================================================
my $levels = "SELECT 'المستوى ' || LEVEL d, LEVEL r FROM dual CONNECT BY LEVEL <= 4";
page(id => 85, name => 'الإيضاحات', alias => 'FS-NOTES', auth => 'IS_ACCOUNTANT', css => <<'CSS');
.nt-head { text-align: center; font-size: 17px; font-weight: 700; text-decoration: underline; margin: 4px 0 14px; direction: rtl; }
.nt-sub { font-size: 12px; font-weight: 400; text-decoration: none; color: #555; }
.nt-block { max-width: 860px; margin: 0 auto 18px; direction: rtl; }
.nt-title { font-size: 15px; font-weight: 700; margin: 0 0 6px; text-decoration: underline; }
.nt-dir { font-size: 11px; color: #555; }
.nt-empty { text-align: center; color: #777; }
.fs { width: 100%; border-collapse: collapse; font-size: 14px; }
.fs th { border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 5px; text-align: center; }
.fs td { padding: 3px 6px; border-bottom: 1px solid #eee; }
.fs td.n { text-align: left; direction: ltr; white-space: nowrap; width: 18%; }
.fs td.nt { text-align: center; color: #555; width: 11%; }
.fs tr.grand td { font-weight: 700; border-top: 1px solid #000; border-bottom: 3px double #000; }
/* الطباعة: لا ينقسم الإيضاح الواحد بين ورقتين ، والاتجاه والمقاس من نافذة الطباعة */
@page { margin: 10mm; }
@media print {
  .no-print { display: none !important; }
  .nt-block { max-width: none; page-break-inside: avoid; break-inside: avoid; }
  .fs { font-size: 12px; }
}
CSS
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P85_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 10, required => 1);
item(name => 'P85_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P85_GROUP_LEVEL',  region => 'f', type => 'select', label => 'مستوى التجميع (الإيضاح)', lov => $levels, seq => 30);
item(name => 'P85_DETAIL_LEVEL', region => 'f', type => 'select', label => 'مستوى التفصيل', lov => $levels, seq => 40, same_line => 1);
# إيضاح بند واحد (الذمم المدينة ، الموردون ، النقدية ، الأصول ...) لطباعته منفرداً
# (في نفس السطر + attribute_03 كما ضبطه المستخدم في APEX Builder)
item(name => 'P85_ACCOUNT_ID', region => 'f', type => 'select', label => 'إيضاح بند واحد', null => 'كل الإيضاحات', submit => 1, seq => 50,
     same_line => 1, attrs => { attribute_03 => "'Y'" },
     lov => "SELECT LPAD(' ', (acc_level - 1) * 4, ' ') || account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE acc_level <= 3 ORDER BY account_code");
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
region(name => 'notes', title => 'الإيضاحات', type => 'plsql', no_header => 1, seq => 10, plsql => src('p85_notes.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P85_FROM IS NULL THEN :P85_FROM := '01/01/' || TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P85_TO IS NULL THEN :P85_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P85_GROUP_LEVEL IS NULL THEN :P85_GROUP_LEVEL := '3'; END IF;",
  "IF :P85_DETAIL_LEVEL IS NULL THEN :P85_DETAIL_LEVEL := '4'; END IF;"));
branch_self('P85_FROM', 'P85_TO', 'P85_GROUP_LEVEL', 'P85_DETAIL_LEVEL', 'P85_ACCOUNT_ID');
end_page();

page(id => 81, name => 'كشف حساب', alias => 'STATEMENT', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', seq => 5,
       html => '<div class="doc-meta" style="margin-bottom:8px"><b>&P81_ACC_INFO.</b></div>');
item(name => 'P81_ACC_INFO', region => 'f', type => 'hidden', seq => 1);
item(name => 'P81_ACCOUNT_ID', region => 'f', type => 'popup', label => 'الحساب', lov => $LOV{accounts_all}, seq => 10, required => 1);
item(name => 'P81_FROM', region => 'f', type => 'date', label => 'من', seq => 30, same_line => 1);
item(name => 'P81_TO', region => 'f', type => 'date', label => 'إلى', seq => 40, same_line => 1);
item(name => 'P81_CURRENCY', region => 'f', type => 'select', label => 'العملة', lov => $LOV{currencies}, null => 'بالعملة الأساسية', seq => 50);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();', cond => ':P81_ACCOUNT_ID IS NOT NULL');
region(name => 'ir', title => 'كشف الحساب', type => 'ir', sql => src('p81_ir.sql'), seq => 10, cond => ':P81_ACCOUNT_ID IS NOT NULL',
       links => { 'رقم القيد' => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:#JOURNAL_ID#' });
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P81_FROM IS NULL THEN :P81_FROM := TO_CHAR(TRUNC(SYSDATE,'YYYY'), 'DD/MM/YYYY'); END IF;",
  "IF :P81_TO IS NULL THEN :P81_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P81_ACCOUNT_ID IS NOT NULL THEN",
  "  SELECT MAX('كشف حساب: ' || account_code || ' - ' || name_ar || ' (' || DECODE(acc_type, 'ASSET', 'أصول', 'LIAB', 'خصوم', 'EQUITY', 'حقوق ملكية', 'REV', 'إيرادات', 'EXP', 'مصروفات') || ')'",
  "         || ' من ' || :P81_FROM || ' إلى ' || :P81_TO)",
  "  INTO :P81_ACC_INFO FROM accounts WHERE account_id = :P81_ACCOUNT_ID;",
  "END IF;"));
check(name => 'CHECK_DATES', seq => 5, button => 'GO', code => <<'SQL');
DECLARE l_f DATE; l_t DATE;
BEGIN
  IF :P81_ACCOUNT_ID IS NULL THEN RETURN 'اختر الحساب'; END IF;
  l_f := TO_DATE(:P81_FROM, 'DD/MM/YYYY'); l_t := TO_DATE(:P81_TO, 'DD/MM/YYYY');
  IF l_f > l_t THEN RETURN 'تاريخ البداية بعد تاريخ النهاية'; END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN RETURN 'التاريخ غير صحيح (يوم/شهر/سنة)';
END;
SQL
branch_self('P81_ACCOUNT_ID', 'P81_FROM', 'P81_TO', 'P81_CURRENCY');
end_page();

# =====================================================================
# 86 أعمار الديون (العملاء 1106 / الموردون 2101) في تاريخ معيّن ، مع الطباعة
# =====================================================================
page(id => 86, name => 'أعمار الديون', alias => 'AGING', auth => 'IS_ACCOUNTANT', css => <<'CSS');
.nt-head { text-align: center; font-size: 17px; font-weight: 700; text-decoration: underline; margin: 4px 0 14px; direction: rtl; }
.nt-sub { font-size: 12px; font-weight: 400; text-decoration: none; color: #555; }
.nt-block { max-width: 1100px; margin: 0 auto 18px; direction: rtl; }
.nt-empty { text-align: center; color: #777; }
.fs { width: 100%; border-collapse: collapse; font-size: 14px; }
.fs th { border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 5px; text-align: center; }
.fs td { padding: 3px 6px; border-bottom: 1px solid #eee; }
.fs td.n { text-align: left; direction: ltr; white-space: nowrap; }
.fs td.n.b { font-weight: 700; }
.fs td.n.old { color: #b00; font-weight: 700; }
.fs td.nt { text-align: center; color: #555; white-space: nowrap; }
.fs td.lbl a { color: inherit; text-decoration: none; border-bottom: 1px dotted #888; }
.fs tr.grand td { font-weight: 700; border-top: 1px solid #000; border-bottom: 3px double #000; }
.fs tr.pct td { color: #555; font-size: 12px; }
@page { margin: 10mm; }
@media print {
  .no-print { display: none !important; }
  .nt-block { max-width: none; }
  .fs { font-size: 12px; }
  .fs td.lbl a { border: none; }
}
CSS
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P86_GROUP_ID', region => 'f', type => 'select', label => 'المجموعة', seq => 10, required => 1,
     lov => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE account_code IN ('1106','2101') ORDER BY account_code");
item(name => 'P86_AS_OF', region => 'f', type => 'date', label => 'في تاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P86_DAYS', region => 'f', type => 'select', label => 'طول الفترة', seq => 30, same_line => 1,
     lov => "SELECT column_value || ' يوم' d, column_value r FROM TABLE(sys.odcinumberlist(15, 30, 45, 60, 90))");
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
region(name => 'aging', title => 'أعمار الديون', type => 'plsql', no_header => 1, seq => 10, plsql => src('p86_aging.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P86_GROUP_ID IS NULL THEN SELECT MIN(account_id) INTO :P86_GROUP_ID FROM accounts WHERE account_code = '1106'; END IF;",
  "IF :P86_AS_OF IS NULL THEN :P86_AS_OF := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P86_DAYS IS NULL THEN :P86_DAYS := '30'; END IF;"));
branch_self('P86_GROUP_ID', 'P86_AS_OF', 'P86_DAYS');
end_page();

# =====================================================================
# 87 سجل التدقيق (للمدير فقط): من أضاف / عدّل / حذف ماذا ومتى (db/20_audit_log.sql)
# =====================================================================
page(id => 87, name => 'سجل التدقيق', alias => 'AUDIT', auth => 'IS_GM');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P87_FROM', region => 'f', type => 'date', label => 'من', seq => 10);
item(name => 'P87_TO', region => 'f', type => 'date', label => 'إلى', seq => 20, same_line => 1);
item(name => 'P87_TABLE', region => 'f', type => 'select', label => 'الشاشة / الجدول', null => 'الكل', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT DISTINCT table_name d, table_name r FROM audit_log ORDER BY 1");
item(name => 'P87_USER', region => 'f', type => 'select', label => 'المستخدم', null => 'الكل', submit => 1, seq => 40,
     lov => "SELECT DISTINCT changed_by d, changed_by r FROM audit_log WHERE changed_by IS NOT NULL ORDER BY 1");
item(name => 'P87_ACTION', region => 'f', type => 'select', label => 'العملية', null => 'الكل', submit => 1, seq => 50, same_line => 1,
     lov => "SELECT 'إضافة' d, 'I' r FROM dual UNION ALL SELECT 'تعديل', 'U' FROM dual UNION ALL SELECT 'حذف', 'D' FROM dual");
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
region(name => 'ir', title => 'سجل التدقيق', type => 'ir', sql => src('p87_ir.sql'), seq => 10, hide => ['AUDIT_ID']);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P87_FROM IS NULL THEN :P87_FROM := TO_CHAR(SYSDATE - 7, 'DD/MM/YYYY'); END IF;",
  "IF :P87_TO IS NULL THEN :P87_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;"));
branch_self('P87_FROM', 'P87_TO', 'P87_TABLE', 'P87_USER', 'P87_ACTION');
end_page();

# =====================================================================
# 88 إقفال السنة المالية (للمدير): معاينة ثم قيد إقفال إلى الأرباح المرحّلة وقفل السنة ، أو إعادة فتحها (db/21)
# =====================================================================
my $fy_run = sub {   # استدعاء إجراء الإقفال / الفتح ، والخطأ يظهر رسالة واضحة بدون رقم ORA
  my $proc = shift;
  return <<"SQL";
DECLARE l_msg VARCHAR2(4000);
BEGIN
  $proc(TO_NUMBER(:P88_YEAR), :APP_USER, l_msg);
  apex_application.g_print_success_message := l_msg;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  apex_error.add_error(p_message => REGEXP_REPLACE(SQLERRM, '^ORA-[0-9]+: ', ''), p_display_location => apex_error.c_inline_in_notification);
END;
SQL
};
page(id => 88, name => 'إقفال السنة المالية', alias => 'YEAR-CLOSE', auth => 'IS_GM', css => <<'CSS');
.nt-head { text-align: center; font-size: 17px; font-weight: 700; text-decoration: underline; margin: 4px 0 14px; direction: rtl; }
.nt-sub { font-size: 12px; font-weight: 400; text-decoration: none; color: #555; }
.nt-block { max-width: 900px; margin: 0 auto 18px; direction: rtl; }
.nt-title { font-size: 15px; font-weight: 700; margin: 0 0 6px; text-decoration: underline; }
.nt-empty { text-align: center; color: #777; }
.fy-st { margin: 0; padding-inline-start: 20px; line-height: 1.9; font-size: 14px; }
.fy-st .ok, .fy-st b.ok { color: #146b2d; }
.fy-st .bad, .fy-st b.bad { color: #b00; }
.fs { width: 100%; border-collapse: collapse; font-size: 14px; }
.fs th { border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 5px; text-align: center; }
.fs td { padding: 3px 6px; border-bottom: 1px solid #eee; }
.fs td.n { text-align: left; direction: ltr; white-space: nowrap; }
.fs td.nt { text-align: center; color: #555; white-space: nowrap; }
.fs tr.grand td { font-weight: 700; border-top: 1px solid #000; }
.fs tr.net td { border-bottom: 3px double #000; }
@media print { .no-print { display: none !important; } }
CSS
region(name => 'f', title => 'السنة المالية', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P88_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 10);
item(name => 'P88_CLOSED', region => 'f', type => 'hidden', seq => 20);
button(name => 'CLOSE_YEAR', region => 'f', label => 'إقفال السنة', hot => 1, seq => 10, cond => ":P88_CLOSED = 'N'",
       confirm => 'سيُنشأ قيد إقفال يصفّر الإيرادات والمصروفات إلى الأرباح المرحّلة، وتُقفل السنة فلا يُقبل فيها أي إدخال. متابعة؟');
button(name => 'REOPEN_YEAR', region => 'f', label => 'إعادة فتح السنة', seq => 20, cond => ":P88_CLOSED = 'Y'",
       confirm => 'سيُحذف قيد الإقفال وتُفتح السنة للإدخال مرة أخرى. متابعة؟');
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 30, js => 'window.print();');
region(name => 'pv', title => 'المعاينة', type => 'plsql', no_header => 1, seq => 10, plsql => src('p88_preview.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P88_YEAR IS NULL THEN SELECT MIN(fy_year) INTO :P88_YEAR FROM fiscal_years WHERE is_closed = 'N'; END IF;",
  "SELECT MAX(is_closed) INTO :P88_CLOSED FROM fiscal_years WHERE fy_year = TO_NUMBER(:P88_YEAR);"));
process(name => 'CLOSE_YEAR', seq => 10, button => 'CLOSE_YEAR', code => $fy_run->('fy_close'));
process(name => 'REOPEN_YEAR', seq => 20, button => 'REOPEN_YEAR', code => $fy_run->('fy_reopen'));
branch_self('P88_YEAR');
end_page();

# =====================================================================
# 90 حركات المخزون + 91 + 92 + 93
# =====================================================================
page(id => 90, name => 'حركة مخزون', alias => 'STOCK', title => '&P90_TITLE.', auth => 'IS_STORE',
     js => src('p90.js'),
     onload => "stk.init();\n" . sprintf($SAVE_KEYS, 'P90_STATUS', 'P90_STATUS', 'DRAFT',
       "['P90_COMPANY_ID','P90_TRANS_DATE','P90_WAREHOUSE_ID','P90_TO_WAREHOUSE_ID','P90_COUNTER_ACCOUNT_ID','P90_CURRENCY_CODE','P90_EXCHANGE_RATE','P90_DESCRIPTION']"));
region(name => 'head', title => '&P90_TITLE.', type => 'static', html => doc_status_html('P90_TRANS_NO', 'P90_STATUS', 'الرقم', 'P90'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P90_TRANS_ID',1],['P90_TRANS_TYPE',2],['P90_TRANS_NO',3],['P90_STATUS',4],['P90_TITLE',5]);
item(name => 'P90_COMPANY_ID', region => 'head', type => 'select', label => 'الشركة', lov => $LOV{companies}, seq => 10, required => 1);
item(name => 'P90_TRANS_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P90_WAREHOUSE_ID', region => 'head', type => 'select', label => 'المخزن', lov => $LOV{warehouses}, null => 1, seq => 30, required => 1);
item(name => 'P90_TO_WAREHOUSE_ID', region => 'head', type => 'select', label => 'إلى مخزن', lov => $LOV{warehouses}, null => 1, seq => 40, same_line => 1,
     cond => ":P90_TRANS_TYPE = 'TRANSFER'");
item(name => 'P90_COUNTER_ACCOUNT_ID', region => 'head', type => 'popup', label => 'الحساب المقابل', lov => $LOV{accounts4}, seq => 50, same_line => 1,
     cond => ":P90_TRANS_TYPE IN ('RECEIPT','ISSUE')");
item(name => 'P90_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 60, cond => ":P90_TRANS_TYPE IN ('RECEIPT','OPENING')");
item(name => 'P90_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 70, same_line => 1, cond => ":P90_TRANS_TYPE IN ('RECEIPT','OPENING')");
item(name => 'P90_DESCRIPTION', region => 'head', label => 'البيان', seq => 80, max => 500);
region(name => 'lines', title => 'الأصناف', type => 'static', seq => 20, html => '<div id="st_lines"></div>');
$draft = can_save('P90_STATUS');
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ (Ctrl+S)', js => "stk.save('DRAFT');", hot => 1, seq => 10, cond => $draft);
wf_setup(page => 90, region => 'lines', table => 'stock_trans', idcol => 'trans_id', id => 'P90_TRANS_ID',
         status => 'P90_STATUS', doc => 'STOCK', post => src('p90_post.sql'));
button(name => 'PRINT_A4', region => 'lines', label => 'طباعة A4', js => 'stk.print();', seq => 25, cond => ':P90_TRANS_ID IS NOT NULL');
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:90:&SESSION.::&DEBUG.:90:P90_TRANS_TYPE:&P90_TRANS_TYPE.', position => 'PREVIOUS', seq => 30);
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, cond => ':P90_TRANS_ID IS NOT NULL', code => <<'SQL');
DECLARE t stock_trans%ROWTYPE; r stock_trans%ROWTYPE;
BEGIN
  SELECT * INTO t FROM stock_trans WHERE trans_id = :P90_TRANS_ID;
  r := t;
  __WF90__
  IF NOT (:G_USER_ROLE = 'ADMIN' OR t.company_id = :G_COMPANY_ID) THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الحركة');
  END IF;
  :P90_TRANS_TYPE := t.trans_type; :P90_TRANS_NO := t.trans_no; :P90_COMPANY_ID := t.company_id;
  :P90_TRANS_DATE := TO_CHAR(t.trans_date, 'DD/MM/YYYY'); :P90_WAREHOUSE_ID := t.warehouse_id;
  :P90_TO_WAREHOUSE_ID := t.to_warehouse_id; :P90_COUNTER_ACCOUNT_ID := t.counter_account_id;
  :P90_CURRENCY_CODE := t.currency_code; :P90_EXCHANGE_RATE := t.exchange_rate;
  :P90_DESCRIPTION := t.description; :P90_STATUS := t.status;
END;
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P90_TRANS_TYPE IS NULL THEN :P90_TRANS_TYPE := 'RECEIPT'; END IF;",
  "IF :P90_TRANS_ID IS NULL THEN",
  '  IF :P90_COMPANY_ID IS NULL THEN :P90_COMPANY_ID := :G_COMPANY_ID; END IF;',
  "  IF :P90_STATUS IS NULL THEN :P90_STATUS := 'DRAFT'; END IF;",
  '  ' . date_default('P90_TRANS_DATE'), '  ' . base_cur_default('P90_CURRENCY_CODE', 'P90_EXCHANGE_RATE'),
  'END IF;',
  ":P90_TITLE := CASE :P90_TRANS_TYPE WHEN 'RECEIPT' THEN 'استلام بضاعة' WHEN 'ISSUE' THEN 'صرف داخلي' WHEN 'TRANSFER' THEN 'تحويل بين المخازن' WHEN 'COUNT' THEN 'تسوية جرد' WHEN 'OPENING' THEN 'إشعار إضافة - بضاعة أول المدة' WHEN 'DAMAGE' THEN 'فاتورة صرف توالف' WHEN 'DAMAGE_WO' THEN 'تصفير التوالف - قرار المدير' ELSE 'حركة مخزون' END;"));
ajax('INIT_DATA', src('p90_init.sql'));
ajax('SAVE_DOC',  src('p90_save.sql'));
branch_self('P90_TRANS_ID', 'P90_TRANS_TYPE');
end_page();

page(id => 91, name => 'قائمة حركات المخزون', alias => 'STOCKS', auth => 'IS_STORE');
my $p91 = src('p91_ir.sql');
$p91 =~ s/^SELECT t\.trans_id,/SELECT t.trans_id, t.trans_type AS trans_type_code,/;
region(name => 'ir', title => 'حركات المخزون', type => 'ir', sql => $p91, hide => ['TRANS_TYPE_CODE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:90:&SESSION.::&DEBUG.:90:P90_TRANS_ID,P90_TRANS_TYPE:#TRANS_ID#,#TRANS_TYPE_CODE#' });
end_page();

# أرصدة المخزن خلال فترة: المرحل ، الوارد ، المنصرف ، التالف ، الحالي (وبالعبوات الكبيرة) ، القيمة بسعر شراء الصغرى
page(id => 92, name => 'أرصدة المخزون', alias => 'STOCK-BAL', auth => 'IS_STORE');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P92_WAREHOUSE_ID', region => 'f', type => 'select', label => 'المخزن', lov => $LOV{warehouses}, null => '- اختر المخزن -',
     submit => 1, seq => 10, required => 1);
item(name => 'P92_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P92_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 30, same_line => 1, required => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
table_region(name => 'rep', title => 'أرصدة المخزن خلال الفترة (الكميات بالوحدة الصغرى)', sql => src('p92_report.sql'), seq => 10,
             cond => ':P92_WAREHOUSE_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P92_FROM IS NULL THEN :P92_FROM := '01/01/' || TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P92_TO IS NULL THEN :P92_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;"));
branch_self('P92_WAREHOUSE_ID', 'P92_FROM', 'P92_TO');
end_page();

# كرت العهدة بين تاريخين: رصيد أول المدة ، الحركات بالرصيد التراكمي ، الرصيد الختامي ، مع طباعة
page(id => 93, name => 'كارت العهدة', alias => 'ITEM-CARD', auth => 'IS_STORE',
     css => "\@media print { .no-print { display: none !important; } .jl-table { font-size: 12px; } }\n");
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P93_ITEM_ID', region => 'f', type => 'popup', label => 'الصنف', lov => "SELECT item_code || ' - ' || name_ar d, item_id r FROM items ORDER BY item_code", required => 1);
item(name => 'P93_WAREHOUSE_ID', region => 'f', type => 'select', label => 'المخزن', lov => $LOV{warehouses}, null => 1, seq => 20, same_line => 1, required => 1);
item(name => 'P93_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 30, same_line => 1, required => 1);
item(name => 'P93_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 40, same_line => 1, required => 1);
item(name => 'P93_INFO', region => 'f', type => 'hidden', seq => 50);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();', cond => ':P93_ITEM_ID IS NOT NULL AND :P93_WAREHOUSE_ID IS NOT NULL');
table_region(name => 'card', title => 'كرت العهدة: &P93_INFO.', sql => src('p93_report.sql'), seq => 10,
             cond => ':P93_ITEM_ID IS NOT NULL AND :P93_WAREHOUSE_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => <<'SQL');
BEGIN
  IF :P93_FROM IS NULL THEN :P93_FROM := '01/01/' || TO_CHAR(SYSDATE, 'YYYY'); END IF;
  IF :P93_TO   IS NULL THEN :P93_TO   := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;
  -- عنوان الكرت: الصنف (الوحدة الصغرى) - المخزن - الفترة
  IF :P93_ITEM_ID IS NOT NULL AND :P93_WAREHOUSE_ID IS NOT NULL THEN
    SELECT i.item_code || ' - ' || i.name_ar || ' (الوحدة: ' || u.name_ar || ')'
           || ' | المخزن: ' || (SELECT w.name_ar FROM warehouses w WHERE w.warehouse_id = TO_NUMBER(:P93_WAREHOUSE_ID))
           || ' | من ' || :P93_FROM || ' إلى ' || :P93_TO
    INTO   :P93_INFO
    FROM   items i JOIN units u ON u.unit_id = i.base_unit_id
    WHERE  i.item_id = TO_NUMBER(:P93_ITEM_ID);
  END IF;
EXCEPTION WHEN NO_DATA_FOUND THEN :P93_INFO := NULL;
END;
SQL
branch_self('P93_ITEM_ID', 'P93_WAREHOUSE_ID', 'P93_FROM', 'P93_TO');
end_page();

# =====================================================================
# 96 ملخص الخزائن والبنوك: لكل خزينة / بنك رصيد أول المدة والمقبوض والمدفوع والرصيد الختامي (يوم أو فترة)
# =====================================================================
page(id => 96, name => 'ملخص الخزائن والبنوك', alias => 'CASH-SUMMARY', auth => 'IS_ACCOUNTANT', css => <<'CSS');
.nt-head { text-align: center; font-size: 17px; font-weight: 700; text-decoration: underline; margin: 4px 0 14px; direction: rtl; }
.nt-block { max-width: 1000px; margin: 0 auto 18px; direction: rtl; }
.nt-empty { text-align: center; color: #777; }
.fs { width: 100%; border-collapse: collapse; font-size: 14px; }
.fs th { border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 5px; text-align: center; }
.fs td { padding: 3px 6px; border-bottom: 1px solid #eee; }
.fs td.n { text-align: left; direction: ltr; white-space: nowrap; }
.fs td.n.b { font-weight: 700; }
.fs td.n.in { color: #146b2d; }
.fs td.n.out { color: #b00; }
.fs td.nt { text-align: center; color: #555; white-space: nowrap; }
.fs td.lbl a { color: inherit; text-decoration: none; border-bottom: 1px dotted #888; }
.fs tr.sec td { font-weight: 700; text-decoration: underline; padding-top: 10px; border-bottom: none; }
.fs tr.tot td { font-weight: 700; border-top: 1px solid #000; }
.fs tr.grand td { font-weight: 700; border-top: 1px solid #000; border-bottom: 3px double #000; }
@page { margin: 10mm; }
@media print {
  .no-print { display: none !important; }
  .nt-block { max-width: none; }
  .fs { font-size: 12px; }
  .fs td.lbl a { border: none; }
}
CSS
region(name => 'f', title => 'الفترة', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P96_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 10, required => 1);
item(name => 'P96_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 20, same_line => 1, required => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
region(name => 'cash', title => 'ملخص الخزائن والبنوك', type => 'plsql', no_header => 1, seq => 10, plsql => src('p96_cash.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P96_FROM IS NULL THEN :P96_FROM := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P96_TO IS NULL THEN :P96_TO := :P96_FROM; END IF;"));
branch_self('P96_FROM', 'P96_TO');
end_page();

# =====================================================================
# 100 مسير الرواتب + 101 قسيمة + 102 التوزيع
# =====================================================================
page(id => 100, name => 'مسير الرواتب', alias => 'PAYROLL', auth => 'IS_HR');
region(name => 'f', title => 'مسير الرواتب', type => 'static', seq => 5,
       html => '<div>الحالة: <span class="doc-status doc-status--&P100_STATUS.">&P100_STATUS.</span></div>');
item(name => 'P100_RUN_ID', region => 'f', type => 'hidden', seq => 1);
item(name => 'P100_STATUS', region => 'f', type => 'hidden', seq => 2);
item(name => 'P100_PERIOD', region => 'f', type => 'select', label => 'الشهر', lov => $LOV{periods}, submit => 1, seq => 10);
item(name => 'P100_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{all_companies}, null => 'كل الشركات', submit => 1, seq => 20, same_line => 1);
button(name => 'CALC', region => 'f', label => 'احتساب / إعادة احتساب', seq => 10, cond => ":P100_STATUS IS NULL OR :P100_STATUS = 'DRAFT'");
button(name => 'APPROVE', region => 'f', label => 'اعتماد وإنشاء القيود', hot => 1, seq => 20, cond => ":P100_STATUS = 'DRAFT'", confirm => 'اعتماد المسير وإنشاء القيود؟');
button(name => 'CANCEL_RUN', region => 'f', label => 'إلغاء المسير', position => 'PREVIOUS', seq => 30, cond => ":P100_STATUS = 'DRAFT'");
region(name => 'ir', title => 'كشف المسير', type => 'ir', sql => src('p100_ir.sql'), seq => 10, cond => ':P100_RUN_ID IS NOT NULL',
       links => { 'الموظف' => 'f?p=&APP_ID.:101:&SESSION.::&DEBUG.:101:P101_PLINE_ID:#PLINE_ID#' });
process(name => 'RUN', point => 'BEFORE_HEADER', seq => 10, code => join("\n",
  "IF :P100_PERIOD IS NULL THEN :P100_PERIOD := TO_CHAR(SYSDATE, 'YYYYMM'); END IF;",
  "SELECT MAX(run_id) INTO :P100_RUN_ID FROM payroll_runs WHERE pay_period = :P100_PERIOD AND NVL(company_id, 0) = NVL(:P100_COMPANY_ID, 0) AND status <> 'CANCELLED';",
  "IF :P100_RUN_ID IS NOT NULL THEN SELECT status INTO :P100_STATUS FROM payroll_runs WHERE run_id = :P100_RUN_ID; ELSE :P100_STATUS := NULL; END IF;"));
check(name => 'CHECK_OVERLAP', seq => 10, button => 'CALC', code => src('p100_val1.sql'));
check(name => 'CHECK_FY_CALC', seq => 20, button => 'CALC', code => src('p100_val2.sql'));
check(name => 'CHECK_FY_APP',  seq => 30, button => 'APPROVE', code => src('p100_val2.sql'));
process(name => 'CALC_PAYROLL', seq => 40, button => 'CALC', code => guard(src('p100_calc.sql')));
process(name => 'APPROVE_PAYROLL', seq => 50, button => 'APPROVE', code => guard(src('p100_approve.sql')));
process(name => 'CANCEL_RUN', seq => 60, button => 'CANCEL_RUN', code => "BEGIN\n" . src('p100_cancel.sql') . "END;");
branch_self();
end_page();

page(id => 101, name => 'قسيمة الراتب', alias => 'PAYSLIP', auth => 'IS_HR');
region(name => 'h', title => 'قسيمة الراتب', type => 'static', html => '<button type="button" class="t-Button" onclick="window.print()">طباعة</button>', seq => 1);
item(name => 'P101_PLINE_ID', region => 'h', type => 'hidden');
table_region(name => 'head', title => 'بيانات الموظف', sql => src('p101_head.sql'), seq => 10);
table_region(name => 'lines', title => 'البنود', sql => src('p101_lines.sql'), seq => 20);
end_page();

page(id => 102, name => 'توزيع الرواتب على الشركات', alias => 'PAYROLL-DIST', auth => 'IS_HR');
region(name => 'f', title => 'الفترة', type => 'static', html => '', seq => 5);
item(name => 'P102_FROM', region => 'f', type => 'select', label => 'من شهر', lov => $LOV{periods}, submit => 1);
item(name => 'P102_TO', region => 'f', type => 'select', label => 'إلى شهر', lov => $LOV{periods}, submit => 1, seq => 20, same_line => 1);
region(name => 'ir', title => 'التوزيع', type => 'ir', sql => src('p102_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P102_FROM IS NULL THEN :P102_FROM := TO_CHAR(SYSDATE, 'YYYY') || '01'; END IF;",
  "IF :P102_TO IS NULL THEN :P102_TO := TO_CHAR(SYSDATE, 'YYYYMM'); END IF;"));
end_page();

# =====================================================================
# 120 الموازنة + 121 مقابل الفعلي
# =====================================================================
page(id => 120, name => 'الموازنة التقديرية', alias => 'BUDGET', auth => 'IS_ACCOUNTANT', js => src('p120.js'), onload => 'bud.init();');
region(name => 'f', title => 'الموازنة', type => 'static', seq => 5,
       html => '<div>الحالة: <span class="doc-status doc-status--&P120_STATUS.">&P120_STATUS.</span></div>');
item(name => 'P120_BUDGET_ID', region => 'f', type => 'hidden', seq => 1);
item(name => 'P120_STATUS', region => 'f', type => 'hidden', seq => 2);
item(name => 'P120_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, submit => 1, seq => 10);
item(name => 'P120_FY_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 20, same_line => 1);
item(name => 'P120_NAME', region => 'f', label => 'الاسم', seq => 30, same_line => 1);
region(name => 'lines', title => 'بنود الموازنة', type => 'static', seq => 10, html => '<div id="bud_lines" style="overflow-x:auto"></div>');
button(name => 'SAVE', region => 'lines', label => 'حفظ', js => "bud.save('DRAFT');", seq => 10, cond => ":P120_STATUS IS NULL OR :P120_STATUS = 'DRAFT'");
button(name => 'APPROVE', region => 'lines', label => 'اعتماد', js => "bud.save('APPROVE');", hot => 1, seq => 20, auth => 'IS_GM', cond => ":P120_STATUS IS NULL OR :P120_STATUS = 'DRAFT'");
button(name => 'COPY_BUDGET', region => 'lines', label => 'نسخ من موازنة السنة السابقة', js => "bud.load('PREV_BUDGET');", position => 'PREVIOUS', seq => 30);
button(name => 'COPY_ACTUAL', region => 'lines', label => 'نسخ من الفعلي للسنة السابقة', js => "bud.load('PREV_ACTUAL');", position => 'PREVIOUS', seq => 40);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  'IF :P120_COMPANY_ID IS NULL THEN :P120_COMPANY_ID := :G_COMPANY_ID; END IF;',
  "IF :P120_FY_YEAR IS NULL THEN :P120_FY_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  'SELECT MAX(budget_id), MAX(status), MAX(name_ar) INTO :P120_BUDGET_ID, :P120_STATUS, :P120_NAME FROM budgets WHERE company_id = :P120_COMPANY_ID AND fy_year = :P120_FY_YEAR;',
  "IF :P120_NAME IS NULL THEN :P120_NAME := 'موازنة ' || :P120_FY_YEAR; END IF;"));
ajax('INIT_DATA', src('p120_init.sql'));
ajax('SAVE_DOC', src('p120_save.sql'));
branch_self();
end_page();

page(id => 121, name => 'الموازنة مقابل الفعلي', alias => 'BUDGET-ACTUAL', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P121_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات (مجمّع)', submit => 1);
item(name => 'P121_FY_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 20, same_line => 1);
# الشهر: "كل الشهور" = السنة كاملة ، وطريقة العرض: تراكمي حتى الشهر أو الشهر وحده
item(name => 'P121_TO_MONTH', region => 'f', type => 'select', label => 'الشهر', null => 'كل الشهور', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT DECODE(LEVEL, 1,'يناير',2,'فبراير',3,'مارس',4,'أبريل',5,'مايو',6,'يونيو',7,'يوليو',8,'أغسطس',9,'سبتمبر',10,'أكتوبر',11,'نوفمبر','ديسمبر') d, LEVEL r FROM dual CONNECT BY LEVEL <= 12");
item(name => 'P121_MODE', region => 'f', type => 'select', label => 'طريقة العرض', submit => 1, seq => 35, same_line => 1,
     lov => "SELECT 'تراكمي حتى الشهر' d, 'CUM' r FROM dual UNION ALL SELECT 'الشهر وحده', 'ONE' FROM dual");
item(name => 'P121_LEVEL', region => 'f', type => 'select', label => 'المستوى', submit => 1, seq => 40, same_line => 1,
     lov => "SELECT 'المستوى ' || (LEVEL + 1) d, LEVEL + 1 r FROM dual CONNECT BY LEVEL <= 3");
region(name => 'ir', title => 'الموازنة مقابل الفعلي', type => 'ir', sql => src('p121_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P121_FY_YEAR IS NULL THEN :P121_FY_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P121_MODE IS NULL THEN :P121_MODE := 'CUM'; END IF;",
  "IF :P121_LEVEL IS NULL THEN :P121_LEVEL := 4; END IF;"));
# القوائم تبقى على اختيارها بعد الإرسال
branch_self('P121_COMPANY_ID', 'P121_FY_YEAR', 'P121_TO_MONTH', 'P121_MODE', 'P121_LEVEL');
end_page();

# =====================================================================
# 125 بنود ميزانية الفروع (إدخال يدوي) + 126 الميزانية المجمّعة
# =====================================================================
page(id => 125, name => 'بنود ميزانية الفروع', alias => 'BRANCH-BAL', auth => 'IS_ACCOUNTANT', js => src('p125.js'), onload => 'brb.init();');
region(name => 'f', title => 'الفرع وتاريخ الميزانية', type => 'static', seq => 5,
       html => '<div class="jl-hint">أدخل أرصدة حسابات الفرع كما في ميزانيته في هذا التاريخ (بالعملة الأساسية). يجب أن يتساوى المدين مع الدائن.</div>');
item(name => 'P125_COMPANY_ID', region => 'f', type => 'select', label => 'الفرع', lov => $LOV{subs}, null => 1, required => 1);
item(name => 'P125_AS_OF_DATE', region => 'f', type => 'date', label => 'تاريخ الميزانية', seq => 20, same_line => 1, required => 1);
region(name => 'lines', title => 'البنود', type => 'static', seq => 10,
       html => "<div id=\"brb_lines\"></div>\n<div style=\"margin-top:8px\">الفرق: <span id=\"brb_diff\" class=\"jv-diff ok\">0.00</span></div>");
button(name => 'SAVE', region => 'lines', label => 'حفظ (Ctrl+S)', js => 'brb.save();', hot => 1);
ajax('INIT_DATA', src('p125_init.sql'));
ajax('SAVE_DOC', src('p125_save.sql'));
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => "IF :P125_AS_OF_DATE IS NULL THEN :P125_AS_OF_DATE := TO_CHAR(LAST_DAY(ADD_MONTHS(SYSDATE, -1)), 'DD/MM/YYYY'); END IF;");
end_page();

page(id => 126, name => 'الميزانية المجمّعة', alias => 'CONSOLIDATED', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P126_AS_OF_DATE', region => 'f', type => 'date', label => 'حتى تاريخ', seq => 10);
item(name => 'P126_LEVEL', region => 'f', type => 'select', label => 'المستوى', seq => 20, same_line => 1, submit => 1,
     lov => "SELECT 'المستوى ' || LEVEL d, LEVEL r FROM dual CONNECT BY LEVEL <= 4");
item(name => 'P126_EXCLUDE', region => 'f', type => 'select', label => 'استبعاد الحسابات البينية', lov => $LOV{yn}, seq => 30, same_line => 1, submit => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1);
region(name => 'rep', title => 'الشركة الأم + الفروع = المجموعة', type => 'plsql', plsql => src('p126_report.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P126_AS_OF_DATE IS NULL THEN :P126_AS_OF_DATE := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P126_LEVEL IS NULL THEN :P126_LEVEL := 2; END IF;",
  "IF :P126_EXCLUDE IS NULL THEN :P126_EXCLUDE := 'Y'; END IF;"));
branch_self('P126_AS_OF_DATE', 'P126_LEVEL', 'P126_EXCLUDE');
end_page();

# =====================================================================
# 1 لوحة المدير العام
# =====================================================================
# 58 الوردية (فتح / إغلاق / مراجعة / اعتماد) + 59 قائمة الورديات
# =====================================================================
page(id => 58, name => 'الوردية', alias => 'SHIFT', auth => 'IS_STORE');
region(name => 'head', title => 'الوردية', type => 'static', seq => 10,
       html => doc_status_html('P58_SHIFT_NO', 'P58_STATUS', 'رقم الوردية', 'P58') . '<div class="doc-meta">&P58_INFO.</div>');
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1])
  for (['P58_SHIFT_ID',1],['P58_SHIFT_NO',2],['P58_STATUS',3],['P58_USER',4],['P58_INFO',5],['P58_HAS_OPEN',6]);
item(name => 'P58_NOTES', region => 'head', label => 'ملاحظات الإغلاق', seq => 20, max => 500, cond => ":P58_STATUS IN ('OPEN','RETURNED')");
button(name => 'OPEN_SHIFT', region => 'head', label => 'فتح وردية جديدة', hot => 1, seq => 5,
       cond => "NVL(:P58_HAS_OPEN, 'N') = 'N' AND :G_USER_ROLE IN ('ADMIN','ENTRY')");
button(name => 'CLOSE_SHIFT', region => 'head', label => 'إغلاق الوردية', hot => 1, seq => 6,
       cond => ":P58_STATUS IN ('OPEN','RETURNED') AND (:P58_USER = :APP_USER OR :G_USER_ROLE = 'ADMIN')",
       confirm => 'إغلاق الوردية وإرسالها للمراجعة والاعتماد؟');
button(name => 'SALES', region => 'head', label => 'فاتورة مبيعات', seq => 7, cond => ":P58_STATUS = 'OPEN' AND :P58_USER = :APP_USER",
       url => 'f?p=&APP_ID.:50:&SESSION.::&DEBUG.:50:P50_INVOICE_TYPE:SALE');
button(name => 'LIST', region => 'head', label => 'قائمة الورديات', seq => 8, position => 'PREVIOUS', url => 'f?p=&APP_ID.:59:&SESSION.::&DEBUG.:59::');
wf_setup(page => 58, region => 'head', table => 'sales_shifts', idcol => 'shift_id', id => 'P58_SHIFT_ID',
         status => 'P58_STATUS', doc => 'SHIFT', post => src('p58_post.sql'));
table_region(name => 'sum', title => 'ملخص الوردية حسب طريقة الدفع والحساب', sql => src('p58_summary.sql'), seq => 20, cond => ':P58_SHIFT_ID IS NOT NULL');
table_region(name => 'inv', title => 'فواتير الوردية', sql => src('p58_invoices.sql'), seq => 30, cond => ':P58_SHIFT_ID IS NOT NULL');
process(name => 'LOAD', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p58_load.sql', 'P58'));
process(name => 'OPEN_SHIFT', seq => 10, button => 'OPEN_SHIFT', code => src('p58_open.sql'));
process(name => 'CLOSE_SHIFT', seq => 20, button => 'CLOSE_SHIFT', code => src('p58_close.sql'));
branch_self('P58_SHIFT_ID');
end_page();

page(id => 59, name => 'قائمة الورديات', alias => 'SHIFTS', auth => 'IS_STORE');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P59_STATUS', region => 'f', type => 'select', label => 'الحالة', null => 'الكل', submit => 1,
     lov => "SELECT 'مفتوحة' d, 'OPEN' r FROM dual UNION ALL SELECT 'مغلقة - بانتظار المراجعة', 'DRAFT' FROM dual UNION ALL SELECT 'معادة للبائع', 'RETURNED' FROM dual UNION ALL SELECT 'مُراجَعة - بانتظار الاعتماد', 'REVIEWED' FROM dual UNION ALL SELECT 'معتمدة ومرحّلة', 'POSTED' FROM dual");
region(name => 'ir', title => 'الورديات', type => 'ir', sql => src('p59_ir.sql'), seq => 10,
       links => { 'رقم الوردية' => 'f?p=&APP_ID.:58:&SESSION.::&DEBUG.:58:P58_SHIFT_ID:#SHIFT_ID#' });
end_page();

# =====================================================================
# 52 تقرير المبيعات اليومي: حسب المستخدم وطريقة الدفع والحساب المدفوع به
# =====================================================================
page(id => 52, name => 'تقرير المبيعات اليومي', alias => 'DAILY-SALES', auth => 'IS_STORE');
region(name => 'f', title => 'الفترة', type => 'static', html => '', seq => 5);
item(name => 'P52_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 10);
item(name => 'P52_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 20, same_line => 1);
item(name => 'P52_USER', region => 'f', type => 'select', label => 'المستخدم', seq => 30, same_line => 1, null => 'كل المستخدمين',
     lov => "SELECT full_name || ' (' || user_name || ')' d, user_name r FROM app_users ORDER BY full_name");
button(name => 'GO', region => 'f', label => 'عرض', seq => 10, hot => 1);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
table_region(name => 'user',   title => 'حسب المستخدم', sql => src('p52_user.sql'), seq => 10);
table_region(name => 'method', title => 'حسب طريقة الدفع', sql => src('p52_method.sql'), seq => 20);
table_region(name => 'acc',    title => 'حسب الحساب المدفوع به (الخزينة / البنك / العملاء)', sql => src('p52_account.sql'), seq => 30);
region(name => 'ir', title => 'تفاصيل الفواتير', type => 'ir', sql => src('p52_detail.sql'), seq => 40);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 10, code => join("\n", date_default('P52_FROM'), date_default('P52_TO')));
branch_self('P52_FROM', 'P52_TO', 'P52_USER');
end_page();

# =====================================================================
# 89 تحليل المبيعات والأرباح: حسب الصنف / العميل / الصنف والعميل ، مع التكلفة الفعلية من حركة المخزون والربح والهامش
# =====================================================================
page(id => 89, name => 'تحليل المبيعات والأرباح', alias => 'SALES-PROFIT', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5, class => 'no-print');
item(name => 'P89_FROM', region => 'f', type => 'date', label => 'من تاريخ', seq => 10, required => 1);
item(name => 'P89_TO',   region => 'f', type => 'date', label => 'إلى تاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P89_GROUP', region => 'f', type => 'select', label => 'التجميع', seq => 30, same_line => 1, submit => 1,
     lov => "SELECT 'حسب الصنف' d, 'ITEM' r FROM dual UNION ALL SELECT 'حسب العميل', 'CUSTOMER' FROM dual UNION ALL SELECT 'حسب الصنف والعميل', 'ITEM_CUSTOMER' FROM dual");
item(name => 'P89_WAREHOUSE_ID', region => 'f', type => 'select', label => 'المخزن', lov => $LOV{warehouses}, null => 'كل المخازن', submit => 1, seq => 40);
item(name => 'P89_PAY', region => 'f', type => 'select', label => 'طريقة الدفع', null => 'الكل', submit => 1, seq => 50, same_line => 1,
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'آجل', 'CREDIT' FROM dual");
button(name => 'GO', region => 'f', label => 'عرض', hot => 1, seq => 10);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 20, js => 'window.print();');
region(name => 'ir', title => 'المبيعات والأرباح (القيم بالعملة الأساسية ، الكميات بالوحدة الصغرى ، التكلفة من حركة المخزون)',
       type => 'ir', sql => src('p89_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P89_FROM IS NULL THEN :P89_FROM := '01/01/' || TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P89_TO IS NULL THEN :P89_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P89_GROUP IS NULL THEN :P89_GROUP := 'ITEM'; END IF;"));
branch_self('P89_FROM', 'P89_TO', 'P89_GROUP', 'P89_WAREHOUSE_ID', 'P89_PAY');
end_page();

# =====================================================================
# 94 أصناف قاربت انتهاء صلاحيتها
# =====================================================================
page(id => 94, name => 'أصناف قاربت انتهاء الصلاحية', alias => 'EXPIRY', auth => 'IS_STORE');
region(name => 'f', title => 'الفترة', type => 'static', html => '', seq => 5);
item(name => 'P94_MONTHS', region => 'f', type => 'select', label => 'تنتهي خلال', seq => 10, submit => 1,
     lov => "SELECT LEVEL || ' شهر' d, LEVEL r FROM dual CONNECT BY LEVEL <= 12");
region(name => 'ir', title => 'الأصناف المنتهية أو التي تنتهي خلال الفترة', type => 'ir', sql => src('p94_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 10, code => "IF :P94_MONTHS IS NULL THEN :P94_MONTHS := 3; END IF;");
end_page();

# =====================================================================
# 105 الحافز السنوي (النسبة × المرتبات المصروفة خلال السنة) + 106 القائمة
# =====================================================================
page(id => 105, name => 'الحافز السنوي', alias => 'ANNUAL-INCENTIVE', auth => 'IS_HR',
     onload => sprintf($SAVE_KEYS, 'P105_STATUS', '', '', "['P105_FY_YEAR','P105_PERCENT','P105_BASIS','P105_EMP_TYPE','P105_DESCRIPTION']"));
region(name => 'head', title => 'الحافز السنوي', type => 'static', seq => 10,
       html => doc_status_html('P105_INC_NO', 'P105_STATUS', 'رقم الحافز', 'P105') . '<div class="doc-meta">الإجمالي: <b>&P105_TOTAL.</b></div>');
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1])
  for (['P105_INC_ID',1],['P105_INC_NO',2],['P105_STATUS',3],['P105_JOURNAL_ID',4],['P105_TOTAL',5]);
item(name => 'P105_FY_YEAR', region => 'head', type => 'select', label => 'السنة', lov => $LOV{years}, seq => 10, required => 1);
item(name => 'P105_PERCENT', region => 'head', label => 'النسبة %', seq => 20, same_line => 1, required => 1);
item(name => 'P105_BASIS', region => 'head', type => 'select', label => 'أساس الحساب', seq => 30, same_line => 1,
     lov => "SELECT 'المرتب الأساسي المصروف' d, 'BASIC' r FROM dual UNION ALL SELECT 'إجمالي الاستحقاقات المصروفة', 'GROSS' FROM dual");
item(name => 'P105_EMP_TYPE', region => 'head', type => 'select', label => 'نوع الموظفين', seq => 40, null => 'الكل',
     lov => "SELECT 'موظف' d, 'EMPLOYEE' r FROM dual UNION ALL SELECT 'عامل', 'WORKER' FROM dual UNION ALL SELECT 'عسكري', 'SOLDIER' FROM dual UNION ALL SELECT 'ضابط', 'OFFICER' FROM dual");
item(name => 'P105_DESCRIPTION', region => 'head', label => 'البيان', seq => 50, same_line => 1, max => 500);
button(name => 'CALC', region => 'head', label => 'حساب وحفظ', hot => 1, seq => 10, cond => can_save('P105_STATUS'));
button(name => 'NEW', region => 'head', label => 'جديد', url => 'f?p=&APP_ID.:105:&SESSION.::&DEBUG.:105::', position => 'PREVIOUS', seq => 30);
button(name => 'LIST', region => 'head', label => 'قائمة الحوافز', url => 'f?p=&APP_ID.:106:&SESSION.::&DEBUG.:106::', position => 'PREVIOUS', seq => 35);
button(name => 'SHOW_JV', region => 'head', label => 'عرض القيد', position => 'PREVIOUS', seq => 40, cond => ":P105_STATUS = 'POSTED'",
       url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P105_JOURNAL_ID.');
wf_setup(page => 105, region => 'head', table => 'annual_incentives', idcol => 'inc_id', id => 'P105_INC_ID',
         status => 'P105_STATUS', doc => 'ANNUAL_INC', post => src('p105_post.sql'));
table_region(name => 'lines', title => 'الموظفون ومبالغ الحافز', sql => src('p105_lines.sql'), seq => 20, cond => ':P105_INC_ID IS NOT NULL');
process(name => 'LOAD', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p105_load.sql', 'P105'), cond => ':P105_INC_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ':P105_INC_ID IS NULL', code => join("\n",
  "IF :P105_FY_YEAR IS NULL THEN :P105_FY_YEAR := EXTRACT(YEAR FROM SYSDATE); END IF;",
  "IF :P105_BASIS IS NULL THEN :P105_BASIS := 'BASIC'; END IF;", ":P105_STATUS := NULL;"));
process(name => 'CALC', seq => 10, button => 'CALC', code => src('p105_calc.sql'));
branch_self('P105_INC_ID');
end_page();

page(id => 106, name => 'قائمة الحوافز السنوية', alias => 'ANNUAL-INCENTIVES', auth => 'IS_HR');
region(name => 'ir', title => 'الحوافز السنوية', type => 'ir', sql => src('p106_ir.sql'), seq => 10,
       links => { 'الرقم' => 'f?p=&APP_ID.:105:&SESSION.::&DEBUG.:105:P105_INC_ID:#INC_ID#' });
end_page();

# =====================================================================
# 122 الخطة (الموازنة التقديرية) للإدارات بالأرباع + 123 تقرير الإيضاحات
# =====================================================================
page(id => 122, name => 'الخطة التقديرية للإدارات', alias => 'DEPT-PLAN', auth => 'IS_ACCOUNTANT',
     js => src('p122.js'),
     onload => "plan.init();\n" . sprintf($SAVE_KEYS, 'P122_STATUS', '', '', "['P122_FY_YEAR','P122_DEPT_ID','P122_DESCRIPTION']"));
region(name => 'head', title => 'الخطة التقديرية', type => 'static', seq => 10,
       html => '<div class="doc-meta">الحالة: <span class="doc-status doc-status--&P122_STATUS.">&P122_STATUS.</span>'
             . '<span class="doc-wf">&P122_WF_INFO.</span><span class="doc-note">&P122_RETURN_NOTE.</span></div>');
item(name => 'P122_PLAN_ID', region => 'head', type => 'hidden', seq => 1);
item(name => 'P122_STATUS',  region => 'head', type => 'hidden', seq => 2);
item(name => 'P122_FY_YEAR', region => 'head', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 10, required => 1);
item(name => 'P122_DEPT_ID', region => 'head', type => 'select', label => 'الإدارة', null => 1, submit => 1, seq => 20, same_line => 1, required => 1,
     lov => "SELECT dept_code || ' - ' || name_ar d, dept_id r FROM departments WHERE is_active = 'Y' ORDER BY dept_code");
item(name => 'P122_DESCRIPTION', region => 'head', label => 'البيان', seq => 30, same_line => 1, max => 500);
region(name => 'lines', title => 'بنود الميزانية بالأرباع', type => 'static', seq => 20, cond => ':P122_DEPT_ID IS NOT NULL',
       html => '<div id="plan_lines" style="overflow-x:auto"></div>');
button(name => 'SAVE', region => 'lines', label => 'حفظ (Ctrl+S)', js => 'plan.save();', hot => 1, seq => 10, cond => can_save('P122_STATUS'));
button(name => 'REPORT', region => 'lines', label => 'تقرير الإيضاحات', position => 'PREVIOUS', seq => 30,
       url => 'f?p=&APP_ID.:123:&SESSION.::&DEBUG.:123:P123_FY_YEAR:&P122_FY_YEAR.');
wf_setup(page => 122, region => 'lines', table => 'budget_plans', idcol => 'plan_id', id => 'P122_PLAN_ID',
         status => 'P122_STATUS', doc => 'BUDGET_PLAN');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5,
        code => "IF :P122_FY_YEAR IS NULL THEN :P122_FY_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;");
process(name => 'LOAD', point => 'BEFORE_HEADER', seq => 10, code => src_wf('p122_load.sql', 'P122'));
ajax('INIT_DATA', src('p122_init.sql'));
ajax('SAVE_DOC',  src('p122_save.sql'));
branch_self('P122_PLAN_ID', 'P122_FY_YEAR', 'P122_DEPT_ID');
end_page();

page(id => 123, name => 'تقرير الخطة حسب الإيضاح', alias => 'PLAN-NOTES', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P123_FY_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 10);
item(name => 'P123_BITEM_ID', region => 'f', type => 'select', label => 'الإيضاح', null => 'كل الإيضاحات', submit => 1, seq => 20, same_line => 1,
     lov => "SELECT note_no || ' - ' || name_ar d, bitem_id r FROM budget_items ORDER BY sort_order, note_no");
item(name => 'P123_ONLY_APPROVED', region => 'f', type => 'select', label => 'الخطط', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT 'كل الخطط' d, 'N' r FROM dual UNION ALL SELECT 'المعتمدة فقط', 'Y' FROM dual");
# كل ربع على حدة: اختيار الربع يعرض مبلغه فقط (الخطة والفعلي والانحراف)
item(name => 'P123_QUARTER', region => 'f', type => 'select', label => 'الربع', null => 'كل الأرباع', submit => 1, seq => 40, same_line => 1,
     lov => "SELECT 'الربع الأول' d, '1' r FROM dual UNION ALL SELECT 'الربع الثاني', '2' FROM dual UNION ALL SELECT 'الربع الثالث', '3' FROM dual UNION ALL SELECT 'الربع الرابع', '4' FROM dual");
item(name => 'P123_Q_NAME', region => 'f', type => 'hidden', seq => 50);
button(name => 'PRINT', region => 'f', label => 'طباعة', seq => 10, js => 'window.print();');
table_region(name => 'rep', title => 'الخطة بالأرباع لكل إيضاح: الإدارات ثم الإجمالي والفعلي والانحراف', sql => src('p123_report.sql'), seq => 10,
             cond => ':P123_QUARTER IS NULL');
{
  # نفس التقرير لربع واحد: عمود المبلغ للربع المختار فقط
  my $base = src('p123_report.sql');
  $base =~ s/\s*ORDER BY r\.sort_key\s*\z//s or die 'p123 order by';
  my $qsql = "SELECT sort_key, \"رقم الإيضاح\", \"البند\", \"الإدارة / البيان\",\n"
           . "       CASE :P123_QUARTER WHEN '1' THEN \"الربع الأول\" WHEN '2' THEN \"الربع الثاني\"\n"
           . "                          WHEN '3' THEN \"الربع الثالث\" ELSE \"الربع الرابع\" END AS \"المبلغ\"\n"
           . "FROM (\n$base\n)\nORDER BY sort_key";
  table_region(name => 'rep_q', title => 'الخطة لكل إيضاح - &P123_Q_NAME.: الإدارات ثم الإجمالي والفعلي والانحراف', sql => $qsql, seq => 11,
               cond => ':P123_QUARTER IS NOT NULL');
}
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 5, code => join("\n",
  "IF :P123_FY_YEAR IS NULL THEN :P123_FY_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P123_ONLY_APPROVED IS NULL THEN :P123_ONLY_APPROVED := 'N'; END IF;",
  ":P123_Q_NAME := CASE :P123_QUARTER WHEN '1' THEN 'الربع الأول' WHEN '2' THEN 'الربع الثاني' WHEN '3' THEN 'الربع الثالث' WHEN '4' THEN 'الربع الرابع' END;"));
# القوائم تبقى على اختيارها بعد الإرسال
branch_self('P123_FY_YEAR', 'P123_BITEM_ID', 'P123_ONLY_APPROVED', 'P123_QUARTER');
end_page();

# =====================================================================
page(id => 1, name => 'الرئيسية', alias => 'HOME');
region(name => 'f', title => 'لوحة المدير العام', type => 'static', html => '', seq => 5);
item(name => 'P1_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات', submit => 1);
item(name => 'P1_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 20, same_line => 1);
item(name => 'P1_MODE', region => 'f', type => 'select', label => 'العرض', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT 'كل شركة منفصلة' d, 'SEP' r FROM dual UNION ALL SELECT 'مجمّع (يستبعد البيني)', 'CONS' FROM dual");
table_region(name => 'kpi', title => 'المؤشرات', sql => src('p1_kpi.sql'), seq => 10, span => 4);
table_region(name => 'comp', title => 'الإيرادات والمصروفات شهرياً', sql => src('p1_monthly.sql'), seq => 20, span => 8, same_row => 1);
table_region(name => 'alerts', title => 'تنبيهات', sql => src('p1_alerts.sql'), seq => 30);
# التوالف التي تنتظر قرار التصفير ، والأصناف القاربت انتهاء صلاحيتها
table_region(name => 'damaged', title => 'التوالف غير المصفّاة (تنتظر قرار المدير)', sql => src('p1_damaged.sql'), seq => 40, span => 6);
table_region(name => 'expiry', title => 'أصناف قاربت انتهاء الصلاحية (خلال 3 أشهر)', sql => src('p1_expiry.sql'), seq => 50, span => 6, same_row => 1);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P1_YEAR IS NULL THEN :P1_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P1_MODE IS NULL THEN :P1_MODE := 'SEP'; END IF;"));
end_page();

1;
