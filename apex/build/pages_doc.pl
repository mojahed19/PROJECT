# =====================================================================
#  pages_doc.pl - صفحات المستندات والتقارير
# =====================================================================
use strict;
use warnings;
use utf8;

our %LOV = (
  companies  => "SELECT name_ar d, company_id r FROM companies c WHERE is_active = 'Y' AND (:G_USER_ROLE = 'GM' OR company_id = :G_COMPANY_ID OR EXISTS (SELECT 1 FROM user_companies u WHERE u.user_name = UPPER(:APP_USER) AND u.company_id = c.company_id)) ORDER BY is_parent DESC, company_code",
  all_companies => "SELECT name_ar d, company_id r FROM companies WHERE is_active = 'Y' ORDER BY is_parent DESC, company_code",
  subs       => "SELECT name_ar d, company_id r FROM companies WHERE is_parent = 'N' AND is_active = 'Y' ORDER BY company_code",
  currencies => "SELECT currency_code || ' - ' || name_ar d, currency_code r FROM currencies WHERE is_active = 'Y' ORDER BY is_base DESC, currency_code",
  jt_manual  => "SELECT name_ar d, jt_code r FROM journal_types WHERE manual_allowed = 'Y' AND is_active = 'Y' ORDER BY sort_order",
  periods    => "SELECT TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYY-MM') d, TO_CHAR(ADD_MONTHS(TRUNC(SYSDATE,'MM'), 1-LEVEL),'YYYYMM') r FROM dual CONNECT BY LEVEL <= 13",
  years      => "SELECT fy_year d, fy_year r FROM fiscal_years ORDER BY 1 DESC",
  warehouses => "SELECT c.name_ar || ' / ' || w.name_ar d, w.warehouse_id r FROM warehouses w JOIN companies c ON c.company_id = w.company_id WHERE w.is_active = 'Y' AND (:G_USER_ROLE = 'GM' OR w.company_id = :G_COMPANY_ID) ORDER BY c.company_code, w.name_ar",
  accounts4  => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_postable = 'Y' AND is_active = 'Y' ORDER BY account_code",
  accounts_all => "SELECT LPAD(' ', (acc_level - 1) * 3) || account_code || ' - ' || name_ar d, account_id r FROM accounts ORDER BY account_code",
  cash       => "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE cash_bank IN ('C','B') AND is_active = 'Y' ORDER BY account_code",
  yn         => "SELECT 'نعم' d, 'Y' r FROM dual UNION ALL SELECT 'لا', 'N' FROM dual",
);

my $SAVE_KEYS = "if (apex.item('%s').getValue() && apex.item('%s').getValue() !== '%s') { %s.forEach(function (n) { apex.item(n).disable(); }); }";

