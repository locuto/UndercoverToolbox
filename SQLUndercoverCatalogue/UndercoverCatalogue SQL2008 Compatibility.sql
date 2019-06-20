--SQL Undercover Catalogue - 2008 Compatibility 
--Tested with 2008R2 & 2008


USE [SQLUndercover]
GO


ALTER PROC [Catalogue].[GetAvailabilityGroups]
AS
BEGIN

--Get availability group details
SELECT	NULL AS AGName,
		NULL AS ServerName,
		NULL AS Role,
		NULL AS BackupPreference,
		NULL AS AvailabilityMode,
		NULL AS FailoverMode,
		NULL AS ConnectionsToSecondary
WHERE 1 = 2

END
GO


ALTER PROC [Catalogue].[GetDatabases]
AS

BEGIN
--get all databases on server

SELECT	@@SERVERNAME AS ServerName,
		databases.name AS DBName,
		databases.database_id AS DatabaseID,
		server_principals.name AS OwnerName,
		databases.compatibility_level AS CompatibilityLevel,
		databases.collation_name AS CollationName,
		databases.recovery_model_desc AS RecoveryModelDesc,
		NULL AS AGName,
		files.FilePaths,
		files.DatabaseSizeMB
FROM sys.databases
LEFT OUTER JOIN sys.server_principals ON server_principals.sid = databases.owner_sid
--LEFT OUTER JOIN sys.availability_replicas ON availability_replicas.replica_id = databases.replica_id
--LEFT OUTER JOIN sys.availability_groups ON availability_groups.group_id = availability_replicas.group_id
JOIN	(SELECT database_id, (SUM(CAST (size AS BIGINT)) * 8)/1024 AS DatabaseSizeMB,STUFF((SELECT ', ' + files2.physical_name
				FROM sys.master_files files2
				WHERE files2.database_id = files1.database_id
				FOR XML PATH('')
			), 1, 2, '') AS FilePaths
		FROM sys.master_files files1
		GROUP BY database_id) files ON files.database_id = databases.database_id
END


