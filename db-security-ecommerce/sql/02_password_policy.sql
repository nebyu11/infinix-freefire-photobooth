/* ===========================================================================
   02_password_policy.sql  -  Strong password policy at TWO levels
   ---------------------------------------------------------------------------
   Run as : administrator, after 01_schema.sql. Safe to run again (idempotent).

   LEVEL A - SQL Server LOGINS (people/apps that connect to the server)
     CHECK_POLICY = ON      -> SQL Server applies the OS password policy:
                               complexity (3 of 4 character types, 8+ chars),
                               and on Windows also lockout + minimum length
                               from "Local Security Policy".
     CHECK_EXPIRATION = ON  -> password expires (max password age).
     MUST_CHANGE            -> user must choose a new password at first login
                               (used after an admin resets a password).

   LEVEL B - WEBSITE USERS (rows in dbo.Users)
     SQL Server knows nothing about these, so WE enforce the rules in T-SQL:
       * at least 10 characters (length beats complexity)
       * upper case + lower case + digit + symbol
       * must not contain the username
       * must not be a known common password (blocklist)
       * must not reuse one of the last 3 passwords (password history)
     The rules live in ONE function (dbo.fn_PasswordPolicyErrors) that is
     used by both app.sp_ChangePassword (here) and app.sp_RegisterCustomer (05).
   =========================================================================== */

SET NOCOUNT ON;
USE master;
GO

/* ===========================================================================
   PART A - SQL Server login password policy
   =========================================================================== */
PRINT '=== PART A: SQL Server login policy (CHECK_POLICY / CHECK_EXPIRATION) ===';

-- Remove the demo login from a previous run (idempotent)
IF SUSER_ID(N'policy_demo_login') IS NOT NULL DROP LOGIN policy_demo_login;
GO

-- A1. WEAK password with CHECK_POLICY = ON  -> must be REJECTED
BEGIN TRY
    CREATE LOGIN policy_demo_login WITH PASSWORD = N'shop123',
           CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
    PRINT 'FAIL: weak password "shop123" was accepted';
END TRY
BEGIN CATCH
    PRINT 'OK  weak password "shop123" REJECTED -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- A2. Password equal to the login name -> must be REJECTED
BEGIN TRY
    CREATE LOGIN policy_demo_login WITH PASSWORD = N'policy_demo_login',
           CHECK_POLICY = ON;
    PRINT 'FAIL: password = login name was accepted';
END TRY
BEGIN CATCH
    PRINT 'OK  password = login name REJECTED -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- A3. STRONG password -> ACCEPTED. MUST_CHANGE forces a new password on the
--     first login (MUST_CHANGE requires CHECK_EXPIRATION = ON).
CREATE LOGIN policy_demo_login
    WITH PASSWORD = N'Tq7#vLm2$Rk9Wp' MUST_CHANGE,
         CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
PRINT 'OK  strong password ACCEPTED for policy_demo_login (MUST_CHANGE at first login)';
GO

-- A4. Show the policy settings that SQL Server stores for each login
PRINT '--- Policy flags of SQL logins ---';
SELECT name                                        AS LoginName,
       is_policy_checked                           AS CheckPolicy,
       is_expiration_checked                       AS CheckExpiration,
       LOGINPROPERTY(name, 'IsMustChange')         AS MustChange,
       LOGINPROPERTY(name, 'IsLocked')             AS IsLocked,
       LOGINPROPERTY(name, 'BadPasswordCount')     AS BadPasswordCount,
       LOGINPROPERTY(name, 'DaysUntilExpiration')  AS DaysUntilExpiry
FROM sys.sql_logins
WHERE name IN (N'sa', N'policy_demo_login');
GO

/* NOTE ON ACCOUNT LOCKOUT FOR SQL LOGINS
   With CHECK_POLICY = ON, SQL Server uses the Windows "Account lockout
   policy". On Windows set it in:  secpol.msc -> Account Policies ->
     Password Policy : Minimum password length = 12, complexity = Enabled,
                       Maximum password age = 90 days, history = 5
     Account Lockout : threshold = 5 invalid attempts, duration = 15 min
   A locked login shows LOGINPROPERTY(name,'IsLocked') = 1 and is unlocked by
     ALTER LOGIN <name> WITH PASSWORD = '<new strong pwd>' UNLOCK;
   (SQL Server on Linux/Docker enforces complexity, but has no Windows lockout
   policy; the website accounts below have their own lockout in 05.)       */

/* ===========================================================================
   PART B - Website (application) password policy
   =========================================================================== */
USE ShopDB;
GO
PRINT '';
PRINT '=== PART B: website password policy (enforced in T-SQL) ===';

/* B1. Blocklist of very common passwords (seen in breach lists).
       Real systems use lists with millions of entries. */
IF OBJECT_ID(N'dbo.CommonPasswords', N'U') IS NULL
    CREATE TABLE dbo.CommonPasswords
    (
        PasswordText NVARCHAR(128) NOT NULL CONSTRAINT PK_CommonPasswords PRIMARY KEY
    );
