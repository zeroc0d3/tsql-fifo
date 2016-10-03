-- Articles => http://www.kodyaz.com/articles/sql-tutorial-map-payments-to-expenses-using-t-sql-query.aspx
-- link     => http://sqlfiddle.com/#!6/e0930/1
-- DROP TABLE PrePayments
-- DROP TABLE Expenses

CREATE TABLE PrePayments (
  PaymentId int, 
  PayerId int, 
  PaymentAmount int, 
  PaymentDate datetime
);
GO

CREATE TABLE Expenses (
  ExpenseId int, 
  ExpensedById int, 
  ExpenseAmount int, 
  ExpenseDate datetime
);
GO

INSERT INTO PrePayments
  SELECT 1, 1, 100, '20100101'
INSERT INTO PrePayments
  SELECT 2, 1, 200, '20100201'
INSERT INTO Expenses
  SELECT 1, 1, 30, '20100301'
INSERT INTO Expenses
  SELECT 2, 1, 20, '20100302'
INSERT INTO Expenses
  SELECT 3, 1, 30, '20100303'
INSERT INTO Expenses
  SELECT 4, 1, 30, '20100304'
INSERT INTO Expenses
  SELECT 5, 1, 20, '20100305'
INSERT INTO Expenses
  SELECT 6, 1, 40, '20100306'
INSERT INTO Expenses
  SELECT 7, 1, 20, '20100307'
INSERT INTO Expenses
  SELECT 8, 1, 30, '20100308'
INSERT INTO Expenses
  SELECT 9, 1, 20, '20100309'
INSERT INTO Expenses
  SELECT 10, 1, 20, '20100310'
INSERT INTO Expenses
  SELECT 11, 1, 20, '20100311'
INSERT INTO Expenses
  SELECT 12, 1, 40, '20100312' 
GO 

----
;
WITH cte AS
  (SELECT p.PaymentId,
                  p.PaymentAmount,
                  total_payments = SUM(pp.PaymentAmount),
                                                    p.PaymentDate
    FROM PrePayments p
    INNER JOIN PrePayments pp ON p.PayerId = pp.PayerId
    AND p.PaymentDate >= pp.PaymentDate
    WHERE p.PayerId = 1
    GROUP BY p.PaymentId,
                      p.PaymentAmount,
                      p.PaymentDate)
SELECT y.ExpensedById,
    y.ExpenseId,
    y.ExpenseDate,
    y.ExpenseAmount,
    cte.PaymentId,
    cte.PaymentAmount,
    cte.PaymentDate PrePayments_date,
    total_expenses,
    total_payments,
    total_difference = (total_payments - total_expenses)
FROM
    (SELECT *,
      PaymentId =
      (SELECT MIN(PaymentId)
        FROM cte
        WHERE total_expenses <= total_payments)
        FROM
          (SELECT e.ExpensedById,
                  e.ExpenseId,
                  e.ExpenseAmount,
                  total_expenses = SUM(ee.ExpenseAmount),
                  e.ExpenseDate ExpenseDate
            FROM Expenses e
            INNER JOIN Expenses ee ON e.ExpensedById = ee.ExpensedById
            AND e.ExpenseDate >= ee.ExpenseDate
                WHERE e.ExpensedById = 1
                GROUP BY e.ExpensedById,
                         e.ExpenseId,
                         e.ExpenseAmount,
                         e.ExpenseDate) x) y
LEFT JOIN cte ON cte.PaymentId = y.PaymentId