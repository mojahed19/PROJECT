DECLARE
  r sales_shifts%ROWTYPE;
BEGIN
  IF :P58_SHIFT_ID IS NULL THEN
    SELECT MAX(shift_id) INTO :P58_SHIFT_ID FROM sales_shifts WHERE user_name = :APP_USER AND status IN ('OPEN','RETURNED');
  END IF;
  SELECT DECODE(COUNT(*), 0, 'N', 'Y') INTO :P58_HAS_OPEN FROM sales_shifts WHERE user_name = :APP_USER AND status IN ('OPEN','RETURNED');
  IF :P58_SHIFT_ID IS NOT NULL THEN
    SELECT * INTO r FROM sales_shifts WHERE shift_id = :P58_SHIFT_ID;
    :P58_SHIFT_NO := r.shift_no;
    :P58_STATUS   := r.status;
    :P58_USER     := r.user_name;
    :P58_NOTES    := r.notes;
    :P58_INFO     := 'البائع: ' || r.user_name || ' - فُتحت ' || TO_CHAR(r.opened_on, 'DD/MM/YYYY HH24:MI')
                  || CASE WHEN r.closed_on IS NOT NULL THEN ' - أُغلقت ' || TO_CHAR(r.closed_on, 'DD/MM/YYYY HH24:MI') END;
    __WF__
  END IF;
END;
