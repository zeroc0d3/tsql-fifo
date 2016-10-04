-- =====================================================          
-- Listing 1: Create Table,
--            Insert Data, 
--            Index Table    
-- 
-- References :
-- https://www.simple-talk.com/sql/performance/t-sql-window-function-speed-phreakery-the-fifo-stock-inventory-problem/
-- 
-- Link :
-- http://sqlfiddle.com/#!6/05e3d/1
-- =====================================================      

-- =====================================================          
-- Step 1: Create Table Stock
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

-- =====================================================          
-- Step 2: Insert Sample Data
-- =====================================================      
INSERT INTO dbo.Stock SELECT 'PO-001', 'A021', '20120101','IN', 3, 100
INSERT INTO dbo.Stock SELECT 'SO-010', 'A021', '20120102', 'OUT', 2, 50
INSERT INTO dbo.Stock SELECT 'PO-002', 'A021', '20120110','IN', 7, 110
INSERT INTO dbo.Stock SELECT 'PO-003', 'A021', '20120201','IN', 9, 110
INSERT INTO dbo.Stock SELECT 'SO-011', 'A021', '20120211', 'OUT', 8, 80
INSERT INTO dbo.Stock SELECT 'SO-012', 'A023', '20120212', 'OUT', 6, 200

-- =====================================================          
-- Step 3: Create Index "IN"
-- =====================================================      
CREATE NONCLUSTERED INDEX IX_Input
ON dbo.Stock (TranCode, ItemID)
INCLUDE (TranDate, Qty) 
WHERE TranCode IN ('IN', 'RET')
 
-- =====================================================          
-- Step 4: Create Index "OUT"
-- =====================================================      
CREATE NONCLUSTERED INDEX IX_Output ON dbo.Stock (TranCode, ItemID)
INCLUDE (TranDate, Qty)
WHERE TranCode = 'OUT'
 
-- =====================================================          
-- Step 5: Select Maximum Rows In One Process Queque
-- =====================================================      
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

-- =====================================================          
-- Step 6: Create Temporary Index
-- =====================================================      
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

-- =====================================================          
-- Step 7: Create Temporary Index Quantity
-- =====================================================      
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

-- =====================================================          
-- Step 8: Create Temporary Index Price
-- =====================================================      
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

-- =====================================================          
-- Step 9: FIFO Dave Ballantyne’s Solution
-- =====================================================      
;
/* Sum up the ins and outs to calculate the remaining stock level */
WITH    
cteStockSum
  AS ( SELECT 
          ItemID ,
          SUM(CASE WHEN TranCode = 'OUT' THEN 0 - Qty
              ELSE Qty
              END) AS TotalStock
       FROM     dbo.Stock
       GROUP BY ItemID
     ),
cteReverseInSum
  AS ( SELECT  
          s.ItemID ,
          s.TranDate ,
          ( SELECT  SUM(i.Qty)
            FROM    dbo.Stock AS i WITH ( INDEX ( IX_Temp_Qty ) )
            WHERE   i.ItemID = s.ItemID
                    AND i.TranCode IN ( 'IN', 'RET' )
                    AND i.TranDate >= s.TranDate
          ) AS RollingStock ,
               s.Qty AS ThisStock
       FROM    dbo.Stock AS s
       WHERE   s.TranCode IN ( 'IN', 'RET' )
     ), 
     
/* Using the rolling balance above find the first stock movement in that meets 
   (or exceeds) our required stock level */
/* and calculate how much stock is required from the earliest stock in */
cteWithLastTranDate
  AS  ( SELECT  w.ItemID ,
                w.TotalStock ,
                LastPartialStock.TranDate ,
                LastPartialStock.StockToUse ,
                LastPartialStock.RunningTotal ,
                w.TotalStock - LastPartialStock.RunningTotal
                + LastPartialStock.StockToUse AS UseThisStock
        FROM    cteStockSum AS w
                CROSS APPLY ( 
                  SELECT TOP ( 1 )
                        z.TranDate ,
                        z.ThisStock AS StockToUse ,
                        z.RollingStock AS RunningTotal
                  FROM  cteReverseInSum AS z
                  WHERE z.ItemID = w.ItemID
                        AND z.RollingStock >= w.TotalStock
                  ORDER BY  z.TranDate DESC
                ) AS LastPartialStock
      )
     
/*  Sum up the cost of 100% of the stock movements in after the returned stockid and for that stockid we need 'UseThisStock' items' */
SELECT  y.ItemID ,
        y.TotalStock AS CurrentQty ,
        SUM(CASE WHEN e.TranDate = y.TranDate 
            THEN y.UseThisStock
            ELSE e.Qty
            END * Price.Price) AS CurrentValue
FROM    cteWithLastTranDate AS y
        INNER JOIN dbo.Stock AS e WITH ( INDEX ( IX_Temp_Qty ) )
        ON e.ItemID = y.ItemID
          AND e.TranDate >= y.TranDate
          AND e.TranCode IN ('IN', 'RET' )
        
        CROSS APPLY ( 
          /* Find the Price of the item in */ 
            SELECT TOP ( 1 )
          	    p.Price
          	FROM dbo.Stock AS p 
          	    WITH ( INDEX ( IX_Temp_Price ) )
          	WHERE
                p.ItemID = e.ItemID
          			AND p.TranDate <= e.TranDate
          			AND p.TranCode = 'IN'
          	ORDER BY p.TranDate DESC
        ) AS Price

GROUP BY y.ItemID ,y.TotalStock
ORDER BY y.ItemID   

