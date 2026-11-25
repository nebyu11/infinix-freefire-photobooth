/* ===========================================================================
   07_mfa.sql  -  (OPTIONAL) Multi-Factor Authentication support
   ---------------------------------------------------------------------------
   Run as : administrator, after 06. Safe to run again (CREATE OR ALTER).

   HONEST NOTE: SQL Server LOGINS have no built-in MFA. (MFA for database
   logins exists only with Microsoft Entra ID / Azure SQL.) So MFA is done
   where users actually log in: the WEBSITE, using TOTP = Time-based
   One-Time Passwords (RFC 6238, the 6-digit codes of Google Authenticator).

   FLOW
     1. Something you KNOW : password -> app.sp_Login (05)
     2. Something you HAVE : phone app shows a 6-digit code that changes
                             every 30 s; it is computed from a shared SECRET
                             + the current time. The app checks the code.

   WHERE IS THE SECRET?
     The Flask app encrypts the TOTP secret (Fernet = AES-128-CBC + HMAC)
     with a key that lives only in the app's .env file, and stores only the
     CIPHERTEXT in Users.MfaSecretEnc. A stolen database or backup therefore
     does not reveal anyone's MFA secret (and TDE encrypts it again on disk).

   PROCEDURES (all in schema [app], so the website may call them)
     app.sp_SaveMfaSecret    store the encrypted secret (not yet enabled)
     app.sp_EnableMfa        switch MFA on after the first correct code
     app.sp_GetMfaSecret     fetch the encrypted secret during login step 2
     app.sp_RecordMfaResult  audit every MFA attempt; 5 failures = lockout
   =========================================================================== */

SET NOCOUNT ON;
USE ShopDB;
GO

CREATE OR ALTER PROCEDURE app.sp_SaveMfaSecret
    @UserID    INT,
    @SecretEnc VARBINARY(512)
AS
BEGIN
    SET NOCOUNT ON;
    IF @SecretEnc IS NULL OR DATALENGTH(@SecretEnc) < 32
    BEGIN SELECT 1 AS ResultCode, N'Invalid secret.' AS Message; RETURN; END

    UPDATE dbo.Users SET MfaSecretEnc = @SecretEnc, MfaEnabled = 0
    WHERE UserID = @UserID AND Status = N'Active';

    IF @@ROWCOUNT = 0
    BEGIN SELECT 1 AS ResultCode, N'User not found.' AS Message; RETURN; END

    INSERT dbo.AuditLog (EventType, AppUsername, Details)
    SELECT N'MFA_SETUP_STARTED', Username, N'New TOTP secret stored (encrypted)'
    FROM dbo.Users WHERE UserID = @UserID;
    SELECT 0 AS ResultCode, N'Secret stored.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE app.sp_EnableMfa
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Users SET MfaEnabled = 1
    WHERE UserID = @UserID AND MfaSecretEnc IS NOT NULL;

    INSERT dbo.AuditLog (EventType, AppUsername, Details)
    SELECT N'MFA_ENABLED', Username, N'TOTP verified and enabled'
    FROM dbo.Users WHERE UserID = @UserID AND MfaEnabled = 1;
    SELECT CASE WHEN @@ROWCOUNT = 1 THEN 0 ELSE 1 END AS ResultCode;
END
GO

CREATE OR ALTER PROCEDURE app.sp_GetMfaSecret
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MfaSecretEnc, MfaEnabled, Status
    FROM dbo.Users WHERE UserID = @UserID;
END
GO

CREATE OR ALTER PROCEDURE app.sp_RecordMfaResult
    @UserID  INT,
    @Success BIT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Max INT = 5, @Failed INT;

    IF @Success = 1
    BEGIN
        UPDATE dbo.Users SET FailedAttempts = 0, LastLoginAt = SYSDATETIME() WHERE UserID = @UserID;
        INSERT dbo.AuditLog (EventType, AppUsername, Details)
        SELECT N'MFA_SUCCESS', Username, N'Second factor verified' FROM dbo.Users WHERE UserID = @UserID;
        SELECT 0 AS ResultCode, N'OK' AS Message;
        RETURN;
    END

    -- wrong code: counts towards the same lockout as wrong passwords
    UPDATE dbo.Users
       SET @Failed = FailedAttempts = FailedAttempts + 1,
           Status      = CASE WHEN FailedAttempts + 1 >= @Max THEN N'Locked' ELSE Status END,
           LockedUntil = CASE WHEN FailedAttempts + 1 >= @Max THEN DATEADD(MINUTE, 15, SYSDATETIME()) ELSE LockedUntil END
     WHERE UserID = @UserID;

    INSERT dbo.AuditLog (EventType, AppUsername, Details)
    SELECT CASE WHEN @Failed >= @Max THEN N'ACCOUNT_LOCKED' ELSE N'MFA_FAILED' END,
           Username, N'Wrong one-time code, attempt ' + CAST(@Failed AS NVARCHAR(5))
    FROM dbo.Users WHERE UserID = @UserID;

    SELECT CASE WHEN @Failed >= @Max THEN 2 ELSE 1 END AS ResultCode,
           CASE WHEN @Failed >= @Max THEN N'Account locked after too many failed attempts.'
                ELSE N'Wrong code. Try again.' END AS Message;
END
GO
PRINT 'MFA procedures created: app.sp_SaveMfaSecret, app.sp_EnableMfa, app.sp_GetMfaSecret, app.sp_RecordMfaResult';
GO

/* ---------------------------------------------------------------------------
   QUICK TEST (as the website login) - uses a dummy ciphertext, then resets
   --------------------------------------------------------------------------- */
EXECUTE AS USER = N'shop_app';
DECLARE @uid INT = 7;   -- admin.tsehay
EXEC app.sp_SaveMfaSecret @uid, 0x00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF;
EXEC app.sp_RecordMfaResult @uid, 0;
EXEC app.sp_RecordMfaResult @uid, 1;
REVERT;
-- reset: MFA is enabled for real through the website (see README)
UPDATE dbo.Users SET MfaSecretEnc = NULL, MfaEnabled = 0 WHERE UserID = 7;
SELECT TOP (3) EventType, AppUsername, Details FROM dbo.AuditLog ORDER BY AuditID DESC;
GO
