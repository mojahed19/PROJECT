SELECT CASE WHEN CONNECT_BY_ISLEAF = 1 THEN 0
            WHEN LEVEL = 1 THEN 1 ELSE -1 END        AS status,
       LEVEL                                          AS lvl,
       a.account_code || ' - ' || a.name_ar          AS title,
       CASE a.acc_level WHEN 4 THEN 'fa fa-file-text-o' ELSE 'fa fa-folder' END AS icon,
       a.account_id                                   AS value,
       a.account_code || ' - ' || a.name_ar          AS tooltip,
       apex_page.get_url(p_page => 10, p_items => 'P10_ACCOUNT_ID',
                         p_values => a.account_id)    AS link
FROM   accounts a
START  WITH a.parent_id IS NULL
CONNECT BY PRIOR a.account_id = a.parent_id
ORDER  SIBLINGS BY a.account_code
