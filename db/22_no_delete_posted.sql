-- =====================================================================
--  22_no_delete_posted.sql  -  منع حذف المستندات بعد الترحيل / الاعتماد (على مستوى قاعدة البيانات)
--   يُسمح بالحذف فقط للمسودة أو المعاد للتصحيح أو الملغى ؛ المستند المرحّل يُصحَّح بالعكس (صفحة عكس القيود)
--   استثناءات مقصودة في النظام:
--     - قيد الإقفال (CLOSING): يحذفه fy_reopen عند إعادة فتح السنة
--     - قيد تسوية الشيك (CHEQUE): يحذفه "إلغاء التسوية" في جدولة الشيكات بعد فك ربطه بالشيك
--   الشيك يُحذف فقط وهو قائم (PENDING) ، أي مع حذف إذنه وهو مسودة
--   سكربت تنظيف البيانات (clean_data.sql) يعطّل هذه الـ Triggers أثناء التنظيف ثم يعيدها
-- =====================================================================
SET DEFINE OFF

CREATE OR REPLACE TRIGGER trg_nodel_journals
BEFORE DELETE ON journals FOR EACH ROW
DECLARE
  l_cnt NUMBER;
BEGIN
  IF :OLD.status IN ('DRAFT','RETURNED') THEN RETURN; END IF;
  IF :OLD.source_type = 'CLOSING' THEN RETURN; END IF;
  IF :OLD.source_type = 'CHEQUE' THEN
    SELECT COUNT(*) INTO l_cnt FROM cheques WHERE settle_journal_id = :OLD.journal_id;
    IF l_cnt = 0 THEN RETURN; END IF;
  END IF;
  raise_application_error(-20201, 'لا يمكن حذف القيد ' || :OLD.journal_no || ' بعد الترحيل أو الاعتماد. صحّحه بالعكس من صفحة عكس القيود');
END;
/

DECLARE
  -- الجدول ، رقم المستند ، اسمه ، الحالات التي يُسمح فيها بالحذف
  TYPE t_rec IS RECORD (tab VARCHAR2(30), no_col VARCHAR2(30), name_ar VARCHAR2(50), ok VARCHAR2(200));
  TYPE t_list IS TABLE OF t_rec;
  l t_list := t_list();
  PROCEDURE add (p_tab VARCHAR2, p_no VARCHAR2, p_name VARCHAR2, p_ok VARCHAR2) IS
  BEGIN l.EXTEND; l(l.COUNT).tab := p_tab; l(l.COUNT).no_col := p_no; l(l.COUNT).name_ar := p_name; l(l.COUNT).ok := p_ok; END;
BEGIN
  add('VOUCHERS',          'VOUCHER_NO',  'الإذن',          q'['DRAFT','RETURNED']');
  add('INVOICES',          'INVOICE_NO',  'الفاتورة',       q'['DRAFT','RETURNED']');
  add('PURCHASE_INVOICES', 'INVOICE_NO',  'فاتورة المشتريات', q'['DRAFT','RETURNED']');
  add('STOCK_TRANS',       'TRANS_NO',    'حركة المخزون',   q'['DRAFT','RETURNED']');
  add('PAYROLL_RUNS',      NULL,          'مسير الرواتب',   q'['DRAFT','CANCELLED']');
  add('PAYROLL_ADJ',       'ADJ_NO',      'المستند',        q'['DRAFT','RETURNED','CANCELLED']');
  add('ANNUAL_INCENTIVES', 'INC_NO',      'الحافز السنوي',  q'['DRAFT']');
  add('CHEQUES',           'CHEQUE_NO',   'الشيك',          q'['PENDING']');
  FOR i IN 1 .. l.COUNT LOOP
    EXECUTE IMMEDIATE
         'CREATE OR REPLACE TRIGGER trg_nodel_' || LOWER(l(i).tab) || CHR(10)
      || 'BEFORE DELETE ON ' || l(i).tab || ' FOR EACH ROW' || CHR(10)
      || 'BEGIN' || CHR(10)
      || '  IF :OLD.status NOT IN (' || l(i).ok || ') THEN' || CHR(10)
      || '    raise_application_error(-20202, ''لا يمكن حذف ' || l(i).name_ar
      || CASE WHEN l(i).no_col IS NOT NULL THEN ' '' || :OLD.' || l(i).no_col || ' || ''' END
      || ' بعد الترحيل أو الاعتماد (الحالة '' || :OLD.status || ''). صحّحه بالعكس'');' || CHR(10)
      || '  END IF;' || CHR(10)
      || 'END;';
    DBMS_OUTPUT.PUT_LINE('TRIGGER trg_nodel_' || LOWER(l(i).tab));
  END LOOP;
END;
/
