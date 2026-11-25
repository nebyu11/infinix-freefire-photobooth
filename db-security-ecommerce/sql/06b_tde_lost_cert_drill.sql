/* ===========================================================================
   06b_tde_lost_cert_drill.sql  -  "What if the TDE certificate is lost?"
   ---------------------------------------------------------------------------
   Run as : administrator, AFTER 06_tde.sql. Takes about 10-30 seconds.
   Needs  : sqlcmd variable CERT_BACKUP_PASSWORD

   A disaster-recovery DRILL on ONE server. We simulate moving the encrypted
   backup to a server that does NOT have the certificate:

     1. Take an encrypted backup of ShopDB.
     2. Temporarily turn TDE off on the live ShopDB and remove the
        certificate from the server  (= "new server / certificate lost").
     3. Try to RESTORE the encrypted backup  -> FAILS (error 33111).
     4. Re-create the certificate from the .cer + .pvk backup files.
     5. RESTORE again                         -> WORKS, data is intact.
     6. Clean up and switch TDE back on for ShopDB.

   LESSON: the encrypted backup is useless without the certificate + private
   key + its password. Lose them and the data is gone forever, even for you.
   Keep them in a safe place, separate from the backups.
   =========================================================================== */

SET NOCOUNT ON;
USE master;
GO

DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @sep NCHAR(1) = CASE WHEN @dir LIKE N'%\%' THEN N'\' ELSE N'/' END;
IF RIGHT(@dir, 1) <> @sep SET @dir += @sep;
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(400));
IF RIGHT(@data, 1) <> @sep SET @data += @sep;

-- Remember where the certificate backup files are (names use the thumbprint)
DECLARE @tp NVARCHAR(8) = LEFT(CONVERT(NVARCHAR(64),
                (SELECT thumbprint FROM sys.certificates WHERE name = N'TDE_ShopDB_Cert'), 2), 8);
IF @tp IS NULL
BEGIN
    RAISERROR('Run 06_tde.sql first (certificate TDE_ShopDB_Cert not found).', 16, 1);
    RETURN;
END

-- keep paths in a temp table so every batch below can read them
IF OBJECT_ID(N'tempdb..#Drill') IS NOT NULL DROP TABLE #Drill;
CREATE TABLE #Drill (BakFile NVARCHAR(500), CerFile NVARCHAR(500), PvkFile NVARCHAR(500),
                     DataFile NVARCHAR(500), LogFile NVARCHAR(500));
INSERT #Drill VALUES (@dir + N'ShopDB_drill_encrypted.bak',
                      @dir + N'TDE_ShopDB_Cert_' + @tp + N'.cer',
                      @dir + N'TDE_ShopDB_Cert_' + @tp + N'.pvk',
                      @data + N'ShopDB_Restored.mdf',
                      @data + N'ShopDB_Restored_log.ldf');
GO

/* STEP 1 - encrypted backup ------------------------------------------------ */
DECLARE @bak NVARCHAR(500) = (SELECT BakFile FROM #Drill);
BACKUP DATABASE ShopDB TO DISK = @bak WITH INIT, FORMAT;
PRINT 'STEP 1  encrypted backup taken: ' + @bak;
GO

/* STEP 2 - simulate a server WITHOUT the certificate ----------------------- */
ALTER DATABASE ShopDB SET ENCRYPTION OFF;
GO
DECLARE @w INT = 0;   -- wait until decryption has finished (state 1)
WHILE @w < 120 AND EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
                           WHERE database_id = DB_ID(N'ShopDB') AND encryption_state <> 1)
BEGIN WAITFOR DELAY '00:00:01'; SET @w += 1; END
GO
USE ShopDB;
DROP DATABASE ENCRYPTION KEY;
USE master;
DROP CERTIFICATE TDE_ShopDB_Cert;
PRINT 'STEP 2  certificate removed from the server (simulated loss / new server).';
GO

