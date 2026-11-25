/* ===========================================================================
   03_rbac.sql  -  Role-Based Access Control (RBAC) with least privilege
   ---------------------------------------------------------------------------
   Run as : administrator, after 02. Safe to run again (idempotent).
   Needs  : sqlcmd variables APP_PASSWORD, LEGACY_APP_PASSWORD, STAFF_PASSWORD

   IDEA: permissions are given to ROLES (job functions), never directly to
   people. A person gets exactly the rights of their job by joining a role.

     LOGIN (server level: "who are you?")  ->  USER (database level)
       -> member of ROLE  ->  GRANT / DENY on tables, columns, schemas

   ROLES IN SHOPDB
     admin_role    manage catalog, customers, orders. NOT db_owner: cannot
                   drop tables, change security or edit the audit log.
     sales_role    read customers/orders/products, update order status,
                   payments WITHOUT the card column, cannot change prices.
     support_role  read customers/orders/products only; no payments.
     auditor_role  read-only everything incl. AuditLog; no hashes, no cards.
     customer_role the WEBSITE login. EXECUTE on schema [app] ONLY:
                   no direct SELECT/INSERT/UPDATE/DELETE on any table.

   GRANT gives a right; DENY forbids it and ALWAYS wins over GRANT
   (even if the user gets a GRANT through another role).
   =========================================================================== */

SET NOCOUNT ON;
USE master;
GO

/* ---------------------------------------------------------------------------
   1. LOGINS (server level). All use CHECK_POLICY = ON (02_password_policy).
      Humans: CHECK_EXPIRATION = ON (passwords expire, must be changed).
      Service accounts (shop_app): expiration OFF, because an expired app
      password would take the whole shop offline; instead its password is
      rotated by the admin and kept only in the server's .env file.
   --------------------------------------------------------------------------- */
DECLARE @Logins TABLE (LoginName SYSNAME, Pwd NVARCHAR(128), IsHuman BIT);
INSERT @Logins VALUES
 (N'shop_app',      N'$(APP_PASSWORD)',        0),  -- hardened website
 (N'legacy_app',    N'$(LEGACY_APP_PASSWORD)', 0),  -- VULNERABLE demo only
 (N'shop_admin',    N'$(STAFF_PASSWORD)',      1),
 (N'sales_addis',   N'$(STAFF_PASSWORD)',      1),
 (N'sales_hawassa', N'$(STAFF_PASSWORD)',      1),
 (N'support_dawit', N'$(STAFF_PASSWORD)',      1),
 (N'auditor_meron', N'$(STAFF_PASSWORD)',      1);

