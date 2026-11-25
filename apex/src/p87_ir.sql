SELECT a.audit_id,
       TO_CHAR(a.changed_on, 'YYYY/MM/DD HH24:MI:SS') AS "الوقت",
       a.changed_by AS "المستخدم",
       DECODE(a.action, 'I', 'إضافة', 'U', 'تعديل', 'D', 'حذف') AS "العملية",
       DECODE(a.table_name,
              'ACCOUNTS', 'شجرة الحسابات', 'ACCOUNT_SETTINGS', 'الحسابات الافتراضية', 'JOURNALS', 'القيود',
              'VOUCHERS', 'الأذونات', 'CHEQUES', 'الشيكات', 'INVOICES', 'فواتير المبيعات',
              'PURCHASE_INVOICES', 'فواتير المشتريات', 'STOCK_TRANS', 'حركات المخزون', 'ITEMS', 'الأصناف',
              'ITEM_UNITS', 'وحدات الأصناف', 'WAREHOUSES', 'المخازن', 'APP_USERS', 'المستخدمون',
              'COMPANIES', 'بيانات الشركة', 'FISCAL_YEARS', 'السنوات المالية', 'EMPLOYEES', 'الموظفون',
              'PAYROLL_RUNS', 'مسير الرواتب', 'PAYROLL_ADJ', 'الخصومات والحوافز', 'ANNUAL_INCENTIVES', 'الحافز السنوي',
              'EXCHANGE_RATES', 'أسعار الصرف', a.table_name) AS "الشاشة / الجدول",
       a.doc_ref AS "رقم المستند",
       a.row_key AS "المعرّف",
       a.page_id AS "الصفحة",
       a.details AS "التفاصيل"
FROM   audit_log a
WHERE  a.changed_on >= TO_DATE(:P87_FROM, 'DD/MM/YYYY')
AND    a.changed_on <  TO_DATE(:P87_TO, 'DD/MM/YYYY') + 1
AND    (:P87_TABLE IS NULL OR a.table_name = :P87_TABLE)
AND    (:P87_USER  IS NULL OR a.changed_by = :P87_USER)
AND    (:P87_ACTION IS NULL OR a.action = :P87_ACTION)
ORDER  BY a.audit_id DESC
