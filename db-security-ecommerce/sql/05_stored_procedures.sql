/* ===========================================================================
   05_stored_procedures.sql  -  Hardened stored procedures vs SQL injection
   ---------------------------------------------------------------------------
   Run as : administrator, after 04. Safe to run again (CREATE OR ALTER).

   WHAT IS SQL INJECTION?
     A vulnerable app glues user input into the SQL text:
        "SELECT ... WHERE Username = '" + input + "'"
     Input  ' OR '1'='1' --   turns the query into  ... WHERE Username = ''
     OR '1'='1' --'  -> the WHERE is always true and the rest is a comment.

   HOW THESE PROCEDURES STOP IT (query hardening techniques)
     1. Typed PARAMETERS: input is passed as DATA, never as SQL code. SQL
        Server compiles the query first, then plugs the value in, so quotes
        and keywords inside the value have no special meaning.
     2. INPUT VALIDATION (allow-lists): length, character set, format and
        ranges are checked before anything else happens.
     3. Dynamic SQL ONLY where unavoidable (sort column), built with
        sp_executesql + parameters, an allow-list and QUOTENAME().
     4. TRY/CATCH: real error details go to the AuditLog for admins; the
        user only sees a generic message (no table names, no SQL text).
     5. Least privilege: the website login can ONLY execute schema [app]
        (03_rbac.sql), so even a successful injection could not read tables.
     6. Lockout: 5 wrong passwords lock the account for 15 minutes.
   =========================================================================== */

SET NOCOUNT ON;
USE ShopDB;
GO

/* ===========================================================================
   1. app.sp_Login
      Returns ONE row: ResultCode (0 = OK, 1 = invalid, 2 = locked),
      a user-safe Message, and the user's details only on success.
   =========================================================================== */
