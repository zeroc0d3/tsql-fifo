-- =====================================================          
-- Listing 1: Create Table,
--            Insert Data, 
--            Index Table    
-- 
-- References :
-- https://www.simple-talk.com/sql/performance/t-sql-window-function-speed-phreakery-the-fifo-stock-inventory-problem/
-- 
-- Link :
-- http://sqlfiddle.com/#!6/1d729/5
-- =====================================================      
CREATE TABLE dbo.Stock (
  StockID INT IDENTITY(1, 1)
      NOT NULL ,
  DocumentID VARCHAR(10) NOT NULL ,
  ItemID VARCHAR(10) NOT NULL ,
  TranDate DATETIME NOT NULL ,
  TranCode VARCHAR(3) NOT NULL ,
  Qty INT NOT NULL ,
  Price MONEY NULL ,
  CONSTRAINT [PK_dbo.Stock] PRIMARY KEY CLUSTERED ( StockID ASC )
);
GO

INSERT INTO dbo.Stock SELECT 'PO-001', 'A021', '20120101','IN', 3, 100
INSERT INTO dbo.Stock SELECT 'SO-010', 'A021', '20120102', 'OUT', 2, 50
INSERT INTO dbo.Stock SELECT 'PO-002', 'A021', '20120110','IN', 7, 110
INSERT INTO dbo.Stock SELECT 'PO-003', 'A021', '20120201','IN', 9, 110
INSERT INTO dbo.Stock SELECT 'SO-011', 'A021', '20120211', 'OUT', 8, 80
INSERT INTO dbo.Stock SELECT 'SO-012', 'A023', '20120212', 'OUT', 6, 200

CREATE NONCLUSTERED INDEX IX_Input
ON dbo.Stock (TranCode, ItemID)
INCLUDE (TranDate, Qty) 
WHERE TranCode IN ('IN', 'RET')
 
CREATE NONCLUSTERED INDEX IX_Output ON dbo.Stock (TranCode, ItemID)
INCLUDE (TranDate, Qty)
WHERE TranCode = 'OUT'
 
IF OBJECT_ID('dbo.TallyNumbers') IS NULL 
BEGIN
    CREATE TABLE dbo.TallyNumbers ( Number INT NOT NULL )
    INSERT  INTO dbo.TallyNumbers
     ( Number
    )
    SELECT TOP ( 1000000 )
      ROW_NUMBER() OVER ( ORDER BY A.OBJECT_ID ) - 1 AS Number
    FROM 
      master.sys.objects AS A
      CROSS JOIN master.sys.objects AS B
      CROSS JOIN master.sys.objects AS C
      CROSS JOIN master.sys.objects AS D 
END;
GO

CREATE NONCLUSTERED INDEX [IX_Temp_General]
ON [dbo].[Stock]
(
	[ItemID] ASC, 
	[TranDate] DESC, 
	[TranCode] ASC
)    
INCLUDE ([Qty], [Price]) 
WITH 
(
  PAD_INDEX  = OFF,
  STATISTICS_NORECOMPUTE  = OFF,
  SORT_IN_TEMPDB = OFF,
  IGNORE_DUP_KEY = OFF,
  DROP_EXISTING = OFF,
  ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, 
  ALLOW_PAGE_LOCKS  = ON
)
ON [PRIMARY];   
GO

CREATE NONCLUSTERED INDEX [IX_Temp_Qty]
ON [dbo].[Stock]
(            
  [ItemID] ASC,
  [TranDate] ASC
)
INCLUDE ([Qty])    
WHERE ([TranCode] IN ('IN', 'RET'))   
WITH 
(
  PAD_INDEX               = OFF,
  STATISTICS_NORECOMPUTE  = OFF, 
  SORT_IN_TEMPDB          = OFF,
  IGNORE_DUP_KEY          = OFF, 
  DROP_EXISTING           = OFF,
  ONLINE                  = OFF,
  ALLOW_ROW_LOCKS         = ON, 
  ALLOW_PAGE_LOCKS        = ON
)
ON [PRIMARY];  
GO

CREATE NONCLUSTERED INDEX [IX_Temp_Price]
ON [dbo].[Stock]
(            
	[ItemID] ASC, 
	[TranDate] ASC
)    
INCLUDE ([Price])    
WHERE ([TranCode] = 'IN')    
WITH 
(
  PAD_INDEX               = OFF,
  STATISTICS_NORECOMPUTE  = OFF,
  SORT_IN_TEMPDB          = OFF, 
  IGNORE_DUP_KEY          = OFF, 
  DROP_EXISTING           = OFF,
  ONLINE                  = OFF, 
  ALLOW_ROW_LOCKS         = ON,
  ALLOW_PAGE_LOCKS        = ON, 
  FILLFACTOR              = 100
) 
ON [PRIMARY]; 
GO

-- ------------------------------------------------------------------------
;
WITH  
  ItemEndTotal
    AS (
        SELECT  
          DocumentID ,
          SUM(CASE WHEN TranCode ='OUT' 
              THEN -Qty
              ELSE Qty
              END) AS FinalCount
        FROM dbo.Stock
        GROUP BY DocumentID
      ),
      
  ReverseRunningTotal
    AS (
        SELECT  
          StockID ,
          DocumentID ,
          TranCode ,
          TranDate ,
          Qty ,
          Price ,
          SUM(Qty) OVER (PARTITION BY DocumentID 
              ORDER BY TranDate
              ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) ReverseTotal
        FROM  dbo.Stock
        WHERE TranCode IN( 'IN','RET' )
        ),
           
  FindDate
    AS (
        SELECT DISTINCT
          T.DocumentID,
          FinalCount ,
          LAST_VALUE(TranDate) OVER (PARTITION BY P.DocumentID 
              ORDER BY TranDate
              ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS TheDate
    FROM ItemEndTotal AS T
    JOIN ReverseRunningTotal AS P
      ON T.DocumentID = P.DocumentID
      AND P.ReverseTotal >= T.FinalCount
    )
    
    SELECT RRT.DocumentID,
      FinalCount ,
      SUM(CASE WHEN TheDate = TranDate
          THEN FinalCount - (ReverseTotal - Qty)
          ELSE Qty
          END * PurchasePrice) AS Value
    FROM ReverseRunningTotal RRT
    JOIN FindDate
      ON RRT.DocumentID= FindDate.DocumentID
      CROSS APPLY (
        SELECT TOP(1)
          Price AS PurchasePrice
        FROM  ReverseRunningTotal AS R
        WHERE RRT.DocumentID = R.DocumentID
          AND TranCode = 'IN'
          AND R.TranDate <= RRT.TranDate
        ORDER BY TranDate DESC
      ) AS P
    WHERE  RRT.TranDate >= TheDate
    GROUP BY RRT.DocumentID , FinalCount
    ORDER BY RRT.DocumentID;
