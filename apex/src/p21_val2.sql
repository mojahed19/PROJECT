RETURN CASE WHEN :P21_JT_CODE IN ('RV','PV','INV','RET','PAY','REV')
             AND :P21_MANUAL_ALLOWED = 'Y'
            THEN 'هذا النوع يُنشأ آلياً من شاشته ولا يُدخل يدوياً' END;