CREATE OR ALTER PROCEDURE app.sp_Login
    @Username NVARCHAR(30),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MaxFailedAttempts INT = 5,       -- lockout threshold
            @LockMinutes       INT = 15;      -- lockout duration

    DECLARE @UserID INT, @Salt VARBINARY(16), @Hash VARBINARY(64), @Status NVARCHAR(10),
            @Failed INT, @LockedUntil DATETIME2(0), @Now DATETIME2(0) = SYSDATETIME();
    DECLARE @Generic NVARCHAR(100) = N'Invalid username or password.';

    BEGIN TRY
        -- (1) validation: wrong shapes are rejected without touching the table
        IF @Username IS NULL OR @Password IS NULL
           OR LEN(@Username) < 3
           OR @Username LIKE N'%[^a-zA-Z0-9._]%'     -- allow-list of characters
        BEGIN
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'LOGIN_REJECTED_INPUT', NULL,
                    LEFT(N'Invalid username format: ' + ISNULL(@Username, N'NULL'), 400));
            SELECT 1 AS ResultCode, @Generic AS Message;
            RETURN;
        END

        -- (2) look the user up - @Username is a PARAMETER, never part of SQL text
        SELECT @UserID = UserID, @Salt = PasswordSalt, @Hash = PasswordHash,
               @Status = Status, @Failed = FailedAttempts, @LockedUntil = LockedUntil
        FROM dbo.Users
        WHERE Username = @Username;

        IF @UserID IS NULL
        BEGIN
            -- hash anyway so "unknown user" takes as long as "wrong password"
            -- (an attacker cannot discover valid usernames by timing)
            DECLARE @dummy VARBINARY(64) = dbo.fn_HashPassword(@Password, 0x00);
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'LOGIN_FAILED', @Username, N'Unknown username');
            SELECT 1 AS ResultCode, @Generic AS Message;
            RETURN;
        END

        -- (3) lockout: still locked?
        IF @Status = N'Locked' AND @LockedUntil > @Now
        BEGIN
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'LOGIN_BLOCKED_LOCKED', @Username, N'Login attempt while locked');
            SELECT 2 AS ResultCode,
                   N'Account locked after too many failed attempts. Try again later.' AS Message;
            RETURN;
        END
        -- lock period is over -> unlock automatically
        IF @Status = N'Locked'
        BEGIN
            UPDATE dbo.Users SET Status = N'Active', FailedAttempts = 0, LockedUntil = NULL
            WHERE UserID = @UserID;
            SELECT @Status = N'Active', @Failed = 0;
        END

        IF @Status <> N'Active'   -- Disabled accounts
        BEGIN
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'LOGIN_FAILED', @Username, N'Account disabled');
            SELECT 1 AS ResultCode, @Generic AS Message;
            RETURN;
        END

        -- (4) check the password: hash the attempt with the user's salt
        IF dbo.fn_HashPassword(@Password, @Salt) <> @Hash
        BEGIN
            SET @Failed += 1;
            UPDATE dbo.Users
               SET FailedAttempts = @Failed,
                   Status      = CASE WHEN @Failed >= @MaxFailedAttempts THEN N'Locked' ELSE Status END,
                   LockedUntil = CASE WHEN @Failed >= @MaxFailedAttempts
                                      THEN DATEADD(MINUTE, @LockMinutes, @Now) ELSE NULL END
             WHERE UserID = @UserID;

            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (CASE WHEN @Failed >= @MaxFailedAttempts THEN N'ACCOUNT_LOCKED' ELSE N'LOGIN_FAILED' END,
                    @Username, N'Wrong password, attempt ' + CAST(@Failed AS NVARCHAR(5)));

            IF @Failed >= @MaxFailedAttempts
                SELECT 2 AS ResultCode,
                       N'Account locked after too many failed attempts. Try again later.' AS Message;
            ELSE
                SELECT 1 AS ResultCode, @Generic AS Message;
            RETURN;
        END

        -- (5) success
        UPDATE dbo.Users SET FailedAttempts = 0, LastLoginAt = @Now WHERE UserID = @UserID;
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        VALUES (N'LOGIN_SUCCESS', @Username, N'Password verified');

        SELECT 0 AS ResultCode, N'Login successful.' AS Message,
               UserID, Username, Role, CustomerID, MfaEnabled, MfaSecretEnc
        FROM dbo.Users WHERE UserID = @UserID;
    END TRY
    BEGIN CATCH
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        VALUES (N'ERROR', LEFT(@Username, 30), LEFT(N'sp_Login: ' + ERROR_MESSAGE(), 400));
        SELECT 1 AS ResultCode, N'Something went wrong. Please try again later.' AS Message;
    END CATCH
END
GO

/* ===========================================================================
   2. app.sp_RegisterCustomer  -  validates EVERYTHING, then inserts the
      customer + website account in ONE transaction (all or nothing).
   =========================================================================== */