sub doc_status_html {
  my ($no_item, $status_item, $no_label) = @_;
  return "<div class=\"doc-meta\" style=\"margin:4px 0 10px\">$no_label: <b>&$no_item.</b> &nbsp;&nbsp; الحالة: "
       . "<span class=\"doc-status doc-status--&$status_item.\">&$status_item.</span></div>";
}

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
region(name => 'head', title => 'رأس القيد', type => 'static', html => doc_status_html('P30_JOURNAL_NO', 'P30_STATUS', 'رقم القيد'));
item(name => 'P30_JOURNAL_ID', region => 'head', type => 'hidden', seq => 1);
item(name => 'P30_JOURNAL_NO', region => 'head', type => 'hidden', seq => 2);
item(name => 'P30_STATUS',     region => 'head', type => 'hidden', seq => 3);
item(name => 'P30_SOURCE_TYPE',region => 'head', type => 'hidden', seq => 4);
item(name => 'P30_COMPANY_ID', region => 'head', type => 'select', label => 'الشركة', lov => $LOV{companies}, seq => 10, required => 1);
item(name => 'P30_JT_CODE',    region => 'head', type => 'select', label => 'نوع القيد', lov => $LOV{jt_manual}, extra => 1, seq => 20, same_line => 1, required => 1);
item(name => 'P30_JOURNAL_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 30, same_line => 1, required => 1);
item(name => 'P30_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 40, required => 1);
item(name => 'P30_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 50, same_line => 1);
item(name => 'P30_REF_NO',     region => 'head', label => 'المرجع', seq => 60, same_line => 1);
item(name => 'P30_DESCRIPTION', region => 'head', label => 'البيان', seq => 70, max => 500);
region(name => 'lines', title => 'سطور القيد', type => 'static', seq => 20,
       html => "<div id=\"jv_lines\"></div>\n<div style=\"margin-top:8px\">الفرق: <span id=\"jv_diff\" class=\"jv-diff ok\">0.00</span></div>");
my $draft = ":P30_STATUS IS NULL OR :P30_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "jv.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ وترحيل', js => "jv.save('POST');", hot => 1, seq => 20, cond => $draft);
button(name => 'DELETE_DOC', region => 'lines', label => 'حذف', js => 'jv.remove();', position => 'PREVIOUS', seq => 30,
       cond => ":P30_JOURNAL_ID IS NOT NULL AND :P30_STATUS = 'DRAFT'");
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30::', position => 'PREVIOUS', seq => 40);
button(name => 'REVERSE', region => 'lines', label => 'عكس القيد', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P30_JOURNAL_ID.',
       position => 'PREVIOUS', seq => 50, cond => ":P30_STATUS = 'POSTED'");
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, code => src('p30_load.sql'), cond => ':P30_JOURNAL_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, cond => ':P30_JOURNAL_ID IS NULL', code => join("\n",
  'IF :P30_COMPANY_ID IS NULL THEN :P30_COMPANY_ID := :G_COMPANY_ID; END IF;',
  "IF :P30_JT_CODE IS NULL THEN :P30_JT_CODE := 'JV'; END IF;", "IF :P30_STATUS IS NULL THEN :P30_STATUS := 'DRAFT'; END IF;",
  date_default('P30_JOURNAL_DATE'), base_cur_default('P30_CURRENCY_CODE', 'P30_EXCHANGE_RATE')));
ajax('INIT_DATA', src('p30_init.sql'));
ajax('SAVE_DOC',  src('p30_save.sql'));
ajax('DELETE_DOC', src('p30_delete.sql'));
branch_self();
end_page();

page(id => 31, name => 'قائمة القيود', alias => 'JOURNALS', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P31_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات', submit => 1);
item(name => 'P31_FROM', region => 'f', type => 'date', label => 'من', seq => 20, same_line => 1);
item(name => 'P31_TO',   region => 'f', type => 'date', label => 'إلى', seq => 30, same_line => 1);
button(name => 'GO', region => 'f', label => 'عرض', seq => 10, hot => 1);
region(name => 'ir', title => 'القيود', type => 'ir', sql => src('p31_ir.sql'), seq => 10,
       links => { 'رقم القيد' => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:#JOURNAL_ID#' });
branch_self();
end_page();

# =====================================================================
# 40 إذن توريد / إذن صرف + 41 القائمة
# =====================================================================
page(id => 40, name => 'إذن توريد / صرف', alias => 'VOUCHER', title => '&P40_TITLE.', auth => 'IS_ACCOUNTANT',
     js => src('p40.js'),
     onload => "vch.init();\n" . sprintf($SAVE_KEYS, 'P40_STATUS', 'P40_STATUS', 'DRAFT',
       "['P40_COMPANY_ID','P40_VOUCHER_DATE','P40_CASH_ACCOUNT_ID','P40_CURRENCY_CODE','P40_EXCHANGE_RATE','P40_PAY_METHOD','P40_CHEQUE_NO','P40_CHEQUE_DATE','P40_BANK_NAME','P40_PARTY_NAME','P40_DESCRIPTION']"));
region(name => 'head', title => '&P40_TITLE.', type => 'static', html => doc_status_html('P40_VOUCHER_NO', 'P40_STATUS', 'رقم الإذن'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P40_VOUCHER_ID',1],['P40_VOUCHER_TYPE',2],['P40_VOUCHER_NO',3],['P40_STATUS',4],['P40_JOURNAL_ID',5],['P40_TITLE',6]);
item(name => 'P40_COMPANY_ID', region => 'head', type => 'select', label => 'الشركة', lov => $LOV{companies}, seq => 10, required => 1);
item(name => 'P40_VOUCHER_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, same_line => 1, required => 1);
item(name => 'P40_CASH_ACCOUNT_ID', region => 'head', type => 'select', label => 'الصندوق / البنك', lov => $LOV{cash}, null => 1, seq => 30, same_line => 1, required => 1);
item(name => 'P40_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 40);
item(name => 'P40_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 50, same_line => 1);
item(name => 'P40_PAY_METHOD', region => 'head', type => 'select', label => 'طريقة الدفع', seq => 60, same_line => 1,
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'شيك', 'CHEQUE' FROM dual UNION ALL SELECT 'تحويل بنكي', 'TRANSFER' FROM dual");
item(name => 'P40_CHEQUE_NO', region => 'head', label => 'رقم الشيك', seq => 70);
item(name => 'P40_CHEQUE_DATE', region => 'head', type => 'date', label => 'تاريخ الشيك', seq => 80, same_line => 1);
item(name => 'P40_BANK_NAME', region => 'head', label => 'البنك', seq => 90, same_line => 1);
item(name => 'P40_PARTY_NAME', region => 'head', label => 'الاسم (استلمنا من / صرفنا إلى)', seq => 100);
item(name => 'P40_DESCRIPTION', region => 'head', label => 'البيان', seq => 110, same_line => 1, max => 500);
region(name => 'lines', title => 'الحسابات المقابلة', type => 'static', seq => 20,
       html => "<div id=\"v_lines\"></div>\n<div style=\"margin-top:8px\"><b>إجمالي الإذن:</b> <span id=\"v_words\"></span></div>");
$draft = ":P40_STATUS IS NULL OR :P40_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "vch.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ وترحيل', js => "vch.save('POST');", hot => 1, seq => 20, cond => $draft);
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:40:&SESSION.::&DEBUG.:40:P40_VOUCHER_TYPE:&P40_VOUCHER_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'SHOW_JV', region => 'lines', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P40_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P40_STATUS IN ('POSTED','REVERSED')");
button(name => 'REVERSE', region => 'lines', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P40_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P40_STATUS = 'POSTED'");
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, code => src('p40_load.sql'), cond => ':P40_VOUCHER_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P40_VOUCHER_TYPE IS NULL THEN :P40_VOUCHER_TYPE := 'R'; END IF;",
  "IF :P40_VOUCHER_ID IS NULL THEN",
  '  IF :P40_COMPANY_ID IS NULL THEN :P40_COMPANY_ID := :G_COMPANY_ID; END IF;',
  "  IF :P40_STATUS IS NULL THEN :P40_STATUS := 'DRAFT'; END IF;",
  "  IF :P40_PAY_METHOD IS NULL THEN :P40_PAY_METHOD := 'CASH'; END IF;",
  '  ' . date_default('P40_VOUCHER_DATE'), '  ' . base_cur_default('P40_CURRENCY_CODE', 'P40_EXCHANGE_RATE'),
  'END IF;',
  ":P40_TITLE := CASE :P40_VOUCHER_TYPE WHEN 'R' THEN 'إذن توريد' ELSE 'إذن صرف' END;"));
ajax('INIT_DATA', src('p40_init.sql'));
ajax('SAVE_DOC',  src('p40_save.sql'));
branch_self();
end_page();

page(id => 41, name => 'قائمة الأذونات', alias => 'VOUCHERS', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'بحث', type => 'static', html => '', seq => 5);
item(name => 'P41_TYPE', region => 'f', type => 'select', label => 'النوع', null => 'الكل', submit => 1,
     lov => "SELECT 'توريد' d, 'R' r FROM dual UNION ALL SELECT 'صرف', 'P' FROM dual");
region(name => 'ir', title => 'أذونات التوريد والصرف', type => 'ir', sql => src('p41_ir.sql'), seq => 10,
       links => { 'الرقم' => 'f?p=&APP_ID.:40:&SESSION.::&DEBUG.:40:P40_VOUCHER_ID:#VOUCHER_ID#' });
end_page();

# =====================================================================
# 50 فاتورة مبيعات / مرتجع مبيعات (الشركة الأم) لفرع أو عميل خارجي + 51 القائمة
# =====================================================================
my $acc_lov_cash = "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_active = 'Y' AND is_postable = 'Y' AND (company_id IS NULL OR company_id = :G_PARENT_ID) AND cash_bank = CASE :%s WHEN 'BANK' THEN 'B' ELSE 'C' END ORDER BY account_code";
my $acc_lov_credit = "SELECT account_code || ' - ' || name_ar d, account_id r FROM accounts WHERE is_active = 'Y' AND is_postable = 'Y' AND cash_bank = 'N' AND (company_id IS NULL OR company_id = :G_PARENT_ID) ORDER BY account_code";

page(id => 50, name => 'فاتورة مبيعات', alias => 'SALES', title => '&P50_TITLE.', auth => 'IS_STORE',
     js => src('p50.js'),
     onload => "inv.init();\n" . sprintf($SAVE_KEYS, 'P50_STATUS', 'P50_STATUS', 'DRAFT',
       "['P50_CUSTOMER_TYPE','P50_CUSTOMER_COMPANY_ID','P50_PAY_TYPE','P50_PAY_METHOD','P50_ACCOUNT_ID','P50_CUSTOMER_NAME','P50_INVOICE_DATE','P50_WAREHOUSE_ID','P50_PRICE_LIST_ID','P50_CURRENCY_CODE','P50_EXCHANGE_RATE','P50_DISCOUNT_AMOUNT','P50_DESCRIPTION']"));
region(name => 'head', title => '&P50_TITLE.', type => 'static', html => doc_status_html('P50_INVOICE_NO', 'P50_STATUS', 'رقم الفاتورة'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P50_INVOICE_ID',1],['P50_INVOICE_TYPE',2],['P50_INVOICE_NO',3],['P50_STATUS',4],['P50_JOURNAL_ID',5],['P50_TITLE',6]);
item(name => 'P50_CUSTOMER_TYPE', region => 'head', type => 'select', label => 'العميل', seq => 10, submit => 1, required => 1,
     lov => "SELECT 'عميل خارجي' d, 'EXTERNAL' r FROM dual UNION ALL SELECT 'فرع من فروع الشركة', 'BRANCH' FROM dual");
item(name => 'P50_INVOICE_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, same_line => 1, required => 1);
# فرع
item(name => 'P50_CUSTOMER_COMPANY_ID', region => 'head', type => 'select', label => 'الفرع (آجل على حسابه)', lov => $LOV{subs}, null => 1,
     seq => 30, required => 1, cond => ":P50_CUSTOMER_TYPE = 'BRANCH'");
# عميل خارجي
item(name => 'P50_PAY_TYPE', region => 'head', type => 'select', label => 'طريقة الدفع', seq => 40, submit => 1,
     cond => ":P50_CUSTOMER_TYPE = 'EXTERNAL'",
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'آجل' d, 'CREDIT' r FROM dual");
item(name => 'P50_PAY_METHOD', region => 'head', type => 'select', label => 'نقداً عن طريق', seq => 50, same_line => 1, submit => 1,
     cond => ":P50_CUSTOMER_TYPE = 'EXTERNAL' AND :P50_PAY_TYPE = 'CASH'",
     lov => "SELECT 'الصندوق' d, 'CASH' r FROM dual UNION ALL SELECT 'تحويل بنكي' d, 'BANK' r FROM dual");
item(name => 'P50_ACCOUNT_ID', region => 'head', type => 'popup', seq => 60, same_line => 1, required => 1,
     label => '&P50_ACC_LABEL.', cond => ":P50_CUSTOMER_TYPE = 'EXTERNAL'",
     lov => "SELECT d, r FROM (" . sprintf($acc_lov_cash, 'P50_PAY_METHOD') . ") WHERE :P50_PAY_TYPE = 'CASH' UNION ALL SELECT d, r FROM ($acc_lov_credit) WHERE :P50_PAY_TYPE = 'CREDIT'");
item(name => 'P50_ACC_LABEL', region => 'head', type => 'hidden', seq => 7);
item(name => 'P50_CUSTOMER_NAME', region => 'head', label => 'اسم العميل', seq => 70, max => 150, cond => ":P50_CUSTOMER_TYPE = 'EXTERNAL'");
item(name => 'P50_WAREHOUSE_ID', region => 'head', type => 'select', label => 'المخزن', seq => 80, required => 1,
     lov => "SELECT name_ar d, warehouse_id r FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y' ORDER BY name_ar");
item(name => 'P50_PRICE_LIST_ID', region => 'head', type => 'select', label => 'قائمة الأسعار (اختياري)', seq => 90, same_line => 1, null => 'بدون',
     lov => "SELECT name_ar || ' (' || currency_code || ')' d, price_list_id r FROM price_lists WHERE is_active = 'Y' ORDER BY name_ar");
item(name => 'P50_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 100);
item(name => 'P50_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 110, same_line => 1);
item(name => 'P50_DISCOUNT_AMOUNT', region => 'head', label => 'خصم إضافي', seq => 120, same_line => 1);
item(name => 'P50_DESCRIPTION', region => 'head', label => 'البيان', seq => 130, max => 500);
region(name => 'lines', title => 'الأصناف', type => 'static', seq => 20, html => <<'HTML');
<div class="jl-hint">ابحث بالكود أو بجزء من الاسم أو بالباركود. الأسهم للتنقل في النتائج و Enter للاختيار.</div>
<div id="inv_lines"></div>
<div style="margin-top:10px;font-weight:600">
  الإجمالي: <span id="inv_gross">0.00</span> &nbsp;&nbsp;
  الصافي بعد الخصم الإضافي: <span id="inv_net">0.00</span>
</div>
HTML
$draft = ":P50_STATUS IS NULL OR :P50_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "inv.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ وترحيل', js => "inv.save('POST');", hot => 1, seq => 20, cond => $draft);
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
  :P50_INVOICE_TYPE := i.invoice_type; :P50_INVOICE_NO := i.invoice_no; :P50_CUSTOMER_TYPE := i.customer_type;
  :P50_CUSTOMER_COMPANY_ID := i.customer_company_id; :P50_INVOICE_DATE := TO_CHAR(i.invoice_date, 'DD/MM/YYYY');
  :P50_PAY_TYPE := i.pay_type; :P50_PAY_METHOD := i.pay_method; :P50_ACCOUNT_ID := i.account_id;
  :P50_CUSTOMER_NAME := i.customer_name; :P50_WAREHOUSE_ID := i.warehouse_id; :P50_PRICE_LIST_ID := i.price_list_id;
  :P50_CURRENCY_CODE := i.currency_code; :P50_EXCHANGE_RATE := i.exchange_rate;
  :P50_DISCOUNT_AMOUNT := i.discount_amount; :P50_DESCRIPTION := i.description;
  :P50_STATUS := i.status; :P50_JOURNAL_ID := i.journal_id;
END;
SQL
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', seq => 20, code => join("\n",
  "IF :P50_INVOICE_TYPE IS NULL THEN :P50_INVOICE_TYPE := 'SALE'; END IF;",
  "IF :P50_CUSTOMER_TYPE IS NULL THEN :P50_CUSTOMER_TYPE := 'EXTERNAL'; END IF;",
  "IF :P50_PAY_TYPE IS NULL THEN :P50_PAY_TYPE := 'CASH'; END IF;",
  "IF :P50_PAY_TYPE = 'CASH' AND :P50_PAY_METHOD IS NULL THEN :P50_PAY_METHOD := 'CASH'; END IF;",
  "IF :P50_INVOICE_ID IS NULL THEN",
  "  IF :P50_STATUS IS NULL THEN :P50_STATUS := 'DRAFT'; END IF;",
  "  IF :P50_WAREHOUSE_ID IS NULL THEN SELECT MIN(warehouse_id) INTO :P50_WAREHOUSE_ID FROM warehouses WHERE company_id = :G_PARENT_ID AND is_active = 'Y'; END IF;",
  '  ' . date_default('P50_INVOICE_DATE'), '  ' . base_cur_default('P50_CURRENCY_CODE', 'P50_EXCHANGE_RATE'),
  'END IF;',
  ":P50_TITLE := CASE :P50_INVOICE_TYPE WHEN 'SALE' THEN 'فاتورة مبيعات' ELSE 'مرتجع مبيعات' END;",
  ":P50_ACC_LABEL := CASE WHEN :P50_PAY_TYPE = 'CREDIT' THEN 'حساب العميل' WHEN :P50_PAY_METHOD = 'BANK' THEN 'الحساب البنكي' ELSE 'الصندوق' END;"));
ajax('INIT_DATA', src('p50_init.sql'));
ajax('SAVE_DOC',  src('p50_save.sql'));
branch_self();
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
       "['P55_INVOICE_DATE','P55_SUPPLIER_INV_NO','P55_PAY_TYPE','P55_PAY_METHOD','P55_SUPPLIER_ACCOUNT_ID','P55_SUPPLIER_NAME','P55_WAREHOUSE_ID','P55_CURRENCY_CODE','P55_EXCHANGE_RATE','P55_DISCOUNT_AMOUNT','P55_DESCRIPTION']"));
region(name => 'head', title => '&P55_TITLE.', type => 'static', html => doc_status_html('P55_INVOICE_NO', 'P55_STATUS', 'رقم الفاتورة'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P55_PINV_ID',1],['P55_INVOICE_TYPE',2],['P55_INVOICE_NO',3],['P55_STATUS',4],['P55_JOURNAL_ID',5],['P55_TITLE',6]);
item(name => 'P55_COMPANY_ID', region => 'head', type => 'hidden', seq => 7);
item(name => 'P55_LOADED_ID', region => 'head', type => 'hidden', seq => 8);
item(name => 'P55_ACC_LABEL', region => 'head', type => 'hidden', seq => 9);
item(name => 'P55_INVOICE_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 20, required => 1);
item(name => 'P55_SUPPLIER_INV_NO', region => 'head', label => 'رقم فاتورة المورد', seq => 30, same_line => 1, max => 50);
item(name => 'P55_PAY_TYPE', region => 'head', type => 'select', label => 'طريقة الدفع', seq => 40, submit => 1,
     lov => "SELECT 'نقدي' d, 'CASH' r FROM dual UNION ALL SELECT 'آجل' d, 'CREDIT' r FROM dual");
item(name => 'P55_PAY_METHOD', region => 'head', type => 'select', label => 'نقداً عن طريق', seq => 45, same_line => 1, submit => 1,
     cond => ":P55_PAY_TYPE = 'CASH'",
     lov => "SELECT 'الصندوق' d, 'CASH' r FROM dual UNION ALL SELECT 'تحويل بنكي' d, 'BANK' r FROM dual");
item(name => 'P55_SUPPLIER_ACCOUNT_ID', region => 'head', type => 'popup', label => '&P55_ACC_LABEL.', seq => 50, same_line => 1, required => 1,
     lov => "SELECT d, r FROM (" . sprintf($acc_lov_cash, 'P55_PAY_METHOD') . ") WHERE :P55_PAY_TYPE = 'CASH' UNION ALL SELECT d, r FROM ($acc_lov_credit) WHERE :P55_PAY_TYPE = 'CREDIT'");
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
$draft = ":P55_STATUS IS NULL OR :P55_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "pur.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ وترحيل', js => "pur.save('POST');", hot => 1, seq => 20, cond => $draft);
button(name => 'PRINT_A4', region => 'lines', label => 'طباعة A4', js => 'pur.print();', seq => 25, cond => ':P55_PINV_ID IS NOT NULL');
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:55:&SESSION.::&DEBUG.:55:P55_INVOICE_TYPE:&P55_INVOICE_TYPE.', position => 'PREVIOUS', seq => 30);
button(name => 'SHOW_JV', region => 'lines', label => 'عرض القيد', url => 'f?p=&APP_ID.:30:&SESSION.::&DEBUG.:30:P30_JOURNAL_ID:&P55_JOURNAL_ID.', position => 'PREVIOUS', seq => 40, cond => ":P55_STATUS IN ('POSTED','REVERSED')");
button(name => 'REVERSE', region => 'lines', label => 'عكس', url => 'f?p=&APP_ID.:60:&SESSION.::&DEBUG.::P60_JOURNAL_ID:&P55_JOURNAL_ID.', position => 'PREVIOUS', seq => 50, cond => ":P55_STATUS = 'POSTED'");
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10,
        cond => ":P55_PINV_ID IS NOT NULL AND :P55_PINV_ID <> NVL(:P55_LOADED_ID, 'x')", code => <<'SQL');
DECLARE p purchase_invoices%ROWTYPE;
BEGIN
  :P55_LOADED_ID := :P55_PINV_ID;
  SELECT * INTO p FROM purchase_invoices WHERE pinv_id = :P55_PINV_ID;
  IF NOT (:G_USER_ROLE = 'GM' OR p.company_id = :G_COMPANY_ID) THEN
    raise_application_error(-20001, 'ليس لديك صلاحية على هذه الفاتورة');
  END IF;
  :P55_INVOICE_TYPE := p.invoice_type; :P55_INVOICE_NO := p.invoice_no; :P55_COMPANY_ID := p.company_id;
  :P55_INVOICE_DATE := TO_CHAR(p.invoice_date, 'DD/MM/YYYY'); :P55_SUPPLIER_INV_NO := p.supplier_inv_no;
  :P55_PAY_TYPE := p.pay_type; :P55_PAY_METHOD := p.pay_method; :P55_SUPPLIER_ACCOUNT_ID := p.supplier_account_id; :P55_SUPPLIER_NAME := p.supplier_name;
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
  "IF :P55_PAY_TYPE = 'CASH' AND :P55_PAY_METHOD IS NULL THEN :P55_PAY_METHOD := 'CASH'; END IF;",
  ":P55_ACC_LABEL := CASE WHEN :P55_PAY_TYPE = 'CREDIT' THEN 'حساب المورد' WHEN :P55_PAY_METHOD = 'BANK' THEN 'الحساب البنكي' ELSE 'الصندوق' END;",
  ":P55_TITLE := CASE :P55_INVOICE_TYPE WHEN 'PURCHASE' THEN 'فاتورة مشتريات' ELSE 'مرتجع مشتريات' END;"));
ajax('INIT_DATA', src('p55_init.sql'));
ajax('SAVE_DOC',  src('p55_save.sql'));
branch_self();
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
            ['57', 'PURCHASE', 'A4', 'P57_PINV_ID', 'طباعة فاتورة مشتريات A4']) {
  my ($pid, $kind, $size, $itm, $name) = @$pp;
  my $page_css = $print_css . ($size eq '80'
      ? "\@page { size: 80mm auto; margin: 2mm; }\n.inv-brand img { width: 60px; height: 60px; }\n.inv-brand .nm { font-size: 14px; }\n.inv-brand { width: 72mm; margin: 0 auto; }\n"
      : "\@page { size: A4; margin: 12mm; }\n");
  page(id => $pid, name => $name, alias => "PRINT-$pid", template => 'page_minimal', css => $page_css,
       onload => 'setTimeout(function () { window.print(); }, 600);');
  region(name => 'brand', title => 'brand', type => 'static', no_header => 1, seq => 5, html => <<'HTML');
<div class="no-print"><button type="button" class="t-Button t-Button--hot" onclick="window.print()">طباعة</button></div>
<div class="inv-brand"><img src="#APP_FILES#logo.jpg" alt=""><div class="nm">&APP_NAME.</div><div class="ln"></div></div>
HTML
  item(name => $itm, region => 'brand', type => 'hidden');
  my $code = src('print_invoice.sql');
  $code =~ s/__KIND__/$kind/; $code =~ s/__SIZE__/$size/; $code =~ s/__ITEM__/$itm/;
  region(name => 'body', title => 'body', type => 'plsql', no_header => 1, seq => 10, plsql => $code);
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
button(name => 'REVERSE', region => 'rev', label => 'عكس القيد', hot => 1, confirm => 'هل تريد عكس هذا القيد؟ لا يمكن التراجع');
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
region(name => 'head', title => '&P70_TITLE.', type => 'static', html => doc_status_html('P70_ADJ_NO', 'P70_STATUS', 'الرقم'));
item(name => $_->[0], region => 'head', type => 'hidden', seq => $_->[1]) for (['P70_ADJ_ID',1],['P70_ADJ_TYPE',2],['P70_ADJ_NO',3],['P70_STATUS',4],['P70_TITLE',5]);
item(name => 'P70_ADJ_DATE', region => 'head', type => 'date', label => 'التاريخ', seq => 10, required => 1);
item(name => 'P70_PAY_PERIOD', region => 'head', type => 'select', label => 'شهر الراتب', lov => $LOV{periods}, seq => 20, same_line => 1, required => 1);
item(name => 'P70_ALLOWANCE_ID', region => 'head', type => 'select', label => 'البند', lov => src('p70_allow_lov.sql'), null => 1, seq => 30, same_line => 1);
item(name => 'P70_CURRENCY_CODE', region => 'head', type => 'select', label => 'العملة', lov => $LOV{currencies}, seq => 40);
item(name => 'P70_EXCHANGE_RATE', region => 'head', label => 'سعر الصرف', seq => 50, same_line => 1);
item(name => 'P70_REASON', region => 'head', label => 'السبب', seq => 60, same_line => 1, max => 500, required => 1);
region(name => 'lines', title => 'الموظفون', type => 'static', seq => 20, html => '<div id="adj_lines"></div>');
$draft = ":P70_STATUS IS NULL OR :P70_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "adj.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'APPROVE', region => 'lines', label => 'اعتماد', js => "adj.save('APPROVE');", hot => 1, seq => 20, cond => $draft);
button(name => 'CANCEL_DOC', region => 'lines', label => 'إلغاء المستند', js => "adj.save('CANCEL');", position => 'PREVIOUS', seq => 30,
       cond => ":P70_ADJ_ID IS NOT NULL AND :P70_STATUS = 'DRAFT'");
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:70:&SESSION.::&DEBUG.:70:P70_ADJ_TYPE:&P70_ADJ_TYPE.', position => 'PREVIOUS', seq => 40);
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, cond => ':P70_ADJ_ID IS NOT NULL', code => <<'SQL');
DECLARE a payroll_adj%ROWTYPE;
BEGIN
  SELECT * INTO a FROM payroll_adj WHERE adj_id = :P70_ADJ_ID;
  :P70_ADJ_TYPE      := a.adj_type;
  :P70_ADJ_NO        := a.adj_no;
  :P70_ADJ_DATE      := TO_CHAR(a.adj_date, 'DD/MM/YYYY');
  :P70_PAY_PERIOD    := a.pay_period;
  :P70_ALLOWANCE_ID  := a.allowance_id;
  :P70_CURRENCY_CODE := a.currency_code;
  :P70_EXCHANGE_RATE := a.exchange_rate;
  :P70_REASON        := a.reason;
  :P70_STATUS        := a.status;
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
branch_self();
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
region(name => 'ir', title => 'ميزان المراجعة', type => 'ir', sql => src('p80_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P80_FROM IS NULL THEN :P80_FROM := TO_CHAR(TRUNC(SYSDATE,'YYYY'), 'DD/MM/YYYY'); END IF;",
  "IF :P80_TO IS NULL THEN :P80_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;",
  "IF :P80_LEVEL IS NULL THEN :P80_LEVEL := 4; END IF;",
  "IF :P80_EXCLUDE_INTERCO IS NULL THEN :P80_EXCLUDE_INTERCO := 'N'; END IF;",
  "IF :P80_SEPARATE IS NULL THEN :P80_SEPARATE := 'N'; END IF;"));
branch_self();
end_page();

page(id => 81, name => 'كشف حساب', alias => 'STATEMENT', auth => 'IS_ACCOUNTANT');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P81_ACCOUNT_ID', region => 'f', type => 'popup', label => 'الحساب', lov => $LOV{accounts_all}, required => 1);
item(name => 'P81_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'الكل', seq => 20, same_line => 1);
item(name => 'P81_FROM', region => 'f', type => 'date', label => 'من', seq => 30);
item(name => 'P81_TO', region => 'f', type => 'date', label => 'إلى', seq => 40, same_line => 1);
item(name => 'P81_CURRENCY', region => 'f', type => 'select', label => 'العملة', lov => $LOV{currencies}, null => 'بالعملة الأساسية', seq => 50, same_line => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1);
region(name => 'ir', title => 'كشف الحساب', type => 'ir', sql => src('p81_ir.sql'), seq => 10, cond => ':P81_ACCOUNT_ID IS NOT NULL');
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P81_FROM IS NULL THEN :P81_FROM := TO_CHAR(TRUNC(SYSDATE,'YYYY'), 'DD/MM/YYYY'); END IF;",
  "IF :P81_TO IS NULL THEN :P81_TO := TO_CHAR(SYSDATE, 'DD/MM/YYYY'); END IF;"));
branch_self();
end_page();

# =====================================================================
# 90 حركات المخزون + 91 + 92 + 93
# =====================================================================
page(id => 90, name => 'حركة مخزون', alias => 'STOCK', title => '&P90_TITLE.', auth => 'IS_STORE',
     js => src('p90.js'),
     onload => "stk.init();\n" . sprintf($SAVE_KEYS, 'P90_STATUS', 'P90_STATUS', 'DRAFT',
       "['P90_COMPANY_ID','P90_TRANS_DATE','P90_WAREHOUSE_ID','P90_TO_WAREHOUSE_ID','P90_COUNTER_ACCOUNT_ID','P90_CURRENCY_CODE','P90_EXCHANGE_RATE','P90_DESCRIPTION']"));
region(name => 'head', title => '&P90_TITLE.', type => 'static', html => doc_status_html('P90_TRANS_NO', 'P90_STATUS', 'الرقم'));
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
$draft = ":P90_STATUS IS NULL OR :P90_STATUS = 'DRAFT'";
button(name => 'SAVE_DRAFT', region => 'lines', label => 'حفظ مسودة (Ctrl+S)', js => "stk.save('DRAFT');", seq => 10, cond => $draft);
button(name => 'POST', region => 'lines', label => 'حفظ وترحيل', js => "stk.save('POST');", hot => 1, seq => 20, cond => $draft);
button(name => 'NEW', region => 'lines', label => 'جديد', url => 'f?p=&APP_ID.:90:&SESSION.::&DEBUG.:90:P90_TRANS_TYPE:&P90_TRANS_TYPE.', position => 'PREVIOUS', seq => 30);
process(name => 'LOAD_HEADER', point => 'BEFORE_HEADER', seq => 10, cond => ':P90_TRANS_ID IS NOT NULL', code => <<'SQL');
DECLARE t stock_trans%ROWTYPE;
BEGIN
  SELECT * INTO t FROM stock_trans WHERE trans_id = :P90_TRANS_ID;
  IF NOT (:G_USER_ROLE = 'GM' OR t.company_id = :G_COMPANY_ID) THEN
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
  ":P90_TITLE := CASE :P90_TRANS_TYPE WHEN 'RECEIPT' THEN 'استلام بضاعة' WHEN 'ISSUE' THEN 'صرف داخلي' WHEN 'TRANSFER' THEN 'تحويل بين المخازن' WHEN 'COUNT' THEN 'تسوية جرد' WHEN 'OPENING' THEN 'إشعار إضافة - بضاعة أول المدة' ELSE 'حركة مخزون' END;"));
ajax('INIT_DATA', src('p90_init.sql'));
ajax('SAVE_DOC',  src('p90_save.sql'));
branch_self();
end_page();

page(id => 91, name => 'قائمة حركات المخزون', alias => 'STOCKS', auth => 'IS_STORE');
my $p91 = src('p91_ir.sql');
$p91 =~ s/^SELECT t\.trans_id,/SELECT t.trans_id, t.trans_type AS trans_type_code,/;
region(name => 'ir', title => 'حركات المخزون', type => 'ir', sql => $p91, hide => ['TRANS_TYPE_CODE'],
       links => { 'الرقم' => 'f?p=&APP_ID.:90:&SESSION.::&DEBUG.:90:P90_TRANS_ID,P90_TRANS_TYPE:#TRANS_ID#,#TRANS_TYPE_CODE#' });
end_page();

page(id => 92, name => 'أرصدة المخزون', alias => 'STOCK-BAL', auth => 'IS_STORE');
region(name => 'ir', title => 'أرصدة المخزون', type => 'ir', sql => src('p92_ir.sql'));
end_page();

page(id => 93, name => 'كارت صنف', alias => 'ITEM-CARD', auth => 'IS_STORE');
region(name => 'f', title => 'الخيارات', type => 'static', html => '', seq => 5);
item(name => 'P93_ITEM_ID', region => 'f', type => 'popup', label => 'الصنف', lov => "SELECT item_code || ' - ' || name_ar d, item_id r FROM items ORDER BY item_code", required => 1);
item(name => 'P93_WAREHOUSE_ID', region => 'f', type => 'select', label => 'المخزن', lov => $LOV{warehouses}, null => 1, seq => 20, same_line => 1, required => 1);
button(name => 'GO', region => 'f', label => 'عرض', hot => 1);
region(name => 'ir', title => 'حركة الصنف', type => 'ir', sql => src('p93_ir.sql'), seq => 10, cond => ':P93_ITEM_ID IS NOT NULL AND :P93_WAREHOUSE_ID IS NOT NULL');
branch_self();
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
item(name => 'P121_TO_MONTH', region => 'f', type => 'select', label => 'حتى شهر', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT LEVEL d, LEVEL r FROM dual CONNECT BY LEVEL <= 12");
item(name => 'P121_LEVEL', region => 'f', type => 'select', label => 'المستوى', submit => 1, seq => 40, same_line => 1,
     lov => "SELECT 'المستوى ' || (LEVEL + 1) d, LEVEL + 1 r FROM dual CONNECT BY LEVEL <= 3");
region(name => 'ir', title => 'الموازنة مقابل الفعلي', type => 'ir', sql => src('p121_ir.sql'), seq => 10);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P121_FY_YEAR IS NULL THEN :P121_FY_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P121_TO_MONTH IS NULL THEN :P121_TO_MONTH := TO_NUMBER(TO_CHAR(SYSDATE, 'MM')); END IF;",
  "IF :P121_LEVEL IS NULL THEN :P121_LEVEL := 4; END IF;"));
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
branch_self();
end_page();

# =====================================================================
# 1 لوحة المدير العام
# =====================================================================
page(id => 1, name => 'الرئيسية', alias => 'HOME');
region(name => 'f', title => 'لوحة المدير العام', type => 'static', html => '', seq => 5);
item(name => 'P1_COMPANY_ID', region => 'f', type => 'select', label => 'الشركة', lov => $LOV{companies}, null => 'كل الشركات', submit => 1);
item(name => 'P1_YEAR', region => 'f', type => 'select', label => 'السنة', lov => $LOV{years}, submit => 1, seq => 20, same_line => 1);
item(name => 'P1_MODE', region => 'f', type => 'select', label => 'العرض', submit => 1, seq => 30, same_line => 1,
     lov => "SELECT 'كل شركة منفصلة' d, 'SEP' r FROM dual UNION ALL SELECT 'مجمّع (يستبعد البيني)', 'CONS' FROM dual");
table_region(name => 'kpi', title => 'المؤشرات', sql => src('p1_kpi.sql'), seq => 10, span => 4);
table_region(name => 'comp', title => 'مقارنة الشركات', sql => src('p1_companies.sql'), seq => 20, span => 8, same_row => 1);
table_region(name => 'alerts', title => 'تنبيهات', sql => src('p1_alerts.sql'), seq => 30);
process(name => 'DEFAULTS', point => 'BEFORE_HEADER', code => join("\n",
  "IF :P1_YEAR IS NULL THEN :P1_YEAR := TO_CHAR(SYSDATE, 'YYYY'); END IF;",
  "IF :P1_MODE IS NULL THEN :P1_MODE := 'SEP'; END IF;"));
end_page();

1;
