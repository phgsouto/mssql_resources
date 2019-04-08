USE [master]
GO

/**
 * Script: sp_BackupAllDatabases.sql
 * 
 * Purpose: Provides an easy way to perform a full backup of all databases of 
 *          the instance.
 * 
 * Parameters and flags (all parameters are optional):
 *      @_bkpPath: The location to save the backups, with a trailing backslash.
 *                 Default value: 'C:\Temp\'
 *      @_ignoreTempDB  : Should the procedure ignore the TempDB?
 *                        Default value: 1 (true)
 *      @_bkpSystemDBs  : Should the procedure back up the system databases?
 *                        Default value: 1 (true)
 *                        Obs: This flag does not override @_ignoreTempDB.
 *      @_useCompression: Tell the procedure to use compression or not.
 *                        Default value: null (use system default)
 */

CREATE OR ALTER PROCEDURE dbo.sp_BackupAllDatabases
    @_bkpPath AS NVARCHAR(MAX) = N'C:\Temp\'
   ,@_ignoreTempDB AS BIT = 1 
   ,@_bkpSystemDBs AS BIT = 1
   ,@_useCompression AS BIT = null
AS BEGIN
    SET NOCOUNT ON

    -- Checks for trailing baskslash on @_bkpPath
    IF RIGHT(@_bkpPath, 1) <> '\'
        SET @_bkpPath = @_bkpPath + '\'

    -- Checks if @_bkpPath exists
    DECLARE @_bkpPathExists AS INT
    SELECT @_bkpPathExists=file_is_a_directory 
      FROM sys.dm_os_file_exists(@_bkpPath);
    IF @_bkpPathExists = 0 
    BEGIN
        PRINT 'The backup path does not exist. Create it or provide a valid one.'
        RETURN
    END

    -- If @_useCompression is not passed by the user, use the default server config
    IF @_useCompression IS NULL
        SELECT @_useCompression=CONVERT(BIT, [value]) 
          FROM sys.configurations 
         WHERE [name] = 'backup compression default';

    -- Creates temp table to store information about the databases and backups
    DROP TABLE IF EXISTS #_databases

    SELECT [name], 0 AS bkpd INTO #_databases FROM sys.databases

    IF @_ignoreTempDB = 1
        DELETE #_databases WHERE [name] = 'TempDB'

    IF @_bkpSystemDBs = 0
        DELETE #_databases WHERE [name] in ('master','model','msdb')

    -- Start backing up the databases
    DECLARE @_remaining AS INT
    SELECT @_remaining=count(*) FROM #_databases WHERE bkpd = 0
    WHILE @_remaining > 0
    BEGIN
        DECLARE @_db NVARCHAR(MAX)
        SELECT TOP 1 @_db = [name] FROM #_databases WHERE bkpd = 0
        DECLARE @_bkpFileName AS NVARCHAR(MAX)
        SET @_bkpFileName = @_bkpPath + @_db + '_full_' 
                + replace(convert(varchar, GETDATE(), 126), ':', '') + '.bak'
        
        DECLARE @_sql AS NVARCHAR(MAX)
        SET @_sql = 'BACKUP DATABASE ' + @_db + ' TO DISK=''' + @_bkpFileName 
                + ''' WITH CHECKSUM'

        IF @_useCompression = 1
            SET @_sql = @_sql + ', COMPRESSION'
        ELSE
            SET @_sql = @_sql + ', NO_COMPRESSION'
        
        EXEC sp_executesql @_sql

        UPDATE #_databases SET bkpd = 1 WHERE [name] = @_db
        SELECT @_remaining=count(*) FROM #_databases WHERE bkpd = 0
    END

END