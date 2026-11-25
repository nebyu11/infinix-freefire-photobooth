/* ===========================================================================
   06_tde.sql  -  Encryption at rest (TDE) + column (cell-level) encryption
   ---------------------------------------------------------------------------
   Run as : administrator, after 05. Safe to run again (idempotent).
   Needs  : sqlcmd variables MASTER_KEY_PASSWORD, CERT_BACKUP_PASSWORD
   Edition: TDE needs Developer / Enterprise / Standard (2019+). NOT Express.

   TWO DIFFERENT PROTECTIONS
   ┌─────────────────────┬──────────────────────────────┬───────────────────────────────┐
   │                     │ TDE (Transparent Data Enc.)  │ Column / cell-level encryption│
   ├─────────────────────┼──────────────────────────────┼───────────────────────────────┤
   │ What is encrypted   │ whole database FILES on disk │ one column (card numbers)     │
   │                     │ (.mdf, .ldf, backups)        │                               │
   │ Protects against    │ stolen disk / stolen backup  │ users who CAN query the table │
   │                     │ / copied .mdf file           │ but must not read the value   │
   │ Who sees plaintext  │ anyone with SELECT rights    │ only users allowed to use the │
   │                     │ (decrypted automatically)    │ key (we grant: admin_role)    │
   │ App changes needed  │ none ("transparent")         │ ENCRYPTBYKEY / DECRYPTBYKEY   │
   └─────────────────────┴──────────────────────────────┴───────────────────────────────┘

   KEY HIERARCHY (TDE)
     Service Master Key (created by SQL Server setup, protected by the OS)
       -> Database Master Key in [master]     (CREATE MASTER KEY)
         -> Certificate TDE_ShopDB_Cert         (CREATE CERTIFICATE)
           -> Database Encryption Key in ShopDB (CREATE DATABASE ENCRYPTION KEY, AES-256)
             -> encrypts every data page as it is written to disk

   ORDER OF THIS SCRIPT
     1. Backup "before"  (plaintext backup, to compare later)
     2. Column encryption of Payments.CardNumber (then drop the plaintext column)
     3. TDE: master key, certificate, CERTIFICATE BACKUP, DEK, encryption ON
     4. Backup "after" and verification
     5. Tests: authorized vs unauthorized user reading card numbers
     6. Data classification: sensitivity labels on sensitive columns
   What happens if the certificate is LOST? -> see 06b_tde_lost_cert_drill.sql
   =========================================================================== */

SET NOCOUNT ON;
USE master;
GO

/* ---------------------------------------------------------------------------
   0. Where do backup files go? The instance's default backup folder: the
      SQL Server service account can always write there (Windows and Linux).
   --------------------------------------------------------------------------- */
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @sep NCHAR(1) = CASE WHEN @dir LIKE N'%\%' THEN N'\' ELSE N'/' END;
IF RIGHT(@dir, 1) <> @sep SET @dir += @sep;
PRINT 'Backup folder: ' + @dir;

/* ---------------------------------------------------------------------------
   1. BACKUP "BEFORE" - TDE is still OFF, so this file contains readable data
      (use it in the demo to show a stolen, unencrypted backup is readable)
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
               WHERE database_id = DB_ID(N'ShopDB') AND encryption_state IN (2, 3))
BEGIN
    DECLARE @before NVARCHAR(500) = @dir + N'ShopDB_before_TDE.bak';
    BACKUP DATABASE ShopDB TO DISK = @before WITH INIT, FORMAT, NO_COMPRESSION;
    PRINT 'Plain backup written: ' + @before;
END
GO

/* ===========================================================================
   2. COLUMN ENCRYPTION of the card number (cell-level, AES-256)
      Key chain inside ShopDB:
        Database Master Key -> certificate CardDataCert -> symmetric key CardDataKey
   =========================================================================== */