CREATE OR ALTER PROCEDURE app.sp_RegisterCustomer
    @Username  NVARCHAR(30),
    @Password  NVARCHAR(128),
    @FirstName NVARCHAR(50),
    @LastName  NVARCHAR(50),
    @Email     NVARCHAR(150),
    @Phone     VARCHAR(20),
    @City      NVARCHAR(50),
    @Region    NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Errors NVARCHAR(400);

    -- trim spaces so " abc " and "abc" are treated the same
    SELECT @Username = LTRIM(RTRIM(@Username)), @Email = LOWER(LTRIM(RTRIM(@Email))),
           @FirstName = LTRIM(RTRIM(@FirstName)), @LastName = LTRIM(RTRIM(@LastName)),
           @Phone = LTRIM(RTRIM(@Phone)), @City = LTRIM(RTRIM(@City));

    -- (1) input validation with allow-lists (reject, never "fix" bad input)
    IF @Username IS NULL OR LEN(@Username) NOT BETWEEN 3 AND 30 OR @Username LIKE N'%[^a-zA-Z0-9._]%'
        SET @Errors = N'Username: 3-30 characters, only letters, digits, dot, underscore.';
    ELSE IF @FirstName IS NULL OR @LastName IS NULL OR LEN(@FirstName) = 0 OR LEN(@LastName) = 0
         OR @FirstName LIKE N'%[0-9<>;"=]%' OR @LastName LIKE N'%[0-9<>;"=]%'
        SET @Errors = N'First and last name are required and may not contain digits or symbols.';
    ELSE IF @Email IS NULL OR @Email NOT LIKE N'%_@_%._%' OR @Email LIKE N'%[ <>;''"]%'
        SET @Errors = N'Please enter a valid e-mail address.';
    ELSE IF @Phone IS NULL OR @Phone NOT LIKE '+251[79][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
        SET @Errors = N'Phone must look like +2519XXXXXXXX.';
    ELSE IF @Region IS NULL OR @Region NOT IN (N'Addis Ababa', N'Hawassa', N'Bahir Dar', N'Dire Dawa')
        SET @Errors = N'Please choose a valid region.';
    ELSE
        SET @Errors = dbo.fn_PasswordPolicyErrors(@Password, @Username);   -- policy from 02

    IF @Errors IS NOT NULL
    BEGIN
        SELECT 1 AS ResultCode, N'Registration rejected: ' + @Errors AS Message;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
            INSERT dbo.Customers (FirstName, LastName, Email, Phone, City, Region)
            VALUES (@FirstName, @LastName, @Email, @Phone, ISNULL(NULLIF(@City, N''), @Region), @Region);
            DECLARE @CustomerID INT = SCOPE_IDENTITY();

            DECLARE @Salt VARBINARY(16) = CAST(CRYPT_GEN_RANDOM(16) AS VARBINARY(16));
            DECLARE @Hash VARBINARY(64) = dbo.fn_HashPassword(@Password, @Salt);

            INSERT dbo.Users (Username, PasswordHash, PasswordSalt, Role, CustomerID)
            VALUES (@Username, @Hash, @Salt, N'Customer', @CustomerID);

            INSERT dbo.PasswordHistory (UserID, PasswordHash, PasswordSalt)
            VALUES (SCOPE_IDENTITY(), @Hash, @Salt);

            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'REGISTERED', @Username, N'New customer account created');
        COMMIT TRANSACTION;

        SELECT 0 AS ResultCode, N'Account created. You can now log in.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        -- 2627/2601 = UNIQUE constraint: the database itself refuses duplicates
        IF ERROR_NUMBER() IN (2627, 2601)
            SELECT 1 AS ResultCode, N'That username or e-mail is already registered.' AS Message;
        ELSE
        BEGIN
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'ERROR', LEFT(@Username, 30), LEFT(N'sp_RegisterCustomer: ' + ERROR_MESSAGE(), 400));
            SELECT 1 AS ResultCode, N'Something went wrong. Please try again later.' AS Message;
        END
    END CATCH
END
GO

/* ===========================================================================
   3. app.sp_SearchProducts  -  the one place where DYNAMIC SQL is needed:
      the user may choose the SORT column, and a column name cannot be
      passed as a parameter. Safe recipe:
        a) the column name must be in an ALLOW-LIST (else default 'Name')
        b) it is wrapped with QUOTENAME() -> [Name]
        c) all VALUES (search text, category, max price) are still passed
           as parameters through sp_executesql - never concatenated.
      EXECUTE AS OWNER: dynamic SQL breaks "ownership chaining", so without
      this the website login (which has no SELECT rights) could not read
      Products. It is safe here because the SQL text is fully controlled.
   =========================================================================== */
CREATE OR ALTER PROCEDURE app.sp_SearchProducts
    @SearchTerm NVARCHAR(50)  = NULL,
    @Category   NVARCHAR(30)  = NULL,
    @MaxPrice   DECIMAL(10,2) = NULL,
    @SortBy     NVARCHAR(20)  = N'Name',
    @SortDir    NVARCHAR(4)   = N'ASC'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- (a) allow-lists for identifiers / keywords
        IF @SortBy NOT IN (N'Name', N'Price', N'Category', N'Stock') SET @SortBy = N'Name';
        IF UPPER(@SortDir) NOT IN (N'ASC', N'DESC')                  SET @SortDir = N'ASC';
        IF @MaxPrice IS NOT NULL AND @MaxPrice <= 0                  SET @MaxPrice = NULL;

        -- escape LIKE wildcards so "%" or "_" typed by the user are literal
        DECLARE @Pattern NVARCHAR(160) = NULL;
        IF NULLIF(LTRIM(RTRIM(@SearchTerm)), N'') IS NOT NULL
            SET @Pattern = N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@SearchTerm)),
                                 N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

        -- (b)+(c) SQL text contains NO user values, only @parameters
        DECLARE @sql NVARCHAR(MAX) = N'
            SELECT ProductID, SKU, Name, Category, Price, Stock
            FROM dbo.Products
            WHERE IsActive = 1
              AND (@pPattern  IS NULL OR Name LIKE @pPattern)
              AND (@pCategory IS NULL OR Category = @pCategory)
              AND (@pMaxPrice IS NULL OR Price <= @pMaxPrice)
            ORDER BY ' + QUOTENAME(@SortBy) + N' ' + UPPER(@SortDir) + N';';

        EXEC sys.sp_executesql
             @sql,
             N'@pPattern NVARCHAR(160), @pCategory NVARCHAR(30), @pMaxPrice DECIMAL(10,2)',
             @pPattern = @Pattern, @pCategory = @Category, @pMaxPrice = @MaxPrice;
    END TRY
    BEGIN CATCH
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        VALUES (N'ERROR', NULL, LEFT(N'sp_SearchProducts: ' + ERROR_MESSAGE(), 400));
        -- return an empty result with the same columns instead of an error
        SELECT TOP (0) ProductID, SKU, Name, Category, Price, Stock FROM dbo.Products;
    END CATCH
END
GO

/* ===========================================================================
   4. app.sp_PlaceOrder  -  the customer is NOT a parameter!
      The website stores the logged-in customer in SESSION_CONTEXT right
      after login; the procedure reads it from there. So nobody can place
      (or view) orders for another customer by changing a form field
      ("IDOR" attack). The RLS BLOCK predicate (04) enforces the same rule.
   =========================================================================== */
CREATE OR ALTER PROCEDURE app.sp_PlaceOrder
    @ProductID     INT,
    @Quantity      INT,
    @PaymentMethod NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CustomerID INT = CAST(SESSION_CONTEXT(N'CustomerID') AS INT);
    DECLARE @Price DECIMAL(10,2), @Region NVARCHAR(30), @OrderID INT;

    -- validation
    IF @CustomerID IS NULL
    BEGIN SELECT 1 AS ResultCode, N'Please log in as a customer first.' AS Message, NULL AS OrderID; RETURN; END
    IF @Quantity IS NULL OR @Quantity NOT BETWEEN 1 AND 10
    BEGIN SELECT 1 AS ResultCode, N'Quantity must be between 1 and 10.' AS Message, NULL AS OrderID; RETURN; END
    IF @PaymentMethod IS NULL OR @PaymentMethod NOT IN (N'Card', N'Telebirr', N'CBE Birr', N'Cash on Delivery')
    BEGIN SELECT 1 AS ResultCode, N'Unknown payment method.' AS Message, NULL AS OrderID; RETURN; END

    BEGIN TRY
        BEGIN TRANSACTION;
            -- take stock and read the price in one atomic step
            UPDATE dbo.Products
               SET Stock = Stock - @Quantity, @Price = Price
             WHERE ProductID = @ProductID AND IsActive = 1 AND Stock >= @Quantity;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 1 AS ResultCode, N'Product not available in that quantity.' AS Message, NULL AS OrderID;
                RETURN;
            END

            -- RLS lets the website see ONLY this customer's own row
            SELECT @Region = Region FROM dbo.Customers WHERE CustomerID = @CustomerID;

            INSERT dbo.Orders (CustomerID, Status, ShipRegion, TotalAmount)
            VALUES (@CustomerID,
                    CASE WHEN @PaymentMethod = N'Cash on Delivery' THEN N'Pending' ELSE N'Paid' END,
                    @Region, @Price * @Quantity);
            SET @OrderID = SCOPE_IDENTITY();

            INSERT dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
            VALUES (@OrderID, @ProductID, @Quantity, @Price);

            -- card numbers are NEVER accepted here: a payment gateway handles
            -- cards (PCI DSS). We only record the method and amount.
            INSERT dbo.Payments (OrderID, Amount, Method, Status)
            VALUES (@OrderID, @Price * @Quantity, @PaymentMethod,
                    CASE WHEN @PaymentMethod = N'Cash on Delivery' THEN N'Pending' ELSE N'Completed' END);

            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'ORDER_PLACED', NULL, N'Customer ' + CAST(@CustomerID AS NVARCHAR(10))
                    + N' placed order ' + CAST(@OrderID AS NVARCHAR(10)));
        COMMIT TRANSACTION;

        SELECT 0 AS ResultCode, N'Order placed successfully.' AS Message, @OrderID AS OrderID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        VALUES (N'ERROR', NULL, LEFT(N'sp_PlaceOrder: ' + ERROR_MESSAGE(), 400));
        SELECT 1 AS ResultCode, N'Something went wrong. Please try again later.' AS Message, NULL AS OrderID;
    END CATCH
END
GO

/* ===========================================================================
   5. app.sp_GetMyOrders  -  deliberately has NO "WHERE CustomerID = ..."
      Row-Level Security (04) adds that filter automatically, based on the
      session attribute. This proves RLS works even if a developer forgets.
   =========================================================================== */
CREATE OR ALTER PROCEDURE app.sp_GetMyOrders
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.OrderDate, o.Status, o.ShipRegion, o.TotalAmount,
           STRING_AGG(CAST(CONCAT(oi.Quantity, N' x ', p.Name) AS NVARCHAR(MAX)), N', ') AS Items
    FROM dbo.Orders AS o
    JOIN dbo.OrderItems AS oi ON oi.OrderID = o.OrderID
    JOIN dbo.Products   AS p  ON p.ProductID = oi.ProductID
    GROUP BY o.OrderID, o.OrderDate, o.Status, o.ShipRegion, o.TotalAmount
    ORDER BY o.OrderDate DESC;
END
GO
PRINT 'Procedures created: app.sp_Login, app.sp_RegisterCustomer, app.sp_SearchProducts, app.sp_PlaceOrder, app.sp_GetMyOrders';
GO

/* ===========================================================================
   TESTS - every test runs AS THE WEBSITE LOGIN (shop_app) to prove the
   procedures work with least privilege.
   =========================================================================== */
EXECUTE AS USER = N'shop_app';
GO
PRINT '';
PRINT '=== TEST 1: normal login (correct password) ===';
EXEC app.sp_Login N'selam.g', N'$(DEMO_USER_PASSWORD)';

PRINT '=== TEST 2: injection payloads as username - treated as plain text ===';
EXEC app.sp_Login N''' OR ''1''=''1'' --', N'anything';
EXEC app.sp_Login N'admin.tsehay''--',      N'anything';

PRINT '=== TEST 3: brute force - 5 wrong passwords lock the account ===';
DECLARE @i INT = 1;
WHILE @i <= 5 BEGIN EXEC app.sp_Login N'yonas.b', N'Guess#12345'; SET @i += 1; END
PRINT 'Now the CORRECT password is also refused while locked:';
EXEC app.sp_Login N'yonas.b', N'$(DEMO_USER_PASSWORD)';
GO
REVERT;
GO
-- admin unlocks the account so the live demo can use it again
UPDATE dbo.Users SET Status = N'Active', FailedAttempts = 0, LockedUntil = NULL WHERE Username = N'yonas.b';
PRINT '(admin unlocked yonas.b for the demo)';
GO

EXECUTE AS USER = N'shop_app';
PRINT '=== TEST 4: product search ===';
PRINT 'a) normal search "coffee", sorted by price:';
EXEC app.sp_SearchProducts @SearchTerm = N'coffee', @SortBy = N'Price';
PRINT 'b) UNION injection in the search box -> just text, 0 rows:';
EXEC app.sp_SearchProducts @SearchTerm = N''' UNION SELECT UserID, Username, Role, Role, 0, 0 FROM dbo.Users --';
PRINT 'c) injection in the SORT column -> not in allow-list, falls back to Name:';
EXEC app.sp_SearchProducts @SearchTerm = N'e', @Category = N'Food', @SortBy = N'Price; DROP TABLE dbo.Products; --';
PRINT 'd) direct SELECT on the table by the website login -> DENIED:';
BEGIN TRY
    SELECT TOP (1) Name FROM dbo.Products;
END TRY
BEGIN CATCH PRINT '   ' + ERROR_MESSAGE(); END CATCH;
REVERT;
GO
SELECT CASE WHEN OBJECT_ID(N'dbo.Products') IS NOT NULL THEN 'Products table still exists' END AS AfterInjectionTests;
GO

EXECUTE AS USER = N'shop_app';
PRINT '=== TEST 5: registration ===';
EXEC app.sp_RegisterCustomer N'mekdes.t', N'mekdes123', N'Mekdes', N'Tilahun', N'mekdes.t@mail.et',
                             '+251912121212', N'Adama', N'Addis Ababa';
EXEC app.sp_RegisterCustomer N'mekdes.t', N'Green#Tea2026', N'Mekdes', N'Tilahun', N'mekdes.t@mail.et',
                             '+251912121212', N'Adama', N'Addis Ababa';
EXEC app.sp_RegisterCustomer N'mekdes.t2', N'Green#Tea2026', N'Mekdes', N'Tilahun', N'mekdes.t@mail.et',
                             '+251912121212', N'Adama', N'Addis Ababa';
EXEC app.sp_RegisterCustomer N'x''; DROP TABLE dbo.Users;--', N'Green#Tea2026', N'X', N'Y', N'x@y.et',
                             '+251912121213', N'Adama', N'Addis Ababa';
REVERT;
GO

PRINT '=== TEST 6: orders use the SESSION attribute (customer 3 = Liya) ===';
EXECUTE AS USER = N'shop_app';
EXEC sys.sp_set_session_context @key = N'CustomerID', @value = 3;
EXEC app.sp_PlaceOrder @ProductID = 9, @Quantity = 2, @PaymentMethod = N'Telebirr';
EXEC app.sp_PlaceOrder @ProductID = 2, @Quantity = 50, @PaymentMethod = N'Card';
PRINT 'Liya''s orders (procedure has no WHERE clause - RLS filters):';
EXEC app.sp_GetMyOrders;
PRINT 'Switch the session to customer 1 (Selam) - different rows:';
EXEC sys.sp_set_session_context @key = N'CustomerID', @value = 1;
EXEC app.sp_GetMyOrders;
EXEC sys.sp_set_session_context @key = N'CustomerID', @value = NULL;
REVERT;
GO

PRINT '=== Latest audit log entries ===';
SELECT TOP (12) AuditID, EventType, AppUsername, LEFT(Details, 70) AS Details
FROM dbo.AuditLog ORDER BY AuditID DESC;
GO