GO
MERGE dbo.CommonPasswords AS t
USING (VALUES (N'password'), (N'password123!'), (N'p@ssw0rd'), (N'p@ssword123'),
              (N'qwerty123!'), (N'welcome@123'), (N'admin@1234'), (N'ethiopia@123'),
              (N'abc12345!'), (N'letmein!23'), (N'iloveyou1!'), (N'shop@12345')) AS s(PasswordText)
ON t.PasswordText = s.PasswordText
WHEN NOT MATCHED THEN INSERT (PasswordText) VALUES (s.PasswordText);
GO

/* B2. Password history: old hashes are kept so a user cannot reuse them */
IF OBJECT_ID(N'dbo.PasswordHistory', N'U') IS NULL
    CREATE TABLE dbo.PasswordHistory
    (
        HistoryID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PasswordHistory PRIMARY KEY,
        UserID       INT               NOT NULL CONSTRAINT FK_PwdHistory_Users REFERENCES dbo.Users(UserID) ON DELETE CASCADE,
        PasswordHash VARBINARY(64)     NOT NULL,
        PasswordSalt VARBINARY(16)     NOT NULL,
        ChangedAt    DATETIME2(0)      NOT NULL CONSTRAINT DF_PwdHistory_ChangedAt DEFAULT (SYSDATETIME())
    );
GO
-- Put every user's CURRENT password into the history (only once)
INSERT INTO dbo.PasswordHistory (UserID, PasswordHash, PasswordSalt)
SELECT u.UserID, u.PasswordHash, u.PasswordSalt
FROM dbo.Users AS u
WHERE NOT EXISTS (SELECT 1 FROM dbo.PasswordHistory h WHERE h.UserID = u.UserID);
GO

/* B3. The policy function. Returns NULL if the password is OK, otherwise a
       list of every rule that failed (so the user knows what to fix).
       COLLATE Latin1_General_100_BIN2 = binary comparison, so [A-Z] really
       means only upper-case letters (the default collation ignores case). */
CREATE OR ALTER FUNCTION dbo.fn_PasswordPolicyErrors
(
    @Password NVARCHAR(128),
    @Username NVARCHAR(30)
)
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @e NVARCHAR(400) = N'';

    IF @Password IS NULL RETURN N'Password is required.';

    IF LEN(@Password) < 10
        SET @e += N'At least 10 characters. ';
    IF @Password COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[A-Z]%'
        SET @e += N'Needs an upper-case letter. ';
    IF @Password COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[a-z]%'
        SET @e += N'Needs a lower-case letter. ';
    IF @Password NOT LIKE N'%[0-9]%'
        SET @e += N'Needs a digit. ';
    IF @Password COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^A-Za-z0-9]%'
        SET @e += N'Needs a symbol (e.g. ! # $ %). ';
    IF @Username IS NOT NULL AND LEN(@Username) >= 3
       AND CHARINDEX(LOWER(@Username), LOWER(@Password)) > 0
        SET @e += N'Must not contain the username. ';
    IF EXISTS (SELECT 1 FROM dbo.CommonPasswords WHERE PasswordText = LOWER(@Password))
        SET @e += N'Too common (found in breach lists). ';

    RETURN NULLIF(RTRIM(@e), N'');
END
GO

/* B4. Change-password procedure.
       Steps: check old password -> check policy -> check history ->
              store new salt + hash -> record history -> audit.
       Returns @Result: 0 = success, 1 = rejected. Messages never reveal
       whether the USERNAME or the OLD PASSWORD was wrong. */
