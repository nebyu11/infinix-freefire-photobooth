/* ===========================================================================
   01_schema.sql  -  ShopDB: database, tables, constraints and sample data
   ---------------------------------------------------------------------------
   Project : E-commerce Database Security (SQL Server 2022 Developer)
   Run as  : an administrator (sa / Windows admin) through run_sql.sh / .ps1
   Needs   : sqlcmd variable DEMO_USER_PASSWORD (comes from .env)

   WHAT THIS SCRIPT DOES
     1. (Re)creates the database ShopDB from scratch.
        -> "Idempotent by re-creation": running it twice gives the same result.
           WARNING: it DROPS the old ShopDB, so run it only to start over.
     2. Creates 8 tables with PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK,
        DEFAULT and NOT NULL constraints.
     3. Creates a password-hashing function (salted + iterated SHA-512).
     4. Inserts realistic sample data into EVERY table.

   SECURITY IDEAS SHOWN HERE
     - Constraints = data integrity: bad data is rejected by the database
       itself, even if the application has a bug.
     - Passwords are NEVER stored in plaintext: only a random salt and a
       slow, salted hash (see dbo.fn_HashPassword below).
     - Payments.CardNumber is stored in plaintext ON PURPOSE in this first
       script: it is the "before" state. 06_tde.sql encrypts it and removes
       the plaintext column ("after" state).
   =========================================================================== */

SET NOCOUNT ON;
USE master;
GO

/* ---------------------------------------------------------------------------
   1. Create the database (drop the old copy first, if any)
   SINGLE_USER WITH ROLLBACK IMMEDIATE disconnects anyone still connected,
   otherwise DROP DATABASE would fail with "database is in use".
   --------------------------------------------------------------------------- */
IF DB_ID(N'ShopDB') IS NOT NULL
BEGIN
    ALTER DATABASE ShopDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ShopDB;
    PRINT 'Old ShopDB dropped.';
END
GO

CREATE DATABASE ShopDB;
GO
PRINT 'ShopDB created.';
GO

USE ShopDB;
GO

/* Schema "app" = the API layer. Only the stored procedures that the website
   is allowed to call go into this schema (02 and 05). Tables stay in "dbo".
   03_rbac.sql then grants the website EXECUTE on schema app - and nothing
   else. Both schemas are owned by dbo, so procedures can still read the
   tables (this is called "ownership chaining"). */
EXEC (N'CREATE SCHEMA app AUTHORIZATION dbo');
GO

/* ---------------------------------------------------------------------------
   2. TABLES
   Naming: PK_ = primary key, FK_ = foreign key, UQ_ = unique,
           CK_ = check, DF_ = default. Named constraints give clear error
           messages and are easy to explain in the demo.
   --------------------------------------------------------------------------- */

/* ---- Staff: employees of the shop. Their Department and Region are the
        ATTRIBUTES used later by ABAC (04_abac.sql). DbUserName links a
        staff member to their SQL Server database user. -------------------- */
CREATE TABLE dbo.Staff
(
    StaffID      INT IDENTITY(1,1)  NOT NULL CONSTRAINT PK_Staff PRIMARY KEY,
    FullName     NVARCHAR(100)      NOT NULL,
    Email        NVARCHAR(150)      NOT NULL CONSTRAINT UQ_Staff_Email UNIQUE,
    Department   NVARCHAR(20)       NOT NULL
        CONSTRAINT CK_Staff_Department CHECK (Department IN (N'Admin', N'Sales', N'Support', N'Audit')),
    -- 'ALL' = head-office staff who work with every region
    Region       NVARCHAR(30)       NOT NULL
        CONSTRAINT CK_Staff_Region CHECK (Region IN (N'ALL', N'Addis Ababa', N'Hawassa', N'Bahir Dar', N'Dire Dawa')),
    DbUserName   SYSNAME            NOT NULL CONSTRAINT UQ_Staff_DbUserName UNIQUE,
    IsActive     BIT                NOT NULL CONSTRAINT DF_Staff_IsActive DEFAULT (1),
    HiredAt      DATE               NOT NULL CONSTRAINT DF_Staff_HiredAt DEFAULT (CAST(SYSDATETIME() AS DATE))
);