DECLARE @name SYSNAME, @pwd NVARCHAR(128), @human BIT, @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT LoginName, Pwd, IsHuman FROM @Logins;
OPEN c;
FETCH NEXT FROM c INTO @name, @pwd, @human;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- QUOTENAME() safely wraps names in [ ] and passwords in ' ' so that
    -- even this admin script cannot be broken by a strange character.
    IF SUSER_ID(@name) IS NULL
        SET @sql = N'CREATE LOGIN ' + QUOTENAME(@name) + N' WITH PASSWORD = ' + QUOTENAME(@pwd, '''')
                 + N', DEFAULT_DATABASE = ShopDB, CHECK_POLICY = ON, CHECK_EXPIRATION = '
                 + CASE WHEN @human = 1 THEN N'ON' ELSE N'OFF' END + N';';
    ELSE   -- already exists: just re-sync its password with .env
        SET @sql = N'ALTER LOGIN ' + QUOTENAME(@name) + N' WITH PASSWORD = ' + QUOTENAME(@pwd, '''') + N';';
    EXEC (@sql);
    FETCH NEXT FROM c INTO @name, @pwd, @human;
END
CLOSE c; DEALLOCATE c;
PRINT 'Logins ready: shop_app, legacy_app, shop_admin, sales_addis, sales_hawassa, support_dawit, auditor_meron';
GO

/* ---------------------------------------------------------------------------
   2. DATABASE USERS + ROLES
   --------------------------------------------------------------------------- */
USE ShopDB;
GO
DECLARE @u SYSNAME;
DECLARE u CURSOR LOCAL FAST_FORWARD FOR
    SELECT v.n FROM (VALUES (N'shop_app'), (N'legacy_app'), (N'shop_admin'), (N'sales_addis'),
                            (N'sales_hawassa'), (N'support_dawit'), (N'auditor_meron')) AS v(n);
OPEN u; FETCH NEXT FROM u INTO @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF USER_ID(@u) IS NULL
        EXEC (N'CREATE USER ' + @u + N' FOR LOGIN ' + @u + N' WITH DEFAULT_SCHEMA = dbo;');
    FETCH NEXT FROM u INTO @u;
END
CLOSE u; DEALLOCATE u;

IF DATABASE_PRINCIPAL_ID(N'admin_role')    IS NULL CREATE ROLE admin_role;
IF DATABASE_PRINCIPAL_ID(N'sales_role')    IS NULL CREATE ROLE sales_role;
IF DATABASE_PRINCIPAL_ID(N'support_role')  IS NULL CREATE ROLE support_role;
IF DATABASE_PRINCIPAL_ID(N'auditor_role')  IS NULL CREATE ROLE auditor_role;
IF DATABASE_PRINCIPAL_ID(N'customer_role') IS NULL CREATE ROLE customer_role;

-- Role membership (ADD MEMBER is harmless if already a member)
ALTER ROLE admin_role    ADD MEMBER shop_admin;
ALTER ROLE sales_role    ADD MEMBER sales_addis;
ALTER ROLE sales_role    ADD MEMBER sales_hawassa;
ALTER ROLE support_role  ADD MEMBER support_dawit;
ALTER ROLE auditor_role  ADD MEMBER auditor_meron;
ALTER ROLE customer_role ADD MEMBER shop_app;
PRINT 'Users and roles ready.';
GO

/* ---------------------------------------------------------------------------
   3. PERMISSIONS (least privilege)
   --------------------------------------------------------------------------- */

-- ---- admin_role: day-to-day management, but NOT an owner ----------------
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Customers  TO admin_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Products   TO admin_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Orders     TO admin_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.OrderItems TO admin_role;
GRANT SELECT, INSERT, UPDATE         ON dbo.Payments   TO admin_role;
GRANT SELECT, INSERT, UPDATE         ON dbo.Staff      TO admin_role;
GRANT SELECT ON dbo.Users (UserID, Username, Role, Status, FailedAttempts, LockedUntil,
                           CustomerID, StaffID, CreatedAt, LastLoginAt) TO admin_role;
GRANT UPDATE ON dbo.Users (Status, FailedAttempts, LockedUntil) TO admin_role;  -- unlock accounts
GRANT SELECT ON dbo.AuditLog TO admin_role;
GRANT EXECUTE ON SCHEMA::app TO admin_role;

-- ---- sales_role ------------------------------------------------------------
GRANT SELECT ON dbo.Customers  TO sales_role;
GRANT SELECT ON dbo.Products   TO sales_role;
GRANT SELECT ON dbo.Orders     TO sales_role;
GRANT SELECT ON dbo.OrderItems TO sales_role;
GRANT UPDATE ON dbo.Orders (Status) TO sales_role;          -- column-level grant
-- Payments: every column EXCEPT the card number (column-level grant)
GRANT SELECT ON dbo.Payments (PaymentID, OrderID, Amount, Method, Status, PaidAt) TO sales_role;
DENY  UPDATE ON dbo.Products TO sales_role;                  -- no price changes

-- ---- support_role ----------------------------------------------------------
GRANT SELECT ON dbo.Customers  TO support_role;
GRANT SELECT ON dbo.Products   TO support_role;
GRANT SELECT ON dbo.Orders     TO support_role;
GRANT SELECT ON dbo.OrderItems TO support_role;
DENY  SELECT ON dbo.Payments   TO support_role;

-- ---- auditor_role: read-only, can see the audit trail ----------------------
GRANT SELECT ON dbo.AuditLog   TO auditor_role;
GRANT SELECT ON dbo.Customers  TO auditor_role;
GRANT SELECT ON dbo.Products   TO auditor_role;
GRANT SELECT ON dbo.Orders     TO auditor_role;
GRANT SELECT ON dbo.OrderItems TO auditor_role;
GRANT SELECT ON dbo.Staff      TO auditor_role;
GRANT SELECT ON dbo.Payments (PaymentID, OrderID, Amount, Method, Status, PaidAt) TO auditor_role;
GRANT SELECT ON dbo.Users (UserID, Username, Role, Status, FailedAttempts, LockedUntil,
                           CreatedAt, LastLoginAt) TO auditor_role;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO auditor_role;   -- truly read-only

-- ---- customer_role (the website): ONLY the app procedures ---------------
GRANT EXECUTE ON SCHEMA::app TO customer_role;
-- Belt and braces: even if someone later grants table rights by mistake,
-- DENY wins. Procedures still work thanks to ownership chaining.
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO customer_role;

-- ---- Everyone: password hashes are never readable, audit log is append-only
DENY SELECT ON dbo.Users (PasswordHash, PasswordSalt) TO admin_role, sales_role, support_role, auditor_role;
DENY SELECT ON dbo.PasswordHistory TO admin_role, sales_role, support_role, auditor_role;
DENY UPDATE, DELETE ON dbo.AuditLog TO admin_role, sales_role, support_role, auditor_role, customer_role;

/* ---- ANTI-PATTERN, for the SQL-injection demo ONLY ----------------------
   legacy_app imitates a typical badly configured web app: it can read and
   write EVERY table (db_datareader + db_datawriter). Combined with string-
   concatenated SQL in the app this is what makes injection so damaging.
   NEVER do this in a real system.                                        */
ALTER ROLE db_datareader ADD MEMBER legacy_app;
ALTER ROLE db_datawriter ADD MEMBER legacy_app;
-- its (string-built) login query calls the hash function directly
GRANT EXECUTE ON dbo.fn_HashPassword TO legacy_app;
PRINT 'Permissions granted.';
GO

/* ---------------------------------------------------------------------------
   4. SHOW the role memberships
   --------------------------------------------------------------------------- */
PRINT '--- Role members ---';
SELECT r.name AS RoleName, m.name AS MemberName
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
WHERE m.name IN (N'shop_app', N'legacy_app', N'shop_admin', N'sales_addis',
                 N'sales_hawassa', N'support_dawit', N'auditor_meron')
ORDER BY r.name, m.name;
GO

/* ---------------------------------------------------------------------------
   5. TEST: PERMISSION MATRIX
   For every user we IMPERSONATE them (EXECUTE AS USER), try each action and
   record ALLOWED or DENIED. Changes are made inside a transaction that is
   always rolled back, so the test never modifies data.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'tempdb..#Matrix') IS NOT NULL DROP TABLE #Matrix;
CREATE TABLE #Matrix (TestNo INT, Action NVARCHAR(60), DbUser SYSNAME, Outcome VARCHAR(7));

DECLARE @Tests TABLE (TestNo INT, Action NVARCHAR(60), Stmt NVARCHAR(400));
INSERT @Tests VALUES
 (1, N'SELECT Products',              N'DECLARE @x INT; SELECT @x = COUNT(*) FROM dbo.Products;'),
 (2, N'UPDATE Products price',        N'UPDATE dbo.Products SET Price = 1 WHERE ProductID = 1;'),
 (3, N'SELECT Customers',             N'DECLARE @x INT; SELECT @x = COUNT(*) FROM dbo.Customers;'),
 (4, N'UPDATE Orders.Status',         N'UPDATE dbo.Orders SET Status = N''Shipped'' WHERE OrderID = 1004;'),
 (5, N'SELECT Payments.CardNumber',   N'DECLARE @x VARCHAR(19); SELECT TOP (1) @x = CardNumber FROM dbo.Payments;'),
 (6, N'SELECT Users.PasswordHash',    N'DECLARE @x VARBINARY(64); SELECT TOP (1) @x = PasswordHash FROM dbo.Users;'),
 (7, N'SELECT AuditLog',              N'DECLARE @x INT; SELECT @x = COUNT(*) FROM dbo.AuditLog;'),
 (8, N'DELETE AuditLog (hide tracks)',N'DELETE FROM dbo.AuditLog;'),
 (9, N'DROP TABLE Customers',         N'DROP TABLE dbo.Customers;'),
 (10,N'EXEC app procedure',           N'DECLARE @r INT, @m NVARCHAR(400); EXEC app.sp_ChangePassword N''x'', N''y'', N''z'', @r OUTPUT, @m OUTPUT;');

DECLARE @Users TABLE (DbUser SYSNAME, Ord INT);
INSERT @Users VALUES (N'shop_admin',1),(N'sales_addis',2),(N'support_dawit',3),
                     (N'auditor_meron',4),(N'shop_app',5),(N'legacy_app',6);

DECLARE @TestNo INT, @Action NVARCHAR(60), @Stmt NVARCHAR(400), @DbUser SYSNAME, @Outcome VARCHAR(7);
DECLARE t CURSOR LOCAL FAST_FORWARD FOR
    SELECT t.TestNo, t.Action, t.Stmt, u.DbUser FROM @Tests t CROSS JOIN @Users u ORDER BY t.TestNo, u.Ord;
OPEN t; FETCH NEXT FROM t INTO @TestNo, @Action, @Stmt, @DbUser;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRANSACTION;
    EXECUTE AS USER = @DbUser;                 -- become that user
    BEGIN TRY
        EXEC sys.sp_executesql @Stmt;
        SET @Outcome = 'ALLOWED';
    END TRY
    BEGIN CATCH
        SET @Outcome = 'DENIED';
    END CATCH;
    REVERT;                                    -- become admin again
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- undo any change
    INSERT #Matrix VALUES (@TestNo, @Action, @DbUser, @Outcome);
    FETCH NEXT FROM t INTO @TestNo, @Action, @Stmt, @DbUser;
END
CLOSE t; DEALLOCATE t;

PRINT '--- Permission matrix (each cell = what happened when that user tried) ---';
SELECT Action, [shop_admin] AS admin, [sales_addis] AS sales, [support_dawit] AS support,
       [auditor_meron] AS auditor, [shop_app] AS website_app, [legacy_app] AS legacy_app_BAD
FROM (SELECT TestNo, Action, DbUser, Outcome FROM #Matrix) AS s
PIVOT (MAX(Outcome) FOR DbUser IN ([shop_admin],[sales_addis],[support_dawit],
                                   [auditor_meron],[shop_app],[legacy_app])) AS p
ORDER BY TestNo;
GO