USE ShopDB;
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(MASTER_KEY_PASSWORD)';
IF CERT_ID(N'CardDataCert') IS NULL
    CREATE CERTIFICATE CardDataCert
        WITH SUBJECT = N'Protects the key that encrypts card numbers',
             EXPIRY_DATE = '2030-12-31';
IF KEY_ID(N'CardDataKey') IS NULL
    CREATE SYMMETRIC KEY CardDataKey
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE CardDataCert;
GO

-- new columns: ciphertext + last 4 digits (safe to show on receipts)
IF COL_LENGTH(N'dbo.Payments', N'CardNumberEnc') IS NULL
    ALTER TABLE dbo.Payments ADD CardNumberEnc VARBINARY(256) NULL, CardLast4 CHAR(4) NULL;
GO

/* Encrypt existing card numbers, then REMOVE the plaintext column.
   Dynamic SQL is used only because the CardNumber column may already be
   gone on a re-run (the code would not compile otherwise).
   The 4th argument of ENCRYPTBYKEY is an "authenticator" (the PaymentID):
   an encrypted value copied to another row will NOT decrypt there. */
IF COL_LENGTH(N'dbo.Payments', N'CardNumber') IS NOT NULL
BEGIN
    EXEC (N'
        OPEN SYMMETRIC KEY CardDataKey DECRYPTION BY CERTIFICATE CardDataCert;
        UPDATE dbo.Payments
           SET CardNumberEnc = ENCRYPTBYKEY(KEY_GUID(N''CardDataKey''), CardNumber, 1,
                                            CONVERT(VARBINARY(4), PaymentID)),
               CardLast4     = RIGHT(CardNumber, 4)
         WHERE CardNumber IS NOT NULL;
        CLOSE SYMMETRIC KEY CardDataKey;
        ALTER TABLE dbo.Payments DROP CONSTRAINT CK_Payments_CardOnlyForCard;
        ALTER TABLE dbo.Payments DROP COLUMN CardNumber;
        ALTER TABLE dbo.Payments ADD CONSTRAINT CK_Payments_CardOnlyForCard
              CHECK (Method = N''Card'' OR CardNumberEnc IS NULL);');
    PRINT 'Card numbers encrypted; plaintext column CardNumber dropped.';
END
ELSE
    PRINT 'Card numbers were already encrypted (re-run).';
GO

/* Permissions for the encrypted data
   - sales_role / auditor_role may SELECT the ciphertext and the last 4
     digits, but get NO rights on the key -> they cannot decrypt.
   - admin_role may use the certificate + key -> can decrypt.            */
GRANT SELECT ON dbo.Payments (CardNumberEnc, CardLast4) TO sales_role, auditor_role;
GRANT VIEW DEFINITION ON SYMMETRIC KEY::CardDataKey TO admin_role;
GRANT CONTROL ON CERTIFICATE::CardDataCert TO admin_role;
GO

/* ===========================================================================
   3. TRANSPARENT DATA ENCRYPTION
   =========================================================================== */
USE master;
GO
-- 3a. master key of the server ([master] database)
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(MASTER_KEY_PASSWORD)';
    PRINT 'Master key created in [master].';
END
-- 3b. certificate that will protect ShopDB's encryption key
IF CERT_ID(N'TDE_ShopDB_Cert') IS NULL
BEGIN
    CREATE CERTIFICATE TDE_ShopDB_Cert
        WITH SUBJECT = N'TDE certificate for ShopDB', EXPIRY_DATE = '2030-12-31';
    PRINT 'Certificate TDE_ShopDB_Cert created.';
END
GO

-- 3c. BACK UP THE CERTIFICATE + PRIVATE KEY (do this BEFORE encrypting!)
--     Without these two files an encrypted backup can NEVER be restored on
--     another server. File names include part of the thumbprint so a new
--     certificate never overwrites the backup of an old one.
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @sep NCHAR(1) = CASE WHEN @dir LIKE N'%\%' THEN N'\' ELSE N'/' END;
IF RIGHT(@dir, 1) <> @sep SET @dir += @sep;
DECLARE @tp  NVARCHAR(8) = LEFT(CONVERT(NVARCHAR(64),
                    (SELECT thumbprint FROM sys.certificates WHERE name = N'TDE_ShopDB_Cert'), 2), 8);
DECLARE @cer NVARCHAR(500) = @dir + N'TDE_ShopDB_Cert_' + @tp + N'.cer';
DECLARE @pvk NVARCHAR(500) = @dir + N'TDE_ShopDB_Cert_' + @tp + N'.pvk';
DECLARE @sql NVARCHAR(MAX) =
      N'BACKUP CERTIFICATE TDE_ShopDB_Cert TO FILE = ' + QUOTENAME(@cer, '''')
    + N' WITH PRIVATE KEY (FILE = ' + QUOTENAME(@pvk, '''')
    + N', ENCRYPTION BY PASSWORD = N''$(CERT_BACKUP_PASSWORD)'');';
BEGIN TRY
    EXEC (@sql);
    PRINT 'Certificate backed up to: ' + @cer + '  and  ' + @pvk;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 15240   -- file already exists = backed up on an earlier run
        PRINT 'Certificate backup already exists: ' + @cer;
    ELSE
        THROW;
END CATCH
PRINT 'Store these two files + the password OUTSIDE the server (e.g. a safe / key vault).';
GO

-- 3d. database encryption key (DEK) inside ShopDB, then switch encryption on
USE ShopDB;
GO
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
BEGIN
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE TDE_ShopDB_Cert;
    PRINT 'Database encryption key created.';
END
GO
IF (SELECT is_encrypted FROM sys.databases WHERE name = N'ShopDB') = 0
    ALTER DATABASE ShopDB SET ENCRYPTION ON;     -- (re-run: already on, skip)
GO
-- encryption runs in the background; wait until it is finished (state 3)
DECLARE @wait INT = 0;
WHILE @wait < 120 AND NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
                                  WHERE database_id = DB_ID(N'ShopDB') AND encryption_state = 3)
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @wait += 1;
END
GO

/* ===========================================================================
   4. VERIFY TDE + "after" backup
   =========================================================================== */
PRINT '--- sys.dm_database_encryption_keys ---';
SELECT DB_NAME(k.database_id)        AS DatabaseName,
       k.encryption_state            AS State,
       CASE k.encryption_state WHEN 0 THEN 'No key' WHEN 1 THEN 'Unencrypted'
            WHEN 2 THEN 'Encrypting...' WHEN 3 THEN 'ENCRYPTED' WHEN 4 THEN 'Key change'
            WHEN 5 THEN 'Decrypting...' END AS StateText,
       k.key_algorithm + '-' + CAST(k.key_length AS VARCHAR(5)) AS Algorithm,
       k.encryptor_type              AS EncryptedBy,
       c.name                        AS CertificateName
FROM sys.dm_database_encryption_keys AS k
LEFT JOIN master.sys.certificates AS c ON c.thumbprint = k.encryptor_thumbprint;
-- note: tempdb appears too - SQL Server encrypts tempdb automatically as soon
-- as any database uses TDE (temporary data must not leak either)
GO
SELECT name, is_encrypted FROM sys.databases WHERE name IN (N'ShopDB', N'tempdb');
GO

USE master;
GO
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @sep NCHAR(1) = CASE WHEN @dir LIKE N'%\%' THEN N'\' ELSE N'/' END;
IF RIGHT(@dir, 1) <> @sep SET @dir += @sep;
DECLARE @after NVARCHAR(500) = @dir + N'ShopDB_after_TDE.bak';
BACKUP DATABASE ShopDB TO DISK = @after WITH INIT, FORMAT, NO_COMPRESSION;
PRINT 'Encrypted backup written: ' + @after;
PRINT 'Compare: search both .bak files for the text EL-PHN-001 (a product SKU):';
PRINT '  before_TDE.bak -> found (readable)   after_TDE.bak -> not found (encrypted)';
GO

/* ===========================================================================
   5. TEST COLUMN ENCRYPTION: who can read card numbers?
   =========================================================================== */
USE ShopDB;
GO
PRINT '';
PRINT '=== TEST A: what is physically stored (ciphertext, no plaintext column) ===';
-- (the first 16 bytes of every value are the GUID of the key, so we show
--  the END of the ciphertext, which is different for every card)
SELECT TOP (3) PaymentID, Method, CardLast4, DATALENGTH(CardNumberEnc) AS Bytes,
       '...' + RIGHT(CONVERT(VARCHAR(600), CardNumberEnc, 2), 32) AS CardNumberEnc_last_bytes
FROM dbo.Payments WHERE CardNumberEnc IS NOT NULL ORDER BY PaymentID;
GO

PRINT '=== TEST B: AUTHORIZED user shop_admin (admin_role, may use the key) ===';
EXECUTE AS USER = N'shop_admin';
    SELECT PaymentID, Method, CardLast4,
           CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL,
                   CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID))) AS CardNumber_Decrypted
    FROM dbo.Payments WHERE CardNumberEnc IS NOT NULL ORDER BY PaymentID;
