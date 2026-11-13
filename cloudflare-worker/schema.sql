CREATE TABLE IF NOT EXISTS tests (
  id TEXT PRIMARY KEY,
  serial_number TEXT NOT NULL,
  model_name TEXT NOT NULL,
  technician_name TEXT NOT NULL,
  profile_name TEXT NOT NULL DEFAULT 'Perfil padrão',
  status TEXT NOT NULL CHECK (status IN ('APROVADA','REPROVADA','INCONCLUSIVA')),
  verdict_reason TEXT NOT NULL,
  initial_temp REAL NOT NULL,
  final_temp REAL NOT NULL,
  target_temp REAL NOT NULL,
  max_allowed_minutes INTEGER NOT NULL,
  duration_minutes INTEGER NOT NULL,
  cooling_rate REAL NOT NULL DEFAULT 0,
  door_open_events INTEGER NOT NULL DEFAULT 0,
  compressor_duty_cycle REAL NOT NULL DEFAULT 1,
  start_time TEXT,
  end_time TEXT,
  readings_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tests_created_at ON tests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tests_status ON tests(status);
CREATE INDEX IF NOT EXISTS idx_tests_serial ON tests(serial_number);
