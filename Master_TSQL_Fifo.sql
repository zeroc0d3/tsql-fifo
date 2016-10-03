-- Articles => http://www.kodyaz.com/t-sql/fifo-example-query-in-sql-server.aspx
-- link     => http://sqlfiddle.com/#!6/7b7f6/1
-- DROP TABLE SalesOrder
-- DROP TABLE ProductionOrder

CREATE TABLE SalesOrder (
  OrderId varchar(10), 
  OrderDate datetime, 
  ProductId varchar(10), 
  OrderQty int
);
GO

CREATE TABLE ProductionOrder (
  OrderId varchar(10), 
  OrderDate datetime, 
  ProductId varchar(10), 
  OrderQty int
);
GO

INSERT INTO SalesOrder
  SELECT 'SO-0001', '20120105 13:45', 'PROD-01', 50
INSERT INTO SalesOrder
  SELECT 'SO-0002', '20120108 12:00', 'PROD-02', 40
INSERT INTO SalesOrder
  SELECT 'SO-0003', '20120109 10:30', 'PROD-01', 20
INSERT INTO SalesOrder
  SELECT 'SO-0004', '20120110 17:10', 'PROD-03', 30
INSERT INTO ProductionOrder
  SELECT 'PO-0001', '20120115 15:00', 'PROD-01', 30
INSERT INTO ProductionOrder
  SELECT 'PO-0002', '20120115 18:00', 'PROD-02', 20
INSERT INTO ProductionOrder
  SELECT 'PO-0003', '20120116 18:00', 'PROD-01', 30

SELECT * FROM SalesOrder --order by ProductId
SELECT * FROM ProductionOrder --order by ProductId

---
;
WITH s AS
  (SELECT *, 
    SoldUpToNow =
      (SELECT sum(OrderQty)
        FROM SalesOrder
        WHERE ProductId = s.ProductId
                AND OrderDate <= s.OrderDate)
    FROM SalesOrder s),
      p AS
  (SELECT ProductId,
    sum(OrderQty) AS TotalProduced
    FROM ProductionOrder
    GROUP BY ProductId)

SELECT *
FROM
  (SELECT s.*,
      p.TotalProduced,
      CASE
        WHEN s.SoldUpToNow - isnull(p.TotalProduced,0) < 0 THEN 0
        WHEN (s.SoldUpToNow - isnull(p.TotalProduced,0)) > s.OrderQty THEN s.OrderQty
        ELSE s.SoldUpToNow - isnull(p.TotalProduced,0)
      END AS LeftQty
    FROM s
    LEFT JOIN p ON s.ProductId = p.ProductId) fifo
WHERE LeftQty > 0