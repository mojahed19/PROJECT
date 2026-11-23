DECLARE
  -- كل بنود الميزانية الفعّالة مع قيم خطة الإدارة (x01 = رقم الخطة)
  l_lines CLOB;
BEGIN
  SELECT JSON_ARRAYAGG(JSON_OBJECT(
           'BITEM_ID' VALUE b.bitem_id, 'NOTE_NO' VALUE b.note_no, 'NAME_AR' VALUE b.name_ar,
           'TYPE_T'   VALUE DECODE(b.item_type, 'REV', 'إيرادات', 'مصروفات'),
           'Q1' VALUE NULLIF(l.q1, 0), 'Q2' VALUE NULLIF(l.q2, 0), 'Q3' VALUE NULLIF(l.q3, 0), 'Q4' VALUE NULLIF(l.q4, 0),
           'NOTES' VALUE l.notes)
         ORDER BY b.sort_order, b.note_no RETURNING CLOB)
  INTO   l_lines
  FROM   budget_items b
  LEFT JOIN budget_plan_lines l ON l.bitem_id = b.bitem_id AND l.plan_id = TO_NUMBER(apex_application.g_x01)
  WHERE  b.is_active = 'Y' OR l.pline_id IS NOT NULL;

  apex_util.prn('{"lines":' || COALESCE(l_lines, TO_CLOB('[]')) || '}', FALSE);
END;
