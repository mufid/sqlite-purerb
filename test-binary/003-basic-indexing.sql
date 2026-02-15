-- 003-basic-indexing.sql
-- Tests basic index usage for WHERE clause equality lookups.
--
-- Creates a table with an index, then queries using the indexed column.
-- SQLite's query planner should choose the index for equality WHERE clauses,
-- producing SeekGE/IdxGT/DeferredSeek opcodes instead of a full table scan.

CREATE TABLE employees (
  id INTEGER PRIMARY KEY,
  name TEXT,
  department TEXT,
  salary INTEGER
);

CREATE INDEX idx_employees_department ON employees (department);

INSERT INTO employees VALUES (1, 'Alice', 'engineering', 90000);
INSERT INTO employees VALUES (2, 'Bob', 'sales', 70000);
INSERT INTO employees VALUES (3, 'Charlie', 'engineering', 95000);
INSERT INTO employees VALUES (4, 'Diana', 'marketing', 80000);
INSERT INTO employees VALUES (5, 'Eve', 'sales', 72000);
INSERT INTO employees VALUES (6, 'Frank', 'engineering', 88000);
INSERT INTO employees VALUES (7, 'Grace', 'marketing', 85000);
INSERT INTO employees VALUES (8, 'Hank', 'sales', 68000);
