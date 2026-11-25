-- =====================================================================
--  17_indexes.sql  -  فهارس الأداء (آمن لإعادة التشغيل: لا يُنشئ فهرساً موجوداً بنفس الأعمدة الأولى)
--   1) فلاتر التقارير: الحالة والتاريخ (القيود ، المخزون ، الفواتير ، المشتريات ، الأذونات)
--   2) البحث بالصنف: سطور المبيعات والمشتريات والمخزون
--   3) المفاتيح الأجنبية إلى القيود وحركات المخزون: حذف قيد (إلغاء تسوية شيك ، إعادة مستند)
--      يفحص كل جدول يشير إليه ؛ بلا فهرس يقرأ الجدول كاملاً ويقفله
--  ثم تحديث إحصائيات المخطط ليختار Oracle أفضل خطة تنفيذ
-- =====================================================================
SET DEFINE OFF

DECLARE
  PROCEDURE ix (p_name VARCHAR2, p_table VARCHAR2, p_cols VARCHAR2) IS
    l_cnt NUMBER;
  BEGIN
    -- موجود؟ (نفس الجدول وتبدأ أعمدته بنفس الأعمدة بالترتيب)
    SELECT COUNT(*) INTO l_cnt
    FROM (SELECT i.index_name, LISTAGG(c.column_name, ',') WITHIN GROUP (ORDER BY c.column_position) cols
          FROM user_indexes i JOIN user_ind_columns c ON c.index_name = i.index_name
          WHERE i.table_name = UPPER(p_table) GROUP BY i.index_name)
    WHERE cols = UPPER(REPLACE(p_cols, ' ')) OR cols LIKE UPPER(REPLACE(p_cols, ' ')) || ',%';
    IF l_cnt = 0 THEN
      EXECUTE IMMEDIATE 'CREATE INDEX ' || p_name || ' ON ' || p_table || ' (' || p_cols || ')';
      DBMS_OUTPUT.PUT_LINE('CREATED ' || p_name);
    ELSE
      DBMS_OUTPUT.PUT_LINE('EXISTS  ' || p_name);
    END IF;
  END;
BEGIN
  ------------------------------------------------------------------ 1) فلاتر التقارير
  ix('ix_jnl_date_status',  'journals',          'journal_date, status');
  ix('ix_jnl_status',       'journals',          'status');
  ix('ix_jl_acc_jnl',       'journal_lines',     'account_id, journal_id');
  ix('ix_st_date_status',   'stock_trans',       'trans_date, status');
  ix('ix_st_wh',            'stock_trans',       'warehouse_id');
  ix('ix_inv_date_status',  'invoices',          'invoice_date, status');
  ix('ix_inv_shift',        'invoices',          'shift_id');
  ix('ix_inv_wh',           'invoices',          'warehouse_id');
  ix('ix_inv_account',      'invoices',          'account_id');
  ix('ix_pinv_date_status', 'purchase_invoices', 'invoice_date, status');
  ix('ix_pinv_supplier',    'purchase_invoices', 'supplier_account_id');
  ix('ix_vch_date_status',  'vouchers',          'voucher_date, status');
  ix('ix_vch_counter',      'vouchers',          'counter_account_id');

  ------------------------------------------------------------------ 2) البحث بالصنف
  ix('ix_stl_item',         'stock_trans_lines',      'item_id');
  ix('ix_invl_item',        'invoice_lines',          'item_id');
  ix('ix_pinvl_item',       'purchase_invoice_lines', 'item_id');
  ix('ix_pli_item',         'price_list_items',       'item_id');

  ------------------------------------------------------------------ 3) المفاتيح الأجنبية إلى القيود وحركات المخزون
  ix('ix_jnl_reversal_of',  'journals',          'reversal_of_id');
  ix('ix_jnl_reversed_by',  'journals',          'reversed_by_id');
  ix('ix_chq_settle_jnl',   'cheques',           'settle_journal_id');
  ix('ix_inv_journal',      'invoices',          'journal_id');
  ix('ix_inv_sub_journal',  'invoices',          'sub_journal_id');
  ix('ix_inv_stock_out',    'invoices',          'stock_out_id');
  ix('ix_inv_stock_in',     'invoices',          'stock_in_id');
  ix('ix_pinv_journal',     'purchase_invoices', 'journal_id');
  ix('ix_pinv_stock',       'purchase_invoices', 'stock_trans_id');
  ix('ix_st_journal',       'stock_trans',       'journal_id');
  ix('ix_vch_journal',      'vouchers',          'journal_id');
  ix('ix_ainc_journal',     'annual_incentives', 'journal_id');
  ix('ix_prj_journal',      'payroll_run_journals', 'journal_id');
END;
/

-- إحصائيات حديثة للمخطط (الجداول صغيرة الآن ، وتُعاد دورياً مع نمو البيانات)
BEGIN
  -- CURRENT_SCHEMA وليس USER: في APEX SQL Commands المستخدم هو APEX_PUBLIC_USER والمخطط MOSS
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), cascade => TRUE);
END;
/