/* ---- Customers: personal data (PII) = a high-value asset ------------------ */
CREATE TABLE dbo.Customers
(
    CustomerID   INT IDENTITY(1,1)  NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    FirstName    NVARCHAR(50)       NOT NULL,
    LastName     NVARCHAR(50)       NOT NULL,
    Email        NVARCHAR(150)      NOT NULL CONSTRAINT UQ_Customers_Email UNIQUE,
    Phone        VARCHAR(20)        NOT NULL,
    City         NVARCHAR(50)       NOT NULL,
    Region       NVARCHAR(30)       NOT NULL
        CONSTRAINT CK_Customers_Region CHECK (Region IN (N'Addis Ababa', N'Hawassa', N'Bahir Dar', N'Dire Dawa')),
    CreatedAt    DATETIME2(0)       NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSDATETIME()),
    -- a very simple e-mail shape check: something@something.something
    CONSTRAINT CK_Customers_Email CHECK (Email LIKE N'%_@_%._%'),
    -- Ethiopian mobile format, e.g. +251911234567
    CONSTRAINT CK_Customers_Phone CHECK (Phone LIKE '+251[79][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);

/* ---- Users: website login accounts (customers AND staff) ------------------
   PasswordHash / PasswordSalt : see fn_HashPassword below - no plaintext!
   FailedAttempts / LockedUntil: used for account lockout (05 script)
   A customer account must point to a customer; a staff account to staff. */
CREATE TABLE dbo.Users
(
    UserID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    Username       NVARCHAR(30)      NOT NULL CONSTRAINT UQ_Users_Username UNIQUE,
    PasswordHash   VARBINARY(64)     NOT NULL,   -- SHA-512 output = 64 bytes
    PasswordSalt   VARBINARY(16)     NOT NULL,   -- 16 random bytes per user
    Role           NVARCHAR(20)      NOT NULL
        CONSTRAINT CK_Users_Role CHECK (Role IN (N'Customer', N'Sales', N'Support', N'Admin', N'Auditor')),
    Status         NVARCHAR(10)      NOT NULL CONSTRAINT DF_Users_Status DEFAULT (N'Active')
        CONSTRAINT CK_Users_Status CHECK (Status IN (N'Active', N'Locked', N'Disabled')),
    FailedAttempts INT               NOT NULL CONSTRAINT DF_Users_FailedAttempts DEFAULT (0)
        CONSTRAINT CK_Users_FailedAttempts CHECK (FailedAttempts >= 0),
    LockedUntil    DATETIME2(0)      NULL,
    CustomerID     INT               NULL CONSTRAINT FK_Users_Customers REFERENCES dbo.Customers(CustomerID),
    StaffID        INT               NULL CONSTRAINT FK_Users_Staff     REFERENCES dbo.Staff(StaffID),
    CreatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSDATETIME()),
    LastLoginAt    DATETIME2(0)      NULL,
    PasswordChangedAt DATETIME2(0)   NOT NULL CONSTRAINT DF_Users_PwdChanged DEFAULT (SYSDATETIME()),
    -- Multi-factor authentication (optional step 07): the TOTP secret is
    -- stored ENCRYPTED by the application, never in plaintext.
    MfaEnabled     BIT               NOT NULL CONSTRAINT DF_Users_MfaEnabled DEFAULT (0),
    MfaSecretEnc   VARBINARY(512)    NULL,
    -- usernames: only letters, digits, dot and underscore (no spaces/quotes)
    CONSTRAINT CK_Users_UsernameChars CHECK (Username NOT LIKE N'%[^a-zA-Z0-9._]%' AND LEN(Username) >= 3),
    -- a Customer account must be linked to exactly a customer, staff to staff
    CONSTRAINT CK_Users_Link CHECK (
        (Role = N'Customer' AND CustomerID IS NOT NULL AND StaffID IS NULL) OR
        (Role <> N'Customer' AND StaffID IS NOT NULL AND CustomerID IS NULL))
);

/* ---- Products: the catalog ------------------------------------------------ */
CREATE TABLE dbo.Products
(
    ProductID    INT IDENTITY(1,1)  NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    SKU          VARCHAR(20)        NOT NULL CONSTRAINT UQ_Products_SKU UNIQUE,
    Name         NVARCHAR(100)      NOT NULL,
    Category     NVARCHAR(30)       NOT NULL
        CONSTRAINT CK_Products_Category CHECK (Category IN (N'Electronics', N'Clothing', N'Home', N'Books', N'Food')),
    Price        DECIMAL(10,2)      NOT NULL CONSTRAINT CK_Products_Price CHECK (Price > 0),   -- ETB
    Stock        INT                NOT NULL CONSTRAINT DF_Products_Stock DEFAULT (0)
        CONSTRAINT CK_Products_Stock CHECK (Stock >= 0),
    IsActive     BIT                NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1)
);

