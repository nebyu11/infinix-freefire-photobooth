/* ===========================================================================
   99_demo_queries.sql  -  the LIVE DEMO in SSMS, in presentation order
   ---------------------------------------------------------------------------
   Open this file in SSMS (connected as your Windows admin / sa), then
   highlight ONE block at a time and press F5. Each block is short so the
   audience can follow. No sqlcmd variables are needed.
   Everything here is read-only or rolled back, so you can repeat it.
   =========================================================================== */
USE ShopDB;
GO

/* ---- D1. CONSTRAINTS: the database itself refuses bad data -------------- */
INSERT INTO dbo.Products (SKU, Name, Category, Price) VALUES ('X-1', N'Free phone', N'Electronics', -5);
-- expected: conflict with CHECK constraint "CK_Products_Price"
GO

/* ---- D2. PASSWORDS are stored as salt + hash, never plaintext ------------- */
SELECT TOP (3) Username, Role, PasswordSalt, PasswordHash FROM dbo.Users ORDER BY UserID;
GO

/* ---- D3. PASSWORD POLICY: weak SQL login refused (CHECK_POLICY = ON) ------ */
CREATE LOGIN weak_demo WITH PASSWORD = N'shop123', CHECK_POLICY = ON;
-- expected: Password validation failed ... too short / not complex enough
GO
/* website password rules (one function used by register + change password) */
SELECT Candidate, ISNULL(dbo.fn_PasswordPolicyErrors(Candidate, N'abebe'), N'ACCEPTED') AS Result
FROM (VALUES (N'abebe2026'), (N'Password123!'), (N'Blue-Coffee#Hawassa7')) AS t(Candidate);
GO

/* ---- D4. RBAC: sales may read orders but NOT change prices ---------------- */
EXECUTE AS USER = N'sales_addis';
    SELECT USER_NAME() AS IAm, COUNT(*) AS ProductsICanSee FROM dbo.Products;
    UPDATE dbo.Products SET Price = 1 WHERE ProductID = 2;     -- expected: permission DENIED
REVERT;
GO
/* the website login cannot read ANY table directly - only call procedures */
EXECUTE AS USER = N'shop_app';
    SELECT * FROM dbo.Customers;                               -- expected: permission DENIED
REVERT;
GO

/* ---- D5. ABAC (Row-Level Security): SAME query, different rows ------------ */
EXECUTE AS USER = N'sales_addis';
    SELECT USER_NAME() AS IAm, OrderID, ShipRegion, TotalAmount FROM dbo.Orders;   -- Addis Ababa only
REVERT;
EXECUTE AS USER = N'sales_hawassa';
    SELECT USER_NAME() AS IAm, OrderID, ShipRegion, TotalAmount FROM dbo.Orders;   -- Hawassa only
REVERT;
GO

/* ---- D6. DATA MASKING: SAME query, different column values ---------------- */
EXECUTE AS USER = N'sales_addis';
    SELECT USER_NAME() AS IAm, FirstName, Email, Phone FROM dbo.Customers;          -- real values
REVERT;
EXECUTE AS USER = N'support_dawit';
    SELECT USER_NAME() AS IAm, FirstName, Email, Phone FROM dbo.Customers;          -- masked
REVERT;
GO

/* ---- D7. TDE: is the database encrypted on disk? -------------------------- */
SELECT DB_NAME(database_id) AS DatabaseName, encryption_state AS State,   -- 3 = encrypted
       key_algorithm, key_length, encryptor_type
FROM sys.dm_database_encryption_keys;
GO

/* ---- D8. COLUMN ENCRYPTION: authorized vs unauthorized -------------------- */
EXECUTE AS USER = N'shop_admin';      -- admin_role may use the key
    SELECT USER_NAME() AS IAm, PaymentID, CardLast4,
           CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL,
                   CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID))) AS CardNumber
    FROM dbo.Payments WHERE CardNumberEnc IS NOT NULL;
REVERT;
EXECUTE AS USER = N'sales_addis';     -- no key permission -> NULL
    SELECT USER_NAME() AS IAm, PaymentID, CardLast4, CardNumberEnc,
           CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL,
                   CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID))) AS CardNumber
    FROM dbo.Payments WHERE CardNumberEnc IS NOT NULL;
REVERT;
GO

/* ---- D9. AUDIT TRAIL: what happened during the web demo ------------------- */
SELECT TOP (15) EventTime, EventType, AppUsername, DbLogin, Details
FROM dbo.AuditLog ORDER BY AuditID DESC;
GO

/* ---- D10. (after the demo) unlock an account that the lockout demo locked */
-- UPDATE dbo.Users SET Status = N'Active', FailedAttempts = 0, LockedUntil = NULL WHERE Username = N'yonas.b';
