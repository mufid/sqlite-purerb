-- 002-queries-order-by-limit-offset.sql
-- Tests ORDER BY, LIMIT, and LIMIT N OFFSET M queries.

CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  name TEXT,
  price REAL,
  category TEXT,
  stock INTEGER
);

INSERT INTO products VALUES (1, 'Apple', 1.50, 'fruit', 100);
INSERT INTO products VALUES (2, 'Banana', 0.75, 'fruit', 200);
INSERT INTO products VALUES (3, 'Carrot', 2.00, 'vegetable', 150);
INSERT INTO products VALUES (4, 'Date', 5.99, 'fruit', 50);
INSERT INTO products VALUES (5, 'Eggplant', 3.25, 'vegetable', 75);
INSERT INTO products VALUES (6, 'Fig', 4.50, 'fruit', 30);
INSERT INTO products VALUES (7, 'Garlic', 1.99, 'vegetable', 300);
INSERT INTO products VALUES (8, 'Honeydew', 6.00, 'fruit', 20);