/* STEP 3 - restore WITHOUT the certificate -> must fail -------------------
   ":ON ERROR IGNORE" is a sqlcmd command: it lets this ONE expected error
   be printed in full (Msg 33111) without stopping the script.
   (In SSMS switch on Query -> SQLCMD Mode to run this file.)            */
:ON ERROR IGNORE
GO
PRINT 'STEP 3  restoring the encrypted backup WITHOUT the certificate (expect Msg 33111):';
DECLARE @bak NVARCHAR(500), @mdf NVARCHAR(500), @ldf NVARCHAR(500);
SELECT @bak = BakFile, @mdf = DataFile, @ldf = LogFile FROM #Drill;
RESTORE DATABASE ShopDB_Restored FROM DISK = @bak
    WITH MOVE N'ShopDB' TO @mdf, MOVE N'ShopDB_log' TO @ldf, REPLACE;
GO
:ON ERROR EXIT
GO
IF DB_ID(N'ShopDB_Restored') IS NULL
    PRINT 'STEP 3  RESULT: restore FAILED - the backup is unreadable without the certificate.';
GO

/* STEP 4 - recreate the certificate from the backup files ---------------- */
DECLARE @cer NVARCHAR(500), @pvk NVARCHAR(500), @sql NVARCHAR(MAX);
SELECT @cer = CerFile, @pvk = PvkFile FROM #Drill;
SET @sql = N'CREATE CERTIFICATE TDE_ShopDB_Cert FROM FILE = ' + QUOTENAME(@cer, '''')
         + N' WITH PRIVATE KEY (FILE = ' + QUOTENAME(@pvk, '''')
         + N', DECRYPTION BY PASSWORD = N''$(CERT_BACKUP_PASSWORD)'');';
EXEC (@sql);
PRINT 'STEP 4  certificate restored from ' + @cer + ' (+ .pvk and its password)';
GO

/* STEP 5 - restore again -> works ---------------------------------------- */
DECLARE @bak NVARCHAR(500), @mdf NVARCHAR(500), @ldf NVARCHAR(500);
SELECT @bak = BakFile, @mdf = DataFile, @ldf = LogFile FROM #Drill;
RESTORE DATABASE ShopDB_Restored FROM DISK = @bak
    WITH MOVE N'ShopDB' TO @mdf, MOVE N'ShopDB_log' TO @ldf, REPLACE;
PRINT 'STEP 5  RESTORE SUCCEEDED with the certificate. Data check:';
GO
SELECT (SELECT COUNT(*) FROM ShopDB_Restored.dbo.Customers) AS Customers,
       (SELECT COUNT(*) FROM ShopDB_Restored.dbo.Orders)    AS Orders,
       (SELECT COUNT(*) FROM ShopDB_Restored.dbo.Products)  AS Products;
GO

/* STEP 6 - clean up and turn TDE back on for ShopDB ---------------------
   A log backup is needed first: in FULL recovery mode SQL Server will not
   start a new encryption scan while log records of the previous scan
   (step 2) have not been backed up (otherwise: Msg 33122).
   The warning "certificate ... has not been backed up" is expected here:
   the certificate was just re-created FROM its backup files.            */
DROP DATABASE ShopDB_Restored;
GO
DECLARE @trn NVARCHAR(500) = REPLACE((SELECT BakFile FROM #Drill), N'.bak', N'_log.trn');
BACKUP LOG ShopDB TO DISK = @trn WITH INIT, FORMAT;
GO
USE ShopDB;
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TDE_ShopDB_Cert;
ALTER DATABASE ShopDB SET ENCRYPTION ON;
GO
DECLARE @w INT = 0;
WHILE @w < 120 AND NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
                               WHERE database_id = DB_ID(N'ShopDB') AND encryption_state = 3)
BEGIN WAITFOR DELAY '00:00:01'; SET @w += 1; END
SELECT DB_NAME(database_id) AS DatabaseName, encryption_state AS State,
       CASE encryption_state WHEN 3 THEN 'ENCRYPTED' ELSE 'not finished' END AS StateText
FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID(N'ShopDB');
PRINT 'STEP 6  drill finished: ShopDB is encrypted again.';
GO