CREATE OR ALTER PROCEDURE app.sp_ChangePassword
    @Username    NVARCHAR(30),
    @OldPassword NVARCHAR(128),
    @NewPassword NVARCHAR(128),
    @Result      INT           OUTPUT,
    @Message     NVARCHAR(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;      -- any runtime error rolls back the whole transaction

    DECLARE @UserID INT, @Salt VARBINARY(16), @Hash VARBINARY(64), @Errors NVARCHAR(400);

    BEGIN TRY
        SELECT @UserID = UserID, @Salt = PasswordSalt, @Hash = PasswordHash
        FROM dbo.Users
        WHERE Username = @Username AND Status = N'Active';

        -- 1. verify the old password (same generic message for both failures)
        IF @UserID IS NULL OR dbo.fn_HashPassword(@OldPassword, @Salt) <> @Hash
        BEGIN
            SELECT @Result = 1, @Message = N'Invalid username or current password.';
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'PWD_CHANGE_DENIED', LEFT(@Username, 30), N'Wrong current password or unknown user');
            RETURN;
        END

        -- 2. policy rules
        SET @Errors = dbo.fn_PasswordPolicyErrors(@NewPassword, @Username);
        IF @Errors IS NOT NULL
        BEGIN
            SELECT @Result = 1, @Message = N'Password rejected: ' + @Errors;
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'PWD_POLICY_REJECTED', @Username, N'New password failed policy');
            RETURN;
        END

        -- 3. history: compare with the last 3 passwords (each has its own salt)
        IF EXISTS (SELECT 1
                   FROM (SELECT TOP (3) PasswordHash, PasswordSalt
                         FROM dbo.PasswordHistory
                         WHERE UserID = @UserID
                         ORDER BY ChangedAt DESC, HistoryID DESC) AS last3
                   WHERE dbo.fn_HashPassword(@NewPassword, last3.PasswordSalt) = last3.PasswordHash)
        BEGIN
            SELECT @Result = 1, @Message = N'Password rejected: you used it recently (last 3 passwords).';
            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'PWD_POLICY_REJECTED', @Username, N'Password reuse');
            RETURN;
        END

        -- 4. store the new password: NEW random salt + hash
        DECLARE @NewSalt VARBINARY(16) = CAST(CRYPT_GEN_RANDOM(16) AS VARBINARY(16));
        DECLARE @NewHash VARBINARY(64) = dbo.fn_HashPassword(@NewPassword, @NewSalt);

        BEGIN TRANSACTION;
            UPDATE dbo.Users
               SET PasswordSalt = @NewSalt, PasswordHash = @NewHash,
                   PasswordChangedAt = SYSDATETIME(), FailedAttempts = 0
             WHERE UserID = @UserID;

            INSERT dbo.PasswordHistory (UserID, PasswordHash, PasswordSalt)
            VALUES (@UserID, @NewHash, @NewSalt);

            INSERT dbo.AuditLog (EventType, AppUsername, Details)
            VALUES (N'PWD_CHANGED', @Username, N'Password changed successfully');
        COMMIT TRANSACTION;

        SELECT @Result = 0, @Message = N'Password changed successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        -- log the technical details for admins, show a generic message to the user
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        VALUES (N'ERROR', LEFT(@Username, 30), LEFT(N'sp_ChangePassword: ' + ERROR_MESSAGE(), 400));
        SELECT @Result = 1, @Message = N'Something went wrong. Please try again later.';
    END CATCH
END
GO
PRINT 'Objects created: CommonPasswords, PasswordHistory, fn_PasswordPolicyErrors, sp_ChangePassword';
GO

/* ===========================================================================
   PART B DEMO
   =========================================================================== */
PRINT '';
PRINT '--- B-demo 1: the policy function checks several candidate passwords ---';
SELECT Candidate,
       ISNULL(dbo.fn_PasswordPolicyErrors(Candidate, N'natnael.a'), N'ACCEPTED') AS PolicyResult
FROM (VALUES (N'abc'),
             (N'natnael2026'),
             (N'Password123!'),
             (N'alllowercase1!'),
             (N'Natnael.a#2026'),
             (N'Blue-Coffee#Hawassa7')) AS t(Candidate);
GO

/* Demo account: Natnael (customer 8) gets a website account for this test.
   Its passwords below are TEST fixtures for the lab only. */
DELETE FROM dbo.Users WHERE Username = N'natnael.a';     -- idempotent re-run
DECLARE @s VARBINARY(16) = CAST(CRYPT_GEN_RANDOM(16) AS VARBINARY(16));
INSERT dbo.Users (Username, PasswordSalt, PasswordHash, Role, CustomerID)
VALUES (N'natnael.a', @s, dbo.fn_HashPassword(N'Start#Pass2026', @s), N'Customer', 8);
INSERT dbo.PasswordHistory (UserID, PasswordHash, PasswordSalt)
SELECT UserID, PasswordHash, PasswordSalt FROM dbo.Users WHERE Username = N'natnael.a';
GO

PRINT '--- B-demo 2: change password through the procedure ---';
DECLARE @r INT, @m NVARCHAR(400);

EXEC app.sp_ChangePassword N'natnael.a', N'Start#Pass2026', N'natnael123', @r OUTPUT, @m OUTPUT;
PRINT 'Weak "natnael123"          -> Result=' + CAST(@r AS VARCHAR) + '  ' + @m;

EXEC app.sp_ChangePassword N'natnael.a', N'WrongOld#123', N'Blue-Coffee#Hawassa7', @r OUTPUT, @m OUTPUT;
PRINT 'Wrong current password     -> Result=' + CAST(@r AS VARCHAR) + '  ' + @m;

EXEC app.sp_ChangePassword N'natnael.a', N'Start#Pass2026', N'Blue-Coffee#Hawassa7', @r OUTPUT, @m OUTPUT;
PRINT 'Strong "Blue-Coffee#Hawassa7" -> Result=' + CAST(@r AS VARCHAR) + '  ' + @m;

EXEC app.sp_ChangePassword N'natnael.a', N'Blue-Coffee#Hawassa7', N'Start#Pass2026', @r OUTPUT, @m OUTPUT;
PRINT 'Reuse old "Start#Pass2026" -> Result=' + CAST(@r AS VARCHAR) + '  ' + @m;
GO

PRINT '--- Audit trail of the demo ---';
SELECT TOP (4) EventType, AppUsername, Details
FROM dbo.AuditLog WHERE AppUsername = N'natnael.a' ORDER BY AuditID;
GO
