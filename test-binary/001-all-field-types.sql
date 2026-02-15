-- 001-all-field-types.sql
-- Exercises all SQLite storage classes and type affinities.
--
-- SQLite has 5 storage classes: NULL, INTEGER, REAL, TEXT, BLOB
-- SQLite has 5 type affinities: INTEGER, TEXT, BLOB/NONE, REAL, NUMERIC
--
-- Affinity is determined by substring matching on the declared type
-- (see sqlite3AffinityType in build.c):
--   1. Contains "INT"  → INTEGER  (breaks immediately)
--   2. Contains "CHAR" → TEXT
--   3. Contains "CLOB" → TEXT
--   4. Contains "TEXT" → TEXT
--   5. Contains "BLOB" → BLOB     (only if not already TEXT/INTEGER)
--   6. Contains "REAL" → REAL     (only if still NUMERIC)
--   7. Contains "FLOA" → REAL     (only if still NUMERIC)
--   8. Contains "DOUB" → REAL     (only if still NUMERIC)
--   9. Otherwise        → NUMERIC  (the default)
--
-- Serial types exercised by data rows:
--   type 0: NULL
--   type 1: 1-byte signed int   (-128..127)
--   type 2: 2-byte signed int   (-32768..32767)
--   type 3: 3-byte signed int   (-8388608..8388607)
--   type 4: 4-byte signed int   (-2147483648..2147483647)
--   type 5: 6-byte signed int   (-140737488355328..140737488355327)
--   type 6: 8-byte signed int   (-9223372036854775808..9223372036854775807)
--   type 7: 8-byte IEEE 754 double
--   type 8: integer constant 0
--   type 9: integer constant 1
--   type >=12 even: BLOB
--   type >=13 odd:  TEXT

CREATE TABLE all_types (
  id INTEGER PRIMARY KEY,

  -- INTEGER affinity (any type containing "INT")
  col_integer INTEGER,
  col_int INT,
  col_tinyint TINYINT,
  col_smallint SMALLINT,
  col_mediumint MEDIUMINT,
  col_bigint BIGINT,
  col_unsigned_big_int "UNSIGNED BIG INT",
  col_int2 INT2,
  col_int4 INT4,
  col_int8 INT8,

  -- TEXT affinity (contains "CHAR", "CLOB", or "TEXT")
  col_text TEXT,
  col_character CHARACTER(20),
  col_varchar VARCHAR(255),
  col_varying_character "VARYING CHARACTER(255)",
  col_nchar NCHAR(55),
  col_native_character "NATIVE CHARACTER(70)",
  col_nvarchar NVARCHAR(100),
  col_clob CLOB,

  -- BLOB/NONE affinity (contains "BLOB", or no type given)
  col_blob BLOB,
  col_json_blob "JSON BLOB",
  col_no_type,

  -- REAL affinity (contains "REAL", "FLOA", or "DOUB")
  col_real REAL,
  col_double DOUBLE,
  col_double_precision "DOUBLE PRECISION",
  col_float FLOAT,

  -- NUMERIC affinity (the default: anything not matching above)
  col_numeric NUMERIC,
  col_decimal DECIMAL(10,5),
  col_boolean BOOLEAN,
  col_date DATE,
  col_datetime DATETIME,
  col_timestamp TIMESTAMP,
  col_json JSON,
  col_jsonb JSONB
);

-- Row 1: typical positive values across all serial types
INSERT INTO all_types VALUES (
  1,
  42, 42, 7, 1000, 100000, 9999999999999, 42, 99, 42, 42,
  'hello world', 'character val', 'varchar value', 'varying char val', 'nchar value', 'native char val', 'nvarchar value', 'clob value',
  X'DEADBEEF', '{"key":"blob_json"}', 'no type value',
  3.14, 2.71828, 1.23456789, 1.5,
  12345, 99.99, 1, '2025-06-15', '2025-06-15 10:30:00', '2025-06-15 10:30:00', '{"name":"Alice","age":30}', '{"name":"Alice"}'
);

-- Row 2: negative values, zeros, and empty strings
INSERT INTO all_types VALUES (
  2,
  -1, -1, -128, -32768, -8388608, -140737488355328, -1, -99, -42, -42,
  '', '', 'negative test', '', '', '', '', '',
  X'00', '{}', '',
  -3.14, -0.001, -1.23456789, 0.0,
  -1, -99.99, 0, '1970-01-01', '1970-01-01 00:00:00', '1970-01-01 00:00:00', '[]', '[]'
);

-- Row 3: all NULLs (serial type 0)
INSERT INTO all_types VALUES (
  3,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);

-- Row 4: integer boundary values to exercise serial types 1-6 and 8-9
INSERT INTO all_types VALUES (
  4,
  127, -128, 32767, -32768, 8388607, -8388608, 2147483647, -2147483648, 140737488355327, -140737488355328,
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
  X'FF', '{"boundary":true}', X'0102030405060708',
  1.7976931348623157E+308, -1.7976931348623157E+308, 2.2250738585072014E-308, -0.0,
  2147483647, 0.01, 1, '9999-12-31', '9999-12-31 23:59:59', '0001-01-01 00:00:00', '{"n":2147483647}', '{"n":0}'
);

-- Row 5: max 64-bit integers (serial type 6), large text, multi-byte blob
INSERT INTO all_types VALUES (
  5,
  9223372036854775807, -9223372036854775808, 0, 0, 0, 0, 1, 0, 0, 0,
  'The quick brown fox jumps over the lazy dog. This is a longer text value to test text storage.',
  'short', 'medium length string here', 'another varying', 'nchar test', 'native test', 'nvarchar test',
  'Another clob with multiple words in it.',
  X'000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F', '{"arr":[1,2,3]}', X'CAFEBABE',
  0.0, 0.0, 0.0, 0.0,
  0, 0.0, 0, '2000-01-01', '2000-06-15 12:00:00', '2000-06-15 12:00:00', '{"nested":{"a":1}}', '{"x":"y"}'
);