REVERT;
GO

PRINT '=== TEST C: UNAUTHORIZED user sales_addis (can SELECT the column, no key rights) ===';
EXECUTE AS USER = N'sales_addis';
    SELECT PaymentID, Method, CardLast4,
           CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL,
                   CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID))) AS CardNumber_Decrypted
    FROM dbo.Payments WHERE CardNumberEnc IS NOT NULL ORDER BY PaymentID;
    BEGIN TRY
        OPEN SYMMETRIC KEY CardDataKey DECRYPTION BY CERTIFICATE CardDataCert;
        PRINT 'FAIL: sales_addis could open the key';
        CLOSE SYMMETRIC KEY CardDataKey;
    END TRY
    BEGIN CATCH
        PRINT 'OPEN SYMMETRIC KEY as sales_addis -> ' + ERROR_MESSAGE();
    END CATCH
REVERT;
GO

PRINT '=== TEST D: the "authenticator" - ciphertext copied to another row will not decrypt ===';
BEGIN TRANSACTION;
    -- an insider copies Payment 1's encrypted card into Payment 3
    UPDATE p3 SET CardNumberEnc = p1.CardNumberEnc
    FROM dbo.Payments AS p3 CROSS JOIN dbo.Payments AS p1
    WHERE p3.PaymentID = 3 AND p1.PaymentID = 1;
    SELECT PaymentID,
           CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL,
                   CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID))) AS Decrypted
    FROM dbo.Payments WHERE PaymentID IN (1, 3);
ROLLBACK TRANSACTION;   -- undo the "attack"
GO

/* ===========================================================================
   6. DATA DISCOVERY & CLASSIFICATION (lecture: "Data Protection in Databases")
      Label sensitive columns so auditing and tools know what they contain.
      Running it again simply overwrites the labels (idempotent).
   =========================================================================== */
ADD SENSITIVITY CLASSIFICATION TO dbo.Payments.CardNumberEnc
    WITH (LABEL = 'Highly Confidential', INFORMATION_TYPE = 'Credit Card', RANK = CRITICAL);
ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.Email, dbo.Customers.Phone
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Contact Info', RANK = MEDIUM);
ADD SENSITIVITY CLASSIFICATION TO dbo.Users.PasswordHash, dbo.Users.MfaSecretEnc
    WITH (LABEL = 'Highly Confidential', INFORMATION_TYPE = 'Credentials', RANK = HIGH);
GO
PRINT '--- Sensitivity classification ---';
SELECT OBJECT_NAME(c.major_id) AS TableName,
       COL_NAME(c.major_id, c.minor_id) AS ColumnName,
       c.label, c.information_type, c.rank_desc
FROM sys.sensitivity_classifications AS c
ORDER BY c.rank DESC, TableName;
GO
