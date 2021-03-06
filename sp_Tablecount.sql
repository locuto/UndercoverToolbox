USE [master]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('sp_Tablecount') IS NULL 
BEGIN 
	EXEC('CREATE PROCEDURE sp_Tablecount AS');
END
GO

/*********************************************
Procedure Name: sp_Tablecount
Author: Adrian Buckman
Revision date: 06/11/2019
Version: 2

© www.sqlundercover.com 

MIT License
------------
 
Copyright 2019 Sql Undercover
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

*********************************************/

ALTER PROCEDURE [dbo].[sp_Tablecount] (
@Databasename NVARCHAR(128) = NULL,
@Schemaname NVARCHAR(128) = NULL,
@Tablename NVARCHAR(128) = NULL,
@Sortorder NVARCHAR(30) = NULL, --VALID OPTIONS 'Schema' 'Table' 'Rows' 'Delta' 'Size'
@Top INT = NULL,
@Interval TINYINT = NULL,
@Getsizes BIT = 0
)
AS
BEGIN 

SET NOCOUNT ON;

DECLARE @Sql NVARCHAR(4000);
DECLARE @Delay VARCHAR(8);


IF OBJECT_ID('tempdb.dbo.#RowCounts') IS NOT NULL 
DROP TABLE [#RowCounts]

CREATE TABLE [#RowCounts] (
Schemaname NVARCHAR(128),
Tablename NVARCHAR(128),
TotalRows BIGINT,
SizeMB MONEY,
StorageInfo	XML,
IndexTypes VARCHAR(256)
);


--Show debug info:
PRINT 'Parameter values:'
PRINT '@Databasename: '+ISNULL(@Databasename,'NULL');
PRINT '@Schemaname: '+ISNULL(@Schemaname,'NULL');
PRINT '@Tablename: '+ISNULL(@Tablename,'NULL') 
PRINT '@Sortorder: '+ISNULL(@Sortorder,'NULL'); 
PRINT '@Top: '+ISNULL(CAST(@Top AS VARCHAR(20)),'NULL');
PRINT '@Interval '+ISNULL(CAST(@Interval AS VARCHAR(3)),'NULL');
PRINT '@Getsizes '+ISNULL(CAST(@Getsizes AS CHAR(1)),'NULL');

IF @Databasename IS NULL 
BEGIN 
	SET @Databasename = DB_NAME();
END 

--Ensure database exists.
IF DB_ID(@Databasename) IS NULL 
BEGIN 
	RAISERROR('Invalid databasename',11,0);
	RETURN;
END 

--Delta maximum is 60 seconds 
IF (@Interval > 60) 
BEGIN 
	SET @Interval = 60;
	PRINT '@Interval was changed to the maximum value of 60 seconds';
END 

--Set delay for WAITFOR
IF (@Interval IS NOT NULL AND @Interval > 0)
BEGIN 	
	SET @Delay = CASE 
					WHEN @Interval = 60 THEN '00:01:00'
					WHEN @Interval < 10 THEN '00:00:0'+CAST(@Interval AS VARCHAR(2)) 
					ELSE '00:00:'+CAST(@Interval AS VARCHAR(2)) 
				END;
END 

--UPPER @Sortorder
IF @Sortorder IS NOT NULL 
BEGIN 
	SET @Sortorder = UPPER(@Sortorder);
	
	IF @Sortorder NOT IN ('SCHEMA','TABLE','ROWS','DELTA','SIZE')
	BEGIN 
		RAISERROR('Valid options for @Sortorder are ''Schema'' ''Table'' ''Rows'' ''Delta'' ''Size''',11,0);
		RETURN;
	END 

	IF (@Sortorder = 'DELTA' AND (@Interval IS NULL OR @Interval = 0))
	BEGIN 
		RAISERROR('@Sortorder = Delta is invalid with @Interval is null or zero',11,0);
		RETURN;	
	END

	IF (@Getsizes = 0 AND @Sortorder = 'SIZE') 
	BEGIN 
		PRINT '@Sortorder = ''Size'' is not compatible with @Getsizes = 0, using default sortorder';
	END 
END

SET @Sql = N'
SELECT'
+CASE 
	WHEN @Top IS NOT NULL THEN ' TOP ('+CAST(@Top AS VARCHAR(20))+')'
	ELSE ''
END
+'
schemas.name AS Schemaname,
tables.name AS Tablename,
partitions.rows AS TotalRows,
'+
CASE 
	WHEN @Getsizes = 1 THEN 'ISNULL((SELECT SUM((CAST(total_pages AS MONEY)*8)/1024)
FROM ['+@Databasename+'].sys.allocation_units Allocunits 
WHERE partitions.partition_id = Allocunits.container_id ),0.00) AS SizeMB,'
ELSE ''
END 
+'CAST(Allocunits.PageInfo AS XML) AS StorageInfo,
ISNULL((SELECT type_desc + '': ''+CAST(COUNT(*) AS VARCHAR(6))+ ''  '' 
	FROM ['+@Databasename+'].sys.indexes 
	WHERE object_id = tables.object_id AND indexes.type > 0 
	GROUP BY type_desc 
	ORDER BY type_desc 
	FOR XML PATH('''')),''HEAP'') AS IndexTypes
FROM ['+@Databasename+'].sys.tables
INNER JOIN ['+@Databasename+'].sys.schemas ON tables.schema_id = schemas.schema_id
INNER JOIN ['+@Databasename+'].sys.partitions ON tables.object_id = partitions.object_id
CROSS APPLY (SELECT type_desc 
			+ N'': Total pages: ''
			+CAST(total_pages AS NVARCHAR(10))
			+ '' ''
			+CHAR(13)+CHAR(10)
			+N'' Used pages: ''
			+CAST(used_pages AS NVARCHAR(10))
			+ '' ''
			+CHAR(13)+CHAR(10)
			+N'' Total Size: ''
			+CAST((total_pages*8)/1024 AS NVARCHAR(10))
			+N''MB''
			+N'' ''
			FROM ['+@Databasename+'].sys.allocation_units Allocunits 
			WHERE partitions.partition_id = Allocunits.container_id 
			ORDER BY type_desc ASC
			FOR XML PATH('''')) Allocunits (PageInfo)
WHERE index_id IN (0,1)'
+
CASE 
	WHEN @Tablename IS NULL THEN '' 
	ELSE '
AND tables.name = @Tablename'
END
+
CASE 
	WHEN @Schemaname IS NULL THEN '' 
	ELSE '
AND schemas.name = @Schemaname'
END+'
ORDER BY '
+CASE 
	WHEN @Sortorder = 'SCHEMA' THEN 'schemas.name ASC,tables.name ASC;'
	WHEN @Sortorder = 'TABLE' THEN 'tables.name ASC;'
	WHEN @Sortorder = 'ROWS' THEN 'partitions.rows DESC'
	WHEN @Getsizes = 1 AND @Sortorder = 'SIZE' THEN 'SizeMB DESC'
	ELSE 'schemas.name ASC,tables.name ASC;' 
END

PRINT '
Dynamic SQL:';
PRINT @Sql;

IF (@Interval IS NULL OR @Interval = 0)
BEGIN 
	EXEC sp_executesql @Sql,
	N'@Tablename NVARCHAR(128), @Schemaname NVARCHAR(128)',
	@Tablename = @Tablename, @Schemaname = @Schemaname;
END
ELSE 
BEGIN 
	IF @Getsizes = 0 
	BEGIN 
		INSERT INTO #RowCounts (Schemaname,Tablename,TotalRows,StorageInfo,IndexTypes)
		EXEC sp_executesql @Sql,
		N'@Tablename NVARCHAR(128), @Schemaname NVARCHAR(128)',
		@Tablename = @Tablename, @Schemaname = @Schemaname;
	END 

	IF @Getsizes = 1
	BEGIN 
		INSERT INTO #RowCounts (Schemaname,Tablename,TotalRows,SizeMB,StorageInfo,IndexTypes)
		EXEC sp_executesql @Sql,
		N'@Tablename NVARCHAR(128), @Schemaname NVARCHAR(128)',
		@Tablename = @Tablename, @Schemaname = @Schemaname;
	END

	WAITFOR DELAY @Delay;

SET @Sql = N'
SELECT'
+CASE 
	WHEN @Top IS NOT NULL THEN ' TOP ('+CAST(@Top AS VARCHAR(20))+')'
	ELSE ''
END
+'
schemas.name AS Schemaname,
tables.name AS Tablename,
#RowCounts.TotalRows AS TotalRows,
partitions.rows-#RowCounts.TotalRows AS TotalRows_Delta,
'+
CASE 
	WHEN @Getsizes = 1 THEN '#RowCounts.SizeMB,
INULL((SELECT SUM((CAST(total_pages AS MONEY)*8)/1024)
FROM ['+@Databasename+'].sys.allocation_units Allocunits 
WHERE partitions.partition_id = Allocunits.container_id ),0.00)-#RowCounts.SizeMB AS SizeMB_Delta,'
ELSE ''
END 
+'
#RowCounts.StorageInfo,
#RowCounts.IndexTypes
FROM ['+@Databasename+'].sys.tables
INNER JOIN ['+@Databasename+'].sys.schemas ON tables.schema_id = schemas.schema_id
INNER JOIN ['+@Databasename+'].sys.partitions ON tables.object_id = partitions.object_id
INNER JOIN #RowCounts ON tables.name = #RowCounts.Tablename COLLATE DATABASE_DEFAULT AND schemas.name = #RowCounts.Schemaname COLLATE DATABASE_DEFAULT
WHERE index_id IN (0,1)'
+
CASE 
	WHEN @Tablename IS NULL THEN '' 
	ELSE '
AND tables.name = @Tablename'
END
+
CASE 
	WHEN @Schemaname IS NULL THEN '' 
	ELSE '
AND schemas.name = @Schemaname'
END+'
ORDER BY '
+CASE 
	WHEN @Sortorder = 'SCHEMA' THEN 'schemas.name ASC,tables.name ASC;'
	WHEN @Sortorder = 'TABLE' THEN 'tables.name ASC;'
	WHEN @Sortorder = 'ROWS' THEN 'partitions.rows DESC'
	WHEN @Sortorder ='DELTA' THEN 'ABS(partitions.rows-#RowCounts.TotalRows) DESC'
	WHEN @Getsizes = 1 AND @Sortorder = 'SIZE' THEN 'SizeMB DESC'
	ELSE 'schemas.name ASC,tables.name ASC;' 
END


	EXEC sp_executesql @Sql,
	N'@Tablename NVARCHAR(128), @Schemaname NVARCHAR(128)',
	@Tablename = @Tablename, @Schemaname = @Schemaname;

END 

END