/* ---- Orders: ShipRegion is the "resource attribute" used by ABAC --------- */
CREATE TABLE dbo.Orders
(
    OrderID      INT IDENTITY(1001,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerID   INT                NOT NULL CONSTRAINT FK_Orders_Customers REFERENCES dbo.Customers(CustomerID),
    OrderDate    DATETIME2(0)       NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT (SYSDATETIME()),
    Status       NVARCHAR(15)       NOT NULL CONSTRAINT DF_Orders_Status DEFAULT (N'Pending')
        CONSTRAINT CK_Orders_Status CHECK (Status IN (N'Pending', N'Paid', N'Shipped', N'Delivered', N'Cancelled')),
    ShipRegion   NVARCHAR(30)       NOT NULL
        CONSTRAINT CK_Orders_ShipRegion CHECK (ShipRegion IN (N'Addis Ababa', N'Hawassa', N'Bahir Dar', N'Dire Dawa')),
    TotalAmount  DECIMAL(12,2)      NOT NULL CONSTRAINT DF_Orders_Total DEFAULT (0)
        CONSTRAINT CK_Orders_Total CHECK (TotalAmount >= 0)
);

/* ---- OrderItems: composite primary key (one row per product per order) -- */
CREATE TABLE dbo.OrderItems
(
    OrderID      INT            NOT NULL CONSTRAINT FK_OrderItems_Orders   REFERENCES dbo.Orders(OrderID) ON DELETE CASCADE,
    ProductID    INT            NOT NULL CONSTRAINT FK_OrderItems_Products REFERENCES dbo.Products(ProductID),
    Quantity     INT            NOT NULL CONSTRAINT CK_OrderItems_Qty   CHECK (Quantity BETWEEN 1 AND 100),
    UnitPrice    DECIMAL(10,2)  NOT NULL CONSTRAINT CK_OrderItems_Price CHECK (UnitPrice > 0),
    CONSTRAINT PK_OrderItems PRIMARY KEY (OrderID, ProductID)
);

/* ---- Payments: card data = the most sensitive asset ----------------------
   CardNumber is PLAINTEXT here on purpose ("before"); 06_tde.sql encrypts it.
   One payment per order -> UNIQUE(OrderID). */
CREATE TABLE dbo.Payments
(
    PaymentID    INT IDENTITY(1,1)  NOT NULL CONSTRAINT PK_Payments PRIMARY KEY,
    OrderID      INT                NOT NULL CONSTRAINT FK_Payments_Orders REFERENCES dbo.Orders(OrderID)
                                             CONSTRAINT UQ_Payments_Order UNIQUE,
    Amount       DECIMAL(12,2)      NOT NULL CONSTRAINT CK_Payments_Amount CHECK (Amount > 0),
    Method       NVARCHAR(20)       NOT NULL
        CONSTRAINT CK_Payments_Method CHECK (Method IN (N'Card', N'Telebirr', N'CBE Birr', N'Cash on Delivery')),
    CardNumber   VARCHAR(19)        NULL,     -- only for Method = 'Card'
    Status       NVARCHAR(10)       NOT NULL CONSTRAINT DF_Payments_Status DEFAULT (N'Pending')
        CONSTRAINT CK_Payments_Status CHECK (Status IN (N'Pending', N'Completed', N'Failed', N'Refunded')),
    PaidAt       DATETIME2(0)       NOT NULL CONSTRAINT DF_Payments_PaidAt DEFAULT (SYSDATETIME()),
    -- a card number may only exist for card payments
    CONSTRAINT CK_Payments_CardOnlyForCard CHECK (Method = N'Card' OR CardNumber IS NULL)
);

/* ---- AuditLog: who did what, when (accountability / breach detection) ----
   Written ONLY by stored procedures; nobody gets UPDATE/DELETE on it
   (enforced in 03_rbac.sql). */
CREATE TABLE dbo.AuditLog
(
    AuditID      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY,
    EventTime    DATETIME2(3)       NOT NULL CONSTRAINT DF_AuditLog_Time  DEFAULT (SYSDATETIME()),
    EventType    NVARCHAR(30)       NOT NULL,          -- e.g. LOGIN_SUCCESS, LOGIN_FAILED
    AppUsername  NVARCHAR(30)       NULL,              -- website user (if any)
    DbLogin      SYSNAME            NOT NULL CONSTRAINT DF_AuditLog_Login DEFAULT (ORIGINAL_LOGIN()),
    Details      NVARCHAR(400)      NULL
);
GO
PRINT 'Tables created.';
GO

/* ---------------------------------------------------------------------------
   3. PASSWORD HASHING FUNCTION
   ---------------------------------------------------------------------------
   Method: salted, iterated SHA-512 ("key stretching", same idea as PBKDF2).
     hash_0 = SHA512(salt + password)
     hash_i = SHA512(hash_(i-1) + salt + password)   repeated 5,000 times
   Why?
     - SALT (16 random bytes, different per user): two users with the same
       password get different hashes, and pre-computed "rainbow tables"
       become useless.
     - ITERATIONS: one hash is very fast for an attacker's GPU; 5,000 makes
       every single guess 5,000x more expensive (slows brute force).
     - SHA-512 is one-way: you cannot turn the hash back into the password.
   Honest note: in production you would use bcrypt / Argon2 / PBKDF2 from a
   tested library in the application layer. T-SQL has no built-in slow hash,
   so this function shows the same principle inside the database.
   --------------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_HashPassword
(
    @Password NVARCHAR(128),
    @Salt     VARBINARY(16)
)
RETURNS VARBINARY(64)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @PwdBytes VARBINARY(256) = CAST(@Password AS VARBINARY(256));
    DECLARE @Hash     VARBINARY(64)  = HASHBYTES('SHA2_512', @Salt + @PwdBytes);
    DECLARE @i        INT = 1;

    WHILE @i < 5000
    BEGIN
        SET @Hash = HASHBYTES('SHA2_512', @Hash + @Salt + @PwdBytes);
        SET @i += 1;
    END

    RETURN @Hash;
END
GO
PRINT 'Function dbo.fn_HashPassword created.';
GO

/* ---------------------------------------------------------------------------
   4. SAMPLE DATA (realistic Ethiopian e-commerce data, all fictional)
   --------------------------------------------------------------------------- */
INSERT INTO dbo.Staff (FullName, Email, Department, Region, DbUserName) VALUES
 (N'Tsehay Alemu',    N'tsehay@shop.et',  N'Admin',   N'ALL',         N'shop_admin'),
 (N'Abebe Kebede',    N'abebe@shop.et',   N'Sales',   N'Addis Ababa', N'sales_addis'),
 (N'Hana Tadesse',    N'hana@shop.et',    N'Sales',   N'Hawassa',     N'sales_hawassa'),
 (N'Dawit Mengistu',  N'dawit@shop.et',   N'Support', N'ALL',         N'support_dawit'),
 (N'Meron Haile',     N'meron@shop.et',   N'Audit',   N'ALL',         N'auditor_meron');

INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, City, Region) VALUES
 (N'Selam',   N'Getachew', N'selam.g@mail.et',   '+251911234567', N'Addis Ababa', N'Addis Ababa'),
 (N'Yonas',   N'Bekele',   N'yonas.b@mail.et',   '+251922345678', N'Addis Ababa', N'Addis Ababa'),
 (N'Liya',    N'Tesfaye',  N'liya.t@mail.et',    '+251933456789', N'Hawassa',     N'Hawassa'),
 (N'Samuel',  N'Girma',    N'samuel.g@mail.et',  '+251944567890', N'Hawassa',     N'Hawassa'),
 (N'Bethel',  N'Assefa',   N'bethel.a@mail.et',  '+251955678901', N'Bahir Dar',   N'Bahir Dar'),
 (N'Kidus',   N'Wolde',    N'kidus.w@mail.et',   '+251966789012', N'Dire Dawa',   N'Dire Dawa'),
 (N'Mahlet',  N'Desta',    N'mahlet.d@mail.et',  '+251977890123', N'Addis Ababa', N'Addis Ababa'),
 (N'Natnael', N'Abera',    N'natnael.a@mail.et', '+251788901234', N'Bahir Dar',   N'Bahir Dar');

INSERT INTO dbo.Products (SKU, Name, Category, Price, Stock) VALUES
 ('EL-PHN-001', N'Smartphone X10 128GB',       N'Electronics', 18500.00, 25),
 ('EL-LAP-002', N'Laptop Pro 14 inch',         N'Electronics', 65000.00, 8),
 ('EL-EAR-003', N'Wireless Earbuds',           N'Electronics',  2400.00, 60),
 ('CL-HAB-004', N'Habesha Kemis (Traditional)',N'Clothing',     4500.00, 15),
 ('CL-JKT-005', N'Leather Jacket',             N'Clothing',     7800.00, 12),
 ('HM-JEB-006', N'Clay Jebena Coffee Pot',     N'Home',          650.00, 40),
 ('HM-MSB-007', N'Mesob Basket',               N'Home',         1900.00, 20),
 ('BK-FIK-008', N'Fikir Eske Mekabir (Novel)', N'Books',         550.00, 35),
 ('FD-COF-009', N'Yirgacheffe Coffee 1kg',     N'Food',          950.00, 100),
 ('FD-BER-010', N'Berbere Spice 500g',         N'Food',          320.00, 80);

/* Website users. Every sample user gets the demo password from .env,
   hashed with its OWN random salt (CRYPT_GEN_RANDOM = crypto-strong RNG).
   The plaintext is never written into the table. */
DECLARE @DemoPassword NVARCHAR(128) = N'$(DEMO_USER_PASSWORD)';

DECLARE @NewUsers TABLE (Username NVARCHAR(30), Role NVARCHAR(20), CustomerID INT NULL, StaffID INT NULL);
INSERT INTO @NewUsers VALUES
 (N'selam.g',       N'Customer', 1, NULL),
 (N'yonas.b',       N'Customer', 2, NULL),
 (N'liya.t',        N'Customer', 3, NULL),
 (N'samuel.g',      N'Customer', 4, NULL),
 (N'bethel.a',      N'Customer', 5, NULL),
 (N'kidus.w',       N'Customer', 6, NULL),
 (N'admin.tsehay',  N'Admin',    NULL, 1),
 (N'sales.abebe',   N'Sales',    NULL, 2),
 (N'support.dawit', N'Support',  NULL, 4),
 (N'audit.meron',   N'Auditor',  NULL, 5);

INSERT INTO dbo.Users (Username, PasswordSalt, PasswordHash, Role, CustomerID, StaffID)
SELECT u.Username, s.Salt, dbo.fn_HashPassword(@DemoPassword, s.Salt), u.Role, u.CustomerID, u.StaffID
FROM @NewUsers AS u
CROSS APPLY (SELECT CAST(CRYPT_GEN_RANDOM(16) AS VARBINARY(16)) AS Salt) AS s;

/* Orders 1001..1010 with their items; totals are calculated from the items */
INSERT INTO dbo.Orders (CustomerID, OrderDate, Status, ShipRegion) VALUES
 (1, '2026-10-02 09:15', N'Delivered', N'Addis Ababa'),
 (2, '2026-10-05 14:30', N'Delivered', N'Addis Ababa'),
 (3, '2026-10-07 11:05', N'Shipped',   N'Hawassa'),
 (4, '2026-10-11 16:45', N'Paid',      N'Hawassa'),
 (5, '2026-10-15 10:20', N'Delivered', N'Bahir Dar'),
 (6, '2026-10-20 08:55', N'Pending',   N'Dire Dawa'),
 (7, '2026-10-24 19:10', N'Paid',      N'Addis Ababa'),
 (8, '2026-11-01 13:40', N'Shipped',   N'Bahir Dar'),
 (1, '2026-11-10 12:00', N'Paid',      N'Addis Ababa'),
 (3, '2026-11-18 17:25', N'Cancelled', N'Hawassa');

INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT v.OrderID, v.ProductID, v.Quantity, p.Price
FROM (VALUES (1001,1,1),(1001,3,1),(1002,9,3),(1003,4,1),(1003,6,2),
             (1004,2,1),(1005,8,2),(1005,10,4),(1006,5,1),(1007,7,1),
             (1007,9,2),(1008,3,2),(1009,1,1),(1010,6,1)) AS v(OrderID, ProductID, Quantity)
JOIN dbo.Products AS p ON p.ProductID = v.ProductID;

UPDATE o SET TotalAmount = t.Total
FROM dbo.Orders AS o
JOIN (SELECT OrderID, SUM(Quantity * UnitPrice) AS Total FROM dbo.OrderItems GROUP BY OrderID) AS t
  ON t.OrderID = o.OrderID;

/* Payments - card numbers are well-known TEST numbers, not real cards */
INSERT INTO dbo.Payments (OrderID, Amount, Method, CardNumber, Status, PaidAt)
SELECT o.OrderID, o.TotalAmount, v.Method, v.CardNumber, v.Status, DATEADD(MINUTE, 5, o.OrderDate)
FROM (VALUES (1001, N'Card',             '4111111111111111', N'Completed'),
             (1002, N'Telebirr',         NULL,               N'Completed'),
             (1003, N'Card',             '5500000000000004', N'Completed'),
             (1004, N'Card',             '4012888888881881', N'Completed'),
             (1005, N'CBE Birr',         NULL,               N'Completed'),
             (1006, N'Cash on Delivery', NULL,               N'Pending'),
             (1007, N'Card',             '378282246310005',  N'Completed'),
             (1008, N'Telebirr',         NULL,               N'Completed'),
             (1009, N'Card',             '6011111111111117', N'Completed'),
             (1010, N'Card',             '4222222222222',    N'Refunded')) AS v(OrderID, Method, CardNumber, Status)
JOIN dbo.Orders AS o ON o.OrderID = v.OrderID;

INSERT INTO dbo.AuditLog (EventType, AppUsername, Details) VALUES
 (N'SCHEMA_CREATED', NULL, N'ShopDB created and sample data loaded by 01_schema.sql');
GO

/* ---------------------------------------------------------------------------
   5. VERIFY: row counts per table + proof that passwords are not plaintext
   --------------------------------------------------------------------------- */
PRINT '--- Row counts ---';
SELECT 'Staff' AS TableName, COUNT(*) AS Rows FROM dbo.Staff UNION ALL
SELECT 'Customers', COUNT(*) FROM dbo.Customers  UNION ALL
SELECT 'Users',     COUNT(*) FROM dbo.Users      UNION ALL
SELECT 'Products',  COUNT(*) FROM dbo.Products   UNION ALL
SELECT 'Orders',    COUNT(*) FROM dbo.Orders     UNION ALL
SELECT 'OrderItems',COUNT(*) FROM dbo.OrderItems UNION ALL
SELECT 'Payments',  COUNT(*) FROM dbo.Payments   UNION ALL
SELECT 'AuditLog',  COUNT(*) FROM dbo.AuditLog;

PRINT '--- Passwords are stored as salt + hash only (first 3 users) ---';
SELECT TOP (3) Username, Role,
       CONVERT(VARCHAR(34), PasswordSalt, 1)      AS Salt,
       CONVERT(VARCHAR(30), PasswordHash, 1) + '...' AS HashStart
FROM dbo.Users ORDER BY UserID;
GO

/* ---------------------------------------------------------------------------
   6. CONSTRAINT TESTS: each bad INSERT must be REJECTED by the database.
   TRY/CATCH lets the script continue and prints the rejection reason.
   --------------------------------------------------------------------------- */
PRINT '--- Constraint tests (all 4 should be REJECTED) ---';
BEGIN TRY
    INSERT INTO dbo.Products (SKU, Name, Category, Price) VALUES ('X-1', N'Free phone', N'Electronics', -5);
    PRINT 'FAIL: negative price was accepted';
END TRY
BEGIN CATCH PRINT 'OK  CHECK rejected negative price      -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY
    INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, City, Region)
    VALUES (N'Copy', N'Cat', N'selam.g@mail.et', '+251911000000', N'Adama', N'Addis Ababa');
    PRINT 'FAIL: duplicate e-mail was accepted';
END TRY
BEGIN CATCH PRINT 'OK  UNIQUE rejected duplicate e-mail   -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY
    INSERT INTO dbo.Orders (CustomerID, ShipRegion) VALUES (999, N'Addis Ababa');
    PRINT 'FAIL: order for non-existing customer was accepted';
END TRY
BEGIN CATCH PRINT 'OK  FOREIGN KEY rejected customer 999  -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY
    INSERT INTO dbo.Users (Username, PasswordHash, PasswordSalt, Role, CustomerID)
    VALUES (N'bad''user--', 0x00, 0x00, N'Customer', 1);
    PRINT 'FAIL: username with quote was accepted';
END TRY
BEGIN CATCH PRINT 'OK  CHECK rejected username with quote -> ' + ERROR_MESSAGE(); END CATCH;
GO
