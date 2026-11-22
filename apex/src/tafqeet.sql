  -- تفقيط المبلغ بالعربية: جنيه سوداني وقرش
  FUNCTION words3 (n PLS_INTEGER) RETURN VARCHAR2 IS
    TYPE t_a IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
    o t_a; t t_a; h t_a;
    l_h PLS_INTEGER := TRUNC(n / 100);
    l_r PLS_INTEGER := MOD(n, 100);
    l_s VARCHAR2(200);
    l_x VARCHAR2(100);
  BEGIN
    o(1) := 'واحد'; o(2) := 'اثنان'; o(3) := 'ثلاثة'; o(4) := 'أربعة'; o(5) := 'خمسة';
    o(6) := 'ستة'; o(7) := 'سبعة'; o(8) := 'ثمانية'; o(9) := 'تسعة'; o(10) := 'عشرة';
    o(11) := 'أحد عشر'; o(12) := 'اثنا عشر'; o(13) := 'ثلاثة عشر'; o(14) := 'أربعة عشر'; o(15) := 'خمسة عشر';
    o(16) := 'ستة عشر'; o(17) := 'سبعة عشر'; o(18) := 'ثمانية عشر'; o(19) := 'تسعة عشر';
    t(2) := 'عشرون'; t(3) := 'ثلاثون'; t(4) := 'أربعون'; t(5) := 'خمسون';
    t(6) := 'ستون'; t(7) := 'سبعون'; t(8) := 'ثمانون'; t(9) := 'تسعون';
    h(1) := 'مائة'; h(2) := 'مائتان'; h(3) := 'ثلاثمائة'; h(4) := 'أربعمائة'; h(5) := 'خمسمائة';
    h(6) := 'ستمائة'; h(7) := 'سبعمائة'; h(8) := 'ثمانمائة'; h(9) := 'تسعمائة';
    IF l_h > 0 THEN l_s := h(l_h); END IF;
    IF l_r > 0 THEN
      IF l_r < 20 THEN l_x := o(l_r);
      ELSIF MOD(l_r, 10) = 0 THEN l_x := t(TRUNC(l_r / 10));
      ELSE l_x := o(MOD(l_r, 10)) || ' و' || t(TRUNC(l_r / 10));
      END IF;
      l_s := CASE WHEN l_s IS NULL THEN l_x ELSE l_s || ' و' || l_x END;
    END IF;
    RETURN l_s;
  END;

  FUNCTION words (p NUMBER) RETURN VARCHAR2 IS
    l_n   NUMBER := TRUNC(ABS(p));
    l_g   PLS_INTEGER;
    l_s   VARCHAR2(1000);
    l_x   VARCHAR2(300);
    TYPE t_s IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
    s1 t_s; s2 t_s; sp t_s;
  BEGIN
    IF l_n = 0 THEN RETURN 'صفر'; END IF;
    s1(1) := 'ألف';   s2(1) := 'ألفان';   sp(1) := 'آلاف';
    s1(2) := 'مليون'; s2(2) := 'مليونان'; sp(2) := 'ملايين';
    s1(3) := 'مليار'; s2(3) := 'ملياران'; sp(3) := 'مليارات';
    FOR i IN REVERSE 0 .. 3 LOOP
      l_g := TRUNC(MOD(l_n, POWER(1000, i + 1)) / POWER(1000, i));
      IF l_g > 0 THEN
        IF i = 0 THEN l_x := words3(l_g);
        ELSIF l_g = 1 THEN l_x := s1(i);
        ELSIF l_g = 2 THEN l_x := s2(i);
        ELSIF l_g BETWEEN 3 AND 10 THEN l_x := words3(l_g) || ' ' || sp(i);
        ELSE l_x := words3(l_g) || ' ' || s1(i);
        END IF;
        l_s := CASE WHEN l_s IS NULL THEN l_x ELSE l_s || ' و' || l_x END;
      END IF;
    END LOOP;
    RETURN l_s;
  END;

  FUNCTION tafqeet (p NUMBER) RETURN VARCHAR2 IS
    l_p NUMBER := ROUND(MOD(ABS(p), 1) * 100);
  BEGIN
    RETURN 'فقط ' || words(p) || ' جنيه سوداني'
        || CASE WHEN l_p > 0 THEN ' و' || words(l_p) || ' قرش' END || ' لا غير';
  END;
