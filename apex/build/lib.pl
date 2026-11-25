# =====================================================================
#  lib.pl - مكتبة توليد ملف تصدير APEX 24.1 (wwv_flow_imp API)
#  تُستخدم من gen_app.pl
# =====================================================================
use strict;
use warnings;
use utf8;

our $OUT  = '';
our $NEXT = 91_000_000_000_000;
our %REG;       # name -> id  (regions)
our %BTN;       # "page:name" -> id
our %SEC;       # authorization schemes name -> id
our $CUR_PAGE;

# ---- القوالب (من الثيم 42 في ملف التصدير القديم)
our %T = (
  page_modal   => 6601643187757357,
  page_login   => 6603126323757359,
  page_minimal => 6618695660757373,
  reg_std      => 6697232433757451,
  reg_ir       => 6687458349757443,
  reg_blank    => 6630666134757390,
  reg_buttons  => 6633496817757392,
  reg_login    => 6692006857757446,
  fld_opt      => 6768309489757532,   # Optional - Floating
  fld_req      => 6769647329757532,   # Required - Floating
  fld_hidden   => 6768064019757529,
  btn_text     => 6770806568757537,
  btn_icon     => 6770932302757537,
  list_nav     => 6755627325757515,
  list_navbar  => 6758484501757520,
);

sub nid  { return ++$NEXT }
sub wid  { my $n = shift; return "wwv_flow_imp.id($n)" }
sub out  { $OUT .= join('', @_) }

# نص SQL حرفي: ASCII عادي، أو unistr() لأي حرف عربي أو \
sub lit {
  my $s = shift;
  return 'null' unless defined $s;
  (my $e = $s) =~ s/'/''/g;
  if ($e =~ /[^\x00-\x7F]|\\/) {
    $e =~ s/\\/\\005C/g;
    $e =~ s/([^\x00-\x7F])/ord($1) > 0xFFFF ? '?' : sprintf('\\%04X', ord $1)/ge;
    return "unistr('$e')";
  }
  return "'$e'";
}

# نص متعدد الأسطر
sub txt {
  my $s = shift;
  return 'null' unless defined $s;
  $s =~ s/\r//g;
  $s =~ s/\n+\z//;
  my @l = split /\n/, $s, -1;
  return lit($s) if @l == 1 && length($s) < 200;
  return "wwv_flow_string.join(wwv_flow_t_varchar2(\n" . join(",\n", map { lit($_) } @l) . "))";
}

sub src {
  my $f = shift;
  my $p = "$main::SRC/$f";
  open my $fh, '<:encoding(UTF-8)', $p or die "missing $p: $!";
  local $/; my $c = <$fh>; close $fh;
  return $c;
}

sub section { my ($name, $body) = @_; out("prompt --application/$name\nbegin\n$body\nend;\n/\n"); }

sub args {
  my @a = @_; my @r;
  while (@a) { my ($k, $v) = splice(@a, 0, 2); next unless defined $v; push @r, "p_$k=>$v"; }
  return " " . join("\n,", @r);
}

