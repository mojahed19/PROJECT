BEGIN
      -- اعتماد الوردية: ترحيل قيود مبيعاتها
      UPDATE journals j
      SET    status = 'POSTED', posted_by = :APP_USER, posted_on = SYSDATE,
             reviewed_by = (SELECT reviewed_by FROM sales_shifts WHERE shift_id = l_id),
             reviewed_on = (SELECT reviewed_on FROM sales_shifts WHERE shift_id = l_id),
             approved_by = :APP_USER, approved_on = SYSDATE
      WHERE  j.status = 'DRAFT'
      AND    j.journal_id IN (SELECT journal_id FROM invoices WHERE shift_id = l_id AND status = 'POSTED');
    END;
