USE [master]
GO

/**
 * Script: sp_BackupAllDatabases.sql
 * 
 * Purpose: Provides an easy way to perform a full backup of all databases of 
 *          the instance.
 * 
 * Parameters and flags (all parameters are optional):
 *      @_bkpPath       : The location to save the backups, with a trailing backslash.
 *                        Default value: 'C:\Temp\'
 *      @_ignoreTempDB  : Should the procedure ignore the TempDB?
 *                        Default value: 1 (true)
 *      @_bkpSystemDBs  : Should the procedure back up the system databases?
 *                        Default value: 1 (true)
 *                        Obs: This flag does not override @_ignoreTempDB.
 *      @_useCompression: Tell the procedure to use compression or not.
 *                        Default value: null (use system default)
 *      @_verbose       : Print debug messages.
 *                        Default value: 0 (false)
 */

CREATE OR ALTER PROCEDURE dbo.sp_BackupAllDatabases
    @_bkpPath AS NVARCHAR(MAX) = N'C:\Temp\'
   ,@_ignoreTempDB AS BIT = 1 
   ,@_bkpSystemDBs AS BIT = 1
   ,@_useCompression AS BIT = null
   ,@_verbose AS BIT = 0
AS BEGIN
    SET NOCOUNT ON

    -- Checks for trailing backslash on @_bkpPath
    IF @_verbose = 1 PRINT 'Checking for a backslash on @_bkpPath'
    IF RIGHT(@_bkpPath, 1) <> '\'
        IF @_verbose = 1 PRINT 'No backslash found on @_bkpPath. Adding one.'
        SET @_bkpPath = @_bkpPath + '\'

    -- Checks if @_bkpPath exists
    IF @_verbose = 1 PRINT 'Cheking if @_bkpPath exists and if it is a directory.'
    DECLARE @_bkpPathExists AS INT
    SELECT @_bkpPathExists=file_is_a_directory 
      FROM sys.dm_os_file_exists(@_bkpPath);
    IF @_bkpPathExists = 0 
    BEGIN
        PRINT 'The backup path does not exist. Create it or provide a valid one.'
        RETURN
    END
    IF @_verbose = 1 PRINT '@_bkpPath found.'

    -- If @_useCompression is not passed by the user, use the default server config
    IF @_verbose = 1 PRINT 'Checking flag @_useCompression.'
    IF @_useCompression IS NULL
        IF @_verbose = 1 PRINT '@_useCompression is NULL, using server default'
        SELECT @_useCompression=CONVERT(BIT, [value]) 
          FROM sys.configurations 
         WHERE [name] = 'backup compression default';
    
    DECLARE @__compression as NVARCHAR(20)
    IF @_useCompression = 1
    BEGIN
        IF @_verbose = 1 PRINT 'Backup set to use compression'
        SET @__compression = ', COMPRESSION'
    END
    IF @_useCompression = 0
    BEGIN
         IF @_verbose = 1 PRINT 'Backup set to not use compression'
        SET @__compression = ', NO_COMPRESSION'
    END

    -- Creates temp table to store information about the databases and backups
    IF @_verbose = 1 PRINT 'Creating temp table #_databases'
    DROP TABLE IF EXISTS #_databases
    SELECT [name], 0 AS bkpd INTO #_databases FROM sys.databases

    IF @_verbose = 1 PRINT 'Checking value of @_ignoreTempDB'
    IF @_ignoreTempDB = 1
        IF @_verbose = 1 PRINT '@_ignoreTempDB = 1, removing tempDB from #_databases'
        DELETE #_databases WHERE [name] = 'TempDB'

    IF @_verbose = 1 PRINT 'Checking value of  @_bkpSystemDBs'
    IF @_bkpSystemDBs = 0
        IF @_verbose = 1 PRINT '@_bkpSystemDBs = 0. Removing master, model and msdb from #_databases'
        DELETE #_databases WHERE [name] in ('master','model','msdb')

    -- Start backing up the databases
    IF @_verbose = 1 PRINT 'Starting the backup'
    DECLARE @_remaining AS INT
    SELECT @_remaining=count(*) FROM #_databases WHERE bkpd = 0

    IF @_verbose = 1 PRINT 'Backing up ' + CONVERT(VARCHAR, @_remaining) + ' databases'
    WHILE @_remaining > 0
    BEGIN
        DECLARE @_db NVARCHAR(MAX)
        SELECT TOP 1 @_db = [name] FROM #_databases WHERE bkpd = 0
        
        IF @_verbose = 1 PRINT 'Backing up: ' + @_db
        
        DECLARE @_bkpFileName AS NVARCHAR(MAX)
        SET @_bkpFileName = @_bkpPath + @_db + '_full_' 
                + replace(convert(varchar, GETDATE(), 126), ':', '') + '.bak'
        IF @_verbose = 1 PRINT 'Backup filename: ' + @_bkpFileName
        
        DECLARE @_sql AS NVARCHAR(MAX)
        SET @_sql = 'BACKUP DATABASE ' + @_db + ' TO DISK=''' + @_bkpFileName 
                + ''' WITH CHECKSUM' + @__compression  
        
        IF @_verbose = 1 PRINT 'Executing: ' + @_sql
        EXEC sp_executesql @_sql

        IF @_verbose = 1 PRINT 'Updating #_databases'
        UPDATE #_databases SET bkpd = 1 WHERE [name] = @_db
        
        SELECT @_remaining=count(*) FROM #_databases WHERE bkpd = 0
        IF @_verbose = 1 PRINT 'Remaining ' + CONVERT(VARCHAR, @_remaining) + ' databases'
    END
    IF @_verbose = 1 PRINT 'Exiting...'
END