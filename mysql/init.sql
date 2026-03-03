CREATE TABLE orders (
  id INT PRIMARY KEY AUTO_INCREMENT,
  created_at DATE NOT NULL,
  customer VARCHAR(50),
  amount DECIMAL(10,2)
);

INSERT INTO orders (created_at, customer, amount) VALUES
('2026-01-01', 'alice', 100.00),
('2025-07-01', 'bob', 200.00);
