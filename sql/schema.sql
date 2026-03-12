-- =====================================================
-- جامعة دمشق - Quiz App - Database Schema
-- انسخ هذا الكود بالكامل وشغّله في Supabase → SQL Editor
-- =====================================================

-- =================== TABLES ===================

CREATE TABLE IF NOT EXISTS faculties (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  icon       TEXT DEFAULT '📚',
  color      TEXT DEFAULT 'rgba(201,168,67,0.12)',
  is_active  BOOLEAN DEFAULT true,
  sort_order INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS subjects (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  faculty_id  TEXT REFERENCES faculties(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  icon        TEXT DEFAULT '📖',
  year        INT DEFAULT 1,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS questions (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  subject_id    UUID REFERENCES subjects(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL,
  option_a      TEXT NOT NULL,
  option_b      TEXT NOT NULL,
  option_c      TEXT,
  option_d      TEXT,
  correct_opt   CHAR(1) NOT NULL CHECK (correct_opt IN ('a','b','c','d')),
  explanation   TEXT,
  difficulty    SMALLINT DEFAULT 1 CHECK (difficulty BETWEEN 1 AND 3),
  is_active     BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS access_codes (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code           TEXT UNIQUE NOT NULL,
  faculty_access TEXT[] DEFAULT ARRAY['all']::TEXT[],
  is_active      BOOLEAN DEFAULT true,
  expires_at     TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '6 months'),
  uses_count     INT DEFAULT 0,
  max_uses       INT DEFAULT 1,
  notes          TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  access_code      TEXT,
  subject_id       UUID REFERENCES subjects(id),
  score            INT NOT NULL,
  total            INT NOT NULL,
  duration_seconds INT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- =================== ROW LEVEL SECURITY ===================

ALTER TABLE faculties     ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects      ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_codes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions      ENABLE ROW LEVEL SECURITY;

-- Public can read active faculties, subjects, questions
CREATE POLICY "read_faculties"  ON faculties    FOR SELECT USING (is_active = true);
CREATE POLICY "read_subjects"   ON subjects     FOR SELECT USING (is_active = true);
CREATE POLICY "read_questions"  ON questions    FOR SELECT USING (is_active = true);

-- Anyone can verify a code (read by code value)
CREATE POLICY "verify_code"     ON access_codes FOR SELECT USING (true);

-- Students can log their session results
CREATE POLICY "log_session"     ON sessions     FOR INSERT WITH CHECK (true);

-- =================== VIEWS ===================

-- Subject with question count
CREATE OR REPLACE VIEW subjects_with_count AS
  SELECT s.*, COUNT(q.id) AS question_count
  FROM subjects s
  LEFT JOIN questions q ON q.subject_id = s.id AND q.is_active = true
  GROUP BY s.id;

-- Daily stats
CREATE OR REPLACE VIEW daily_stats AS
  SELECT
    DATE(created_at) AS day,
    COUNT(*) AS total_sessions,
    ROUND(AVG(score::NUMERIC / NULLIF(total,0) * 100), 1) AS avg_score
  FROM sessions
  GROUP BY DATE(created_at)
  ORDER BY day DESC;

-- =================== SEED DATA ===================

INSERT INTO faculties (id, name, icon, sort_order) VALUES
  ('engineering', 'الهندسة المدنية',  '⚙️', 1),
  ('medicine',    'الطب البشري',      '🩺', 2),
  ('law',         'الحقوق',           '⚖️', 3),
  ('science',     'العلوم',           '🔬', 4),
  ('arts',        'الآداب',           '📖', 5),
  ('pharmacy',    'الصيدلة',          '💊', 6),
  ('economics',   'الاقتصاد',         '💹', 7),
  ('dentistry',   'طب الأسنان',       '🦷', 8)
ON CONFLICT (id) DO NOTHING;

-- Sample subjects for engineering
WITH eng_subject AS (
  INSERT INTO subjects (faculty_id, name, icon, year) VALUES
    ('engineering', 'رياضيات 1',         '📐', 1),
    ('engineering', 'فيزياء عامة',        '⚡', 1),
    ('engineering', 'ميكانيك التشييد',   '🏗️', 2),
    ('engineering', 'مقاومة المواد',     '🔩', 2),
    ('engineering', 'هندسة التربة',      '🌍', 3),
    ('engineering', 'الخرسانة المسلحة',  '🧱', 3)
  RETURNING id, name
)
SELECT * FROM eng_subject;

-- Sample access code for testing
INSERT INTO access_codes (code, faculty_access, notes, max_uses) VALUES
  ('TEST-1234', ARRAY['all']::TEXT[],         'كود تجريبي',      999),
  ('ENG-2024',  ARRAY['engineering']::TEXT[], 'كلية الهندسة',    50)
ON CONFLICT (code) DO NOTHING;

-- =================== HELPER FUNCTION ===================

-- Function to use a code (increments counter and validates)
CREATE OR REPLACE FUNCTION use_code(p_code TEXT)
RETURNS TABLE(valid BOOLEAN, message TEXT, faculty_access TEXT[]) AS $$
DECLARE
  r access_codes%ROWTYPE;
BEGIN
  SELECT * INTO r FROM access_codes WHERE code = p_code;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'الكود غير موجود'::TEXT, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  IF NOT r.is_active THEN
    RETURN QUERY SELECT false, 'الكود موقوف'::TEXT, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  IF r.expires_at IS NOT NULL AND r.expires_at < NOW() THEN
    RETURN QUERY SELECT false, 'انتهت صلاحية الكود'::TEXT, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  -- Increment usage count
  UPDATE access_codes SET uses_count = uses_count + 1 WHERE code = p_code;

  RETURN QUERY SELECT true, 'تم التحقق بنجاح'::TEXT, r.faculty_access;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
