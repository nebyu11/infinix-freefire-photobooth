/* ===========================================================================
   00_reset.sql  -  remove EVERYTHING this project created (start from zero)
   ---------------------------------------------------------------------------
   Run as : administrator. Use it if you want a completely clean rebuild,
            then run 01 ... 07 again (run_sql.ps1 / run_sql.sh does that).
   Keeps  : the master key of [master] (other things on the server may use
            it) and the backup files on disk (.bak, .cer, .pvk).
   =========================================================================== */
SET NOCOUNT ON;
USE master;
GO
-- databases (SINGLE_USER kicks out open connections, e.g. the Flask app)
IF DB_ID(N'ShopDB_Restored') IS NOT NULL
BEGIN
    ALTER DATABASE ShopDB_Restored SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ShopDB_Restored;
END
IF DB_ID(N'ShopDB') IS NOT NULL
BEGIN
    ALTER DATABASE ShopDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ShopDB;
    PRINT 'ShopDB dropped.';
END
GO
-- logins
DECLARE @n SYSNAME;
DECLARE l CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.server_principals
    WHERE name IN (N'shop_app', N'legacy_app', N'shop_admin', N'sales_addis', N'sales_hawassa',
                   N'support_dawit', N'auditor_meron', N'policy_demo_login');
OPEN l; FETCH NEXT FROM l INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC (N'DROP LOGIN ' + @n);   -- names come from the fixed list above
    PRINT 'Login dropped: ' + @n;
    FETCH NEXT FROM l INTO @n;
END
CLOSE l; DEALLOCATE l;
GO
-- TDE certificate (only possible once no database uses it any more)
IF CERT_ID(N'TDE_ShopDB_Cert') IS NOT NULL
BEGIN
    DROP CERTIFICATE TDE_ShopDB_Cert;
    PRINT 'Certificate TDE_ShopDB_Cert dropped (its .cer/.pvk backup files are still on disk).';
END
GO
PRINT 'Reset complete.';
GO