# =====================================================================
# الصفحات
# =====================================================================
sub page {
  my %p = @_;
  $CUR_PAGE = $p{id};
  my $alias = $p{alias} // "P$p{id}";
  out("prompt --application/pages/page_" . sprintf('%05d', $p{id}) . "\nbegin\n");
  out("wwv_flow_imp_page.create_page(\n" . args(
    id                      => $p{id},
    name                    => lit($p{name}),
    alias                   => lit($alias),
    page_mode               => $p{modal} ? "'MODAL'" : undef,
    step_title              => lit($p{title} // $p{name}),
    warn_on_unsaved_changes => "'N'",
    autocomplete_on_off     => "'OFF'",
    javascript_code         => $p{js}     ? txt($p{js})     : undef,
    javascript_code_onload  => $p{onload} ? txt("window.APP_ROLE = '&G_USER_ROLE.';
" . $p{onload}) : undef,
    inline_css              => $p{css}    ? txt($p{css})    : undef,
    step_template           => $p{template} ? wid($T{$p{template}}) : undef,
    page_template_options   => "'#DEFAULT#'",
    dialog_width            => $p{width} ? lit($p{width}) : undef,
    dialog_chained          => $p{modal} ? "'N'" : undef,
    page_is_public_y_n      => $p{public} ? "'Y'" : undef,
    required_role           => $p{auth} ? wid($SEC{$p{auth}}) : undef,
    protection_level        => "'N'",   # N = Unrestricted (C=checksum, U=no args, D=no URL): يقبل الروابط المبنية في المتصفح (أزرار الطباعة). الصلاحيات تُفحص في الخادم
  ) . "\n);\n");
}
sub end_page { out("end;\n/\n"); }

sub region {
  my %r = @_;
  push @main::PLSQL, ["P$CUR_PAGE region $r{name} cond", "BEGIN IF $r{cond} THEN NULL; END IF; END;"] if $r{cond};
  my $id = nid();
  $REG{"$CUR_PAGE:$r{name}"} = $id;
  my $tmpl = $T{ $r{template} // ($r{type} eq 'ir' ? 'reg_ir' : 'reg_std') };
  my %src;
  if ($r{type} eq 'static') {
    %src = (plug_source => txt($r{html} // ''),
            attributes  => "wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(\n  'expand_shortcuts', 'N',\n  'output_as', 'HTML')).to_clob");
  } elsif ($r{type} eq 'plsql') {
    push @main::PLSQL, ["P$CUR_PAGE region $r{name}", $r{plsql}];
    %src = (plug_source => txt($r{plsql}), plug_source_type => "'NATIVE_PLSQL'");
  } elsif ($r{type} eq 'ir') {
    push @main::SQLQ, ["P$CUR_PAGE ir $r{name}", $r{sql}];
    %src = (query_type => "'SQL'", plug_source => txt($r{sql}), plug_source_type => "'NATIVE_IR'",
            prn_page_header => lit($r{title} // $r{name}));
  } elsif ($r{type} eq 'form') {
    %src = (query_type => "'SQL'", plug_source => txt($r{sql}), is_editable => 'true',
            edit_operations => "'i:u:d'", lost_update_check_type => "'VALUES'",
            plug_source_type => "'NATIVE_FORM'");
  }
  my $opts = '#DEFAULT#';
  $opts .= ':t-Region--removeHeader js-removeLandmark' if $r{no_header};
  $opts .= ':t-Region--scrollBody' unless $r{type} eq 'ir';
  out("wwv_flow_imp_page.create_page_plug(\n" . args(
    id                         => wid($id),
    plug_name                  => lit($r{title} // $r{name}),
    region_template_options    => lit($opts),
    plug_template              => wid($tmpl),
    plug_display_sequence      => $r{seq} // 10,
    plug_display_point         => $r{position} ? lit($r{position}) : undef,
    region_image               => $r{image} ? lit($r{image}) : undef,
    plug_grid_column_span      => $r{span},
    plug_new_grid_row          => $r{same_row} ? 'false' : undef,
    location                   => $r{type} eq 'ir' || $r{type} eq 'form' ? undef : 'null',
    plug_display_condition_type=> $r{cond} ? "'EXPRESSION'" : undef,
    plug_display_when_condition=> $r{cond} ? lit($r{cond}) : undef,
    plug_display_when_cond2    => $r{cond} ? "'PLSQL'" : undef,
    %src,
  ) . "\n);\n");
  ir_columns($id, %r) if $r{type} eq 'ir';
  return $id;
}

# أسماء أعمدة الاستعلام (الـ SELECT الأخير على المستوى الأعلى، أو الأول عند UNION)
sub sql_columns {
  my $sql = shift;
  my $s = $sql;
  $s =~ s/--[^\n]*//g;
  $s =~ s/'(?:[^']|'')*'/'_'/g;                    # إخفاء النصوص
  # موضع SELECT الرئيسي: أول SELECT على مستوى القوسين 0 بعد الـ WITH
  my ($depth, $i, $start) = (0, 0, -1);
  my $len = length $s;
  my @tok;
  while ($i < $len) {
    my $c = substr($s, $i, 1);
    if    ($c eq '(') { $depth++ }
    elsif ($c eq ')') { $depth-- }
    elsif ($depth == 0 && substr($s, $i) =~ /^select\b/i && ($i == 0 || substr($s, $i-1, 1) =~ /\s/)) { $start = $i + 6; last }
    $i++;
  }
  die "no select" if $start < 0;
  # حتى FROM على المستوى 0
  ($depth, $i) = (0, $start);
  my $cur = ''; my @items;
  while ($i < $len) {
    my $c = substr($s, $i, 1);
    if ($c eq '"') { my $j = index($s, '"', $i + 1); $cur .= substr($s, $i, $j - $i + 1); $i = $j + 1; next }
    if    ($c eq '(') { $depth++ }
    elsif ($c eq ')') { $depth-- }
    if ($depth == 0 && substr($s, $i) =~ /^from\b/i && substr($s, $i-1, 1) =~ /\s/) { last }
    if ($depth == 0 && $c eq ',') { push @items, $cur; $cur = ''; $i++; next }
    $cur .= $c; $i++;
  }
  push @items, $cur;
  my @cols;
  for my $it (@items) {
    $it =~ s/^\s+|\s+$//g;
    if    ($it =~ /"([^"]+)"\s*$/)                { push @cols, $1 }
    elsif ($it =~ /(?:\bas\s+)?([A-Za-z_][\w\$#]*)\s*$/i) { push @cols, uc $1 }
    else { die "cannot name column: $it" }
  }
  return @cols;
}

sub col_ident { my $n = shift; my $s = ''; $n++; while ($n > 0) { my $r = ($n - 1) % 26; $s = chr(65 + $r) . $s; $n = int(($n - 1) / 26); } return $s }

sub ir_columns {
  my ($rid, %r) = @_;
  my @cols = sql_columns($r{sql});
  my $ws = nid();
  out("wwv_flow_imp_page.create_worksheet(\n" . args(
    id                     => wid($ws),
    max_row_count_message  => "'The maximum row count for this report is #MAX_ROW_COUNT# rows.  Please apply a filter to reduce the number of records in your query.'",
    no_data_found_message  => lit('لا توجد بيانات'),
    pagination_type        => "'ROWS_X_TO_Y'",
    pagination_display_pos => "'BOTTOM_RIGHT'",
    report_list_mode       => "'TABS'",
    lazy_loading           => 'false',
    show_detail_link       => $r{detail_link} ? "'C'" : "'N'",
    show_notify            => "'Y'",
    download_formats       => "'CSV:HTML:XLSX:PDF'",
    enable_mail_download   => "'Y'",
    detail_link            => $r{detail_link} ? lit($r{detail_link}) : undef,
    detail_link_text       => $r{detail_link} ? lit('<span role="img" aria-label="Edit" class="fa fa-edit" title="Edit"></span>') : undef,
    base_pk1               => $r{pk} ? lit($r{pk}) : undef,
    owner                  => "'ADMIN'",
    internal_uid           => $ws,
  ) . "\n);\n");
  my %hidden = map { $_ => 1 } @{ $r{hide} // [] };
  my %links  = %{ $r{links} // {} };
  my $n = 0;
  for my $c (@cols) {
    my $num = ($c =~ /(مبلغ|المبلغ|الإجمالي|الصافي|مدين|دائن|الرصيد|القيمة|التكلفة|الخصم|المبيعات|المرتجعات|الأساسي|العلاوات|الحوافز|الفروقات|الخصومات|الموازنة|الفعلي|الانحراف|الربح|السعر|الكمية|وارد|صادر|بالعملة|نقداً|بطاقة|العدد|رصيد|حركة|عدد|السنوية|متوسط|النسبة|نسبة|الأصول|الخصوم|حقوق|أرباح|الإيرادات|المصروفات)/);
    my $is_hidden = $hidden{$c} || $c =~ /^[A-Z_]+_ID$/ || $c eq 'ROWID' || $c eq 'SORT_KEY';
    out("wwv_flow_imp_page.create_worksheet_column(\n" . args(
      id                 => wid(nid()),
      db_column_name     => lit($c),
      display_order      => ($n + 1) * 10,
      is_primary_key     => ($r{pk} && $c eq $r{pk}) ? "'Y'" : undef,
      column_identifier  => lit(col_ident($n)),
      column_label       => lit($c),
      column_link        => $links{$c} ? lit($links{$c}) : undef,
      column_linktext    => $links{$c} ? lit("#$c#") : undef,
      column_type        => $num ? "'NUMBER'" : "'STRING'",
      display_text_as    => $is_hidden ? "'HIDDEN_ESCAPE_SC'" : undef,
      column_alignment   => $num ? "'RIGHT'" : undef,
      format_mask        => $num && $c !~ /(العدد|عدد|النسبة|نسبة|المستوى)/ ? "'999G999G999G999G990D00'" : undef,
      heading_alignment  => "'LEFT'",
      tz_dependent       => "'N'",
      use_as_row_header  => "'N'",
    ) . "\n);\n");
    $n++;
  }
  out("wwv_flow_imp_page.create_worksheet_rpt(\n" . args(
    id               => wid(nid()),
    application_user => "'APXWS_DEFAULT'",
    report_seq       => 10,
    report_alias     => lit('R' . $ws),
    status           => "'PUBLIC'",
    is_default       => "'Y'",
    report_columns   => lit(join(':', @cols)),
  ) . "\n);\n");
}

# عرض أي استعلام كجدول HTML داخل منطقة PL/SQL (لا يحتاج تعريف أعمدة)
sub table_region {
  { my %tq = @_; push @main::SQLQ, ["P$CUR_PAGE table $tq{name}", $tq{sql}]; }
  my %r = @_;
  my $q = $r{sql};
  $q =~ s/;\s*\z//;
  my $code = <<'PLSQL';
DECLARE
  l_ctx  apex_exec.t_context;
  l_col  apex_exec.t_column;
  l_val  VARCHAR2(4000);
BEGIN
  l_ctx := apex_exec.open_query_context(
             p_location  => apex_exec.c_location_local_db,
             p_sql_query => q'~__SQL__~');
  htp.p('<div style="overflow-x:auto"><table class="jl-table"><thead><tr>');
  FOR i IN 1 .. apex_exec.get_column_count(l_ctx) LOOP
    l_col := apex_exec.get_column(l_ctx, i);
    IF l_col.name NOT LIKE '%\_ID' ESCAPE '\' AND l_col.name <> 'SORT_KEY' THEN
      htp.p('<th>' || apex_escape.html(l_col.name) || '</th>');
    END IF;
  END LOOP;
  htp.p('</tr></thead><tbody>');
  WHILE apex_exec.next_row(l_ctx) LOOP
    htp.p('<tr>');
    FOR i IN 1 .. apex_exec.get_column_count(l_ctx) LOOP
      l_col := apex_exec.get_column(l_ctx, i);
      IF l_col.name NOT LIKE '%\_ID' ESCAPE '\' AND l_col.name <> 'SORT_KEY' THEN
        IF l_col.data_type = apex_exec.c_data_type_number THEN
          l_val := TO_CHAR(apex_exec.get_number(l_ctx, i), CASE WHEN l_col.name LIKE 'عدد%' THEN 'FM999G999G990' ELSE 'FM999G999G999G999G990D00' END);
          htp.p('<td class="jl-num">' || l_val || '</td>');
        ELSE
          htp.p('<td>' || apex_escape.html(apex_exec.get_varchar2(l_ctx, i)) || '</td>');
        END IF;
      END IF;
    END LOOP;
    htp.p('</tr>');
  END LOOP;
  htp.p('</tbody></table></div>');
  apex_exec.close(l_ctx);
EXCEPTION WHEN OTHERS THEN
  apex_exec.close(l_ctx);
  RAISE;
END;
PLSQL
  $code =~ s/__SQL__/$q/;
  return region(%r, type => 'plsql', plsql => $code);
}

sub item {
  my %i = @_;
  push @main::PLSQL, ["P$CUR_PAGE item $i{name} cond", "BEGIN IF $i{cond} THEN NULL; END IF; END;"] if $i{cond};
  my $id = nid();
  my $type = $i{type} // 'text';
  # شركة واحدة وعملة واحدة: حقول الشركة والعملة وسعر الصرف وخيارات الدمج تُخفى في كل الشاشات
  if (!$i{col} && $i{name} =~ /^P\d+_(COMPANY_ID|COMPANY|CURRENCY_CODE|CURRENCY|EXCHANGE_RATE|MODE|SEPARATE|EXCLUDE_INTERCO)$/) {
    $type = 'hidden';
  }
  my %t;
  if ($type eq 'text') {
    %t = (display_as => "'NATIVE_TEXT_FIELD'", cSize => 30, cMaxlength => $i{max} // 4000,
          attribute_01 => "'N'", attribute_02 => "'N'", attribute_04 => "'TEXT'", attribute_05 => "'BOTH'");
  } elsif ($type eq 'select') {
    push @main::SQLQ, ["P$CUR_PAGE lov $i{name}", $i{lov}];
    %t = (display_as => "'NATIVE_SELECT_LIST'", lov => txt($i{lov}),
          lov_display_null => $i{null} ? "'YES'" : undef, lov_null_text => $i{null} ? lit($i{null} eq '1' ? '' : $i{null}) : undef,
          cHeight => 1, lov_display_extra => $i{extra} ? "'YES'" : "'NO'",
          attribute_01 => $i{submit} ? "'SUBMIT'" : "'NONE'");
  } elsif ($type eq 'popup') {
    push @main::SQLQ, ["P$CUR_PAGE lov $i{name}", $i{lov}];
    %t = (display_as => "'NATIVE_POPUP_LOV'", lov => txt($i{lov}), cSize => 30,
          lov_display_null => "'YES'", lov_display_extra => "'NO'",
          attribute_01 => "'POPUP'", attribute_02 => "'FIRST_ROWSET'", attribute_04 => "'N'", attribute_05 => "'N'");
  } elsif ($type eq 'date') {
    %t = (display_as => "'NATIVE_DATE_PICKER_APEX'", format_mask => "'DD/MM/YYYY'", cSize => 32, cMaxlength => 4000,
          attribute_01 => "'N'", attribute_02 => "'POPUP'", attribute_03 => "'NONE'", attribute_06 => "'NONE'",
          attribute_09 => "'N'", attribute_11 => "'Y'");
  } elsif ($type eq 'checkbox') {
    # خانة اختيار: Y / N
    %t = (display_as => "'NATIVE_SINGLE_CHECKBOX'", attribute_01 => "'N'", attribute_02 => "'Y'", attribute_03 => "'N'");
  } elsif ($type eq 'password') {
    %t = (display_as => "'NATIVE_PASSWORD'", cSize => 40, cMaxlength => 100, attribute_01 => "'Y'");
  } elsif ($type eq 'hidden') {
    %t = (display_as => "'NATIVE_HIDDEN'", attribute_01 => $i{protected} ? "'Y'" : "'N'");
  } else { die "item type $type" }
  my $fld = $type eq 'hidden' ? 'fld_hidden' : ($i{required} ? 'fld_req' : 'fld_opt');
  out("wwv_flow_imp_page.create_page_item(\n" . args(
    id                    => wid($id),
    name                  => lit($i{name}),
    source_data_type      => $i{col} ? lit($i{dtype} // 'VARCHAR2') : undef,
    is_primary_key        => $i{pk} ? 'true' : undef,
    is_query_only         => $i{query_only} ? 'true' : undef,
    item_sequence         => $i{seq} // 10,
    item_plug_id          => wid($REG{"$CUR_PAGE:$i{region}"} // die "no region $i{region}"),
    item_source_plug_id   => $i{col} ? wid($REG{"$CUR_PAGE:$i{region}"}) : undef,
    use_cache_before_default => $i{pk} ? "'NO'" : undef,
    prompt                => lit($i{label} // $i{name}),
    source                => $i{col} ? lit($i{col}) : undef,
    source_type           => $i{col} ? "'REGION_SOURCE_COLUMN'" : undef,
    %t,
    tag_attributes        => $i{readonly} ? "'readonly tabindex=\"-1\" style=\"background:#f3f3f3\"'" : undef,
    begin_on_new_line     => $i{same_line} ? "'N'" : undef,
    colspan               => $i{span},
    field_template        => wid($T{$fld}),
    item_template_options => "'#DEFAULT#'",
    is_required           => $i{required} && $i{col} && $type ne 'hidden' ? 'true' : undef,   # الصفحات بدون نموذج: التحقق في الخادم
    is_persistent         => "'N'",
    protection_level      => $type eq 'hidden' && $i{protected} ? "'S'" : undef,
    display_when          => $i{cond} ? lit($i{cond}) : undef,
    display_when2         => $i{cond} ? "'PLSQL'" : undef,
    display_when_type     => $i{cond} ? "'EXPRESSION'" : undef,
  ) . "\n);\n");
  return $id;
}

sub button {
  my %b = @_;
  push @main::PLSQL, ["P$CUR_PAGE button $b{name} cond", "BEGIN IF $b{cond} THEN NULL; END IF; END;"] if $b{cond};
  my $id = nid();
  $BTN{"$CUR_PAGE:$b{name}"} = $id;
  my $action = $b{js} ? 'REDIRECT_URL' : $b{url} ? 'REDIRECT_URL' : 'SUBMIT';
  my $url = $b{js} ? "javascript:$b{js}" : $b{url};
  my %cond;
  if ($b{cond}) { %cond = (button_condition => lit($b{cond}), button_condition2 => "'PLSQL'", button_condition_type => "'EXPRESSION'") }
  if ($b{if_null})     { %cond = (button_condition => lit($b{if_null}),     button_condition_type => "'ITEM_IS_NULL'") }
  if ($b{if_not_null}) { %cond = (button_condition => lit($b{if_not_null}), button_condition_type => "'ITEM_IS_NOT_NULL'") }
  out("wwv_flow_imp_page.create_page_button(\n" . args(
    id                       => wid($id),
    button_sequence          => $b{seq} // 10,
    button_plug_id           => wid($REG{"$CUR_PAGE:$b{region}"} // die "no region $b{region}"),
    button_name              => lit($b{name}),
    button_action            => lit($action),
    button_template_options  => "'#DEFAULT#'",
    button_template_id       => wid($T{btn_text}),
    button_is_hot            => $b{hot} ? "'Y'" : undef,
    button_image_alt         => lit($b{label}),
    button_position          => lit($b{position} // 'NEXT'),
    button_redirect_url      => $url ? lit($url) : undef,
    button_execute_validations => $b{novalidate} ? "'N'" : undef,
    confirm_message          => $b{confirm} ? lit($b{confirm}) : undef,
    confirm_style            => $b{confirm} ? "'danger'" : undef,
    %cond,
    database_action          => $b{dml} ? lit($b{dml}) : undef,
    security_scheme          => $b{auth} ? wid($SEC{$b{auth}}) : undef,
    warn_on_unsaved_changes  => $action eq 'REDIRECT_URL' ? 'null' : undef,
  ) . "\n);\n");
  return $id;
}

sub process {
  my %p = @_;
  $p{code} =~ s/__WF([0-9]+)__/main::wf_load("P$1")/ge if defined $p{code};   # معلومات المراجعة والاعتماد في تحميل المستند
  push @main::PLSQL, ["P$CUR_PAGE process $p{name} cond", "BEGIN IF $p{cond} THEN NULL; END IF; END;"] if $p{cond} && !$p{when_req};
  my $id = nid();
  my %type;
  if (($p{kind} // 'plsql') eq 'plsql') {
    push @main::PLSQL, ["P$CUR_PAGE process $p{name}", $p{code}];
    %type = (process_type => "'NATIVE_PLSQL'", process_sql_clob => txt($p{code}), process_clob_language => "'PLSQL'");
  } elsif ($p{kind} eq 'form_init') {
    %type = (region_id => wid($REG{"$CUR_PAGE:$p{region}"}), process_type => "'NATIVE_FORM_INIT'");
  } elsif ($p{kind} eq 'form_dml') {
    %type = (region_id => wid($REG{"$CUR_PAGE:$p{region}"}), process_type => "'NATIVE_FORM_DML'",
             attribute_01 => "'REGION_SOURCE'", attribute_05 => "'Y'", attribute_06 => "'Y'", attribute_08 => "'Y'");
  } elsif ($p{kind} eq 'close') {
    %type = (process_type => "'NATIVE_CLOSE_WINDOW'", attribute_02 => "'Y'");
  }
  out("wwv_flow_imp_page.create_page_process(\n" . args(
    id                     => wid($id),
    process_sequence       => $p{seq} // 10,
    process_point          => lit($p{point} // 'AFTER_SUBMIT'),
    %type,
    process_name           => lit($p{name}),
    error_display_location => "'INLINE_IN_NOTIFICATION'",
    process_when_button_id => $p{button} ? wid($BTN{"$CUR_PAGE:$p{button}"} // die "no button $p{button}") : undef,
    process_when           => $p{when_req} ? lit($p{when_req}) : $p{cond} ? lit($p{cond}) : undef,
    process_when_type      => $p{when_req} ? "'REQUEST_IN_CONDITION'" : $p{cond} ? "'EXPRESSION'" : undef,
    process_when2          => $p{cond} && !$p{when_req} ? "'PLSQL'" : undef,
    process_success_message=> $p{success} ? lit($p{success}) : undef,
    internal_uid           => $id,
  ) . "\n);\n");
}

sub ajax { my ($name, $code, $seq) = @_; process(point => 'ON_DEMAND', name => $name, code => $code, seq => $seq // 10) }

# دالة تحقق (تُرجع رسالة خطأ) تتحول إلى عملية تضيف الخطأ بـ apex_error
sub check {
  my %c = @_;
  my $body = $c{code};
  $body =~ s/^\s+|\s+$//g;
  my $fn;
  if ($body =~ s/^DECLARE\b//i) { $fn = "FUNCTION chk RETURN VARCHAR2 IS\n$body" }
  else                          { $fn = "FUNCTION chk RETURN VARCHAR2 IS\nBEGIN\n$body\nEND;" }
  $fn =~ s/;\s*$/;/;
  my $code = "DECLARE\n  l_err VARCHAR2(4000);\n$fn\nBEGIN\n  l_err := chk;\n  IF l_err IS NOT NULL THEN\n    apex_error.add_error(p_message => l_err, p_display_location => apex_error.c_inline_in_notification);\n  END IF;\nEND;";
  process(%c, code => $code);
}

# تحويل بعد المعالجة إلى رابط، اختيارياً حسب الزر (when_req)
sub branch_to {
  my %b = @_;
  out("wwv_flow_imp_page.create_page_branch(
" . args(
    id                    => wid(nid()),
    branch_name           => lit($b{name} // "Branch $b{seq}"),
    branch_action         => lit($b{url}),
    branch_point          => "'AFTER_PROCESSING'",
    branch_type           => "'REDIRECT_URL'",
    branch_sequence       => $b{seq} // 10,
    branch_condition_type => $b{when_req} ? "'REQUEST_IN_CONDITION'" : undef,
    branch_condition      => $b{when_req} ? lit($b{when_req}) : undef,
  ) . "
);
");
}

sub branch_self {
  my $page = $CUR_PAGE;
  my @keep = @_;   # عناصر تبقى بعد الحفظ (المستند يبقى ظاهراً)
  my $set = @keep ? join(",", @keep) . ":" . join(",", map { "&$_." } @keep) : ":";
  out("wwv_flow_imp_page.create_page_branch(\n" . args(
    id               => wid(nid()),
    branch_name      => "'Go To Page $page'",
    branch_action    => lit("f?p=&APP_ID.:$page:&SESSION.::&DEBUG.::$set&success_msg=#SUCCESS_MSG#"),
    branch_point     => "'AFTER_PROCESSING'",
    branch_type      => "'REDIRECT_URL'",
    branch_sequence  => 10,
  ) . "\n);\n");
}

1;

# إيقاف العملية إذا سبقتها أخطاء تحقق (يُدرج بعد أول BEGIN رئيسي)
sub guard {
  my $code = shift;
  $code =~ s/\nBEGIN\n/\nBEGIN\n  IF apex_error.have_errors_occurred THEN RETURN; END IF;\n/ or die "guard: no BEGIN";
  return $code;
}
1;
