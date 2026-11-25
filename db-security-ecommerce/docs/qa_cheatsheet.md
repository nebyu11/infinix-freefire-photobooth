# Q&A cheat sheet: 15 likely questions

Short answers in simple words. Each one points to where in the project you can **show**
the answer, which is often more convincing than talking.

---

**1. What is the difference between TDE and column encryption?**
TDE encrypts the whole database *files* on disk (data, log and backups). It protects
against a stolen disk or a stolen backup, but anyone who may run `SELECT` still sees
normal data, because SQL Server decrypts it automatically. Column (cell-level)
encryption encrypts one column (card numbers). Even users who can `SELECT` the column
only get binary data or `NULL` unless they have permission to use the key.
→ *Show:* `06_tde.sql`, TEST B vs TEST C (admin sees numbers, sales sees NULL).

**2. Why do parameterized queries stop SQL injection?**
With a parameter, the SQL text and the user's data travel **separately**. SQL Server
compiles the query first and only then plugs in the value, so a quote or `OR 1=1`
inside the value is just characters, never code. With string concatenation, the input
becomes part of the SQL text, and the attacker can change its meaning.
→ *Show:* the app's red vs green login (the page prints the SQL it built).

**3. Are stored procedures automatically safe?**
No. A procedure that builds a string and runs `EXEC(@sql)` is just as vulnerable. Mine
use typed parameters, and the one place that needs dynamic SQL (the sort column) uses
an **allow-list**, `QUOTENAME()` and `sp_executesql` with parameters.
→ `05_stored_procedures.sql`, `app.sp_SearchProducts`.

**4. RBAC vs ABAC: what's the difference?**
RBAC gives rights to job roles ("sales may read Orders"). ABAC decides using
attributes of the user, the data and the context ("…only orders whose region equals
my region, and only if I am active"). RBAC works at the table/column level. My ABAC
works at the row level.
→ `04_abac.sql` DEMO 1 and DEMO 3 (changing an attribute changes access, with no role change).

**5. SQL Server doesn't have ABAC. Is your ABAC real?**
Correct, there is no feature literally called ABAC. I implemented the ABAC *model*
with native features: Row-Level Security (a predicate function checks attributes for
every row), attributes in the `Staff` table and in `SESSION_CONTEXT`, plus Dynamic Data
Masking. The decision really is based on attributes, not roles.

**6. What happens if the TDE certificate is lost?**
The encrypted database and **all its backups** can never be opened on another server,
not even by us. That's why the certificate and its private key are backed up to
`.cer` + `.pvk` files with a password and kept apart from the backups.
→ *Show:* `06b_tde_lost_cert_drill.sql`: Msg 33111 without the certificate, success after restoring it.

**7. Why salt and hash passwords instead of encrypting them?**
Hashing is one-way: even the database admin can't turn it back into the password.
Encryption is two-way: whoever steals the key gets every password. The **salt** (16
random bytes per user) makes equal passwords produce different hashes and defeats
rainbow tables. The **5,000 iterations** make every guess 5,000× slower.
In production I'd use bcrypt or Argon2 from a library.

**8. Why not just use `HASHBYTES('SHA2_512', password)` once?**
SHA-512 is designed to be fast: a GPU can try billions per second. Without a salt,
identical passwords have identical hashes. Iterating with a salt fixes both problems.

**9. Is Dynamic Data Masking a security boundary?**
Not on its own. It hides values on the screen, but a user who can run ad-hoc queries
can sometimes infer values (for example `WHERE Email LIKE 'a%'`). That's why I combine
it with RLS and least privilege, and why card numbers are **encrypted**, not just masked.

**10. Why does the website login have no SELECT rights? How do the procedures read tables?**
Ownership chaining: the procedures in schema `app` and the tables in `dbo` have the
same owner (`dbo`), so SQL Server checks only the `EXECUTE` permission on the procedure.
Even if an attacker found a bug, `shop_app` can't read any table directly.
The search procedure uses dynamic SQL, which breaks the chain, so it runs
`WITH EXECUTE AS OWNER`. That's safe because its SQL text is fully controlled.
→ `03_rbac.sql` permission matrix (website_app column).

**11. How does your MFA work, and where is the secret stored?**
TOTP (RFC 6238): the app and the phone share a random secret. Every 30 seconds both
compute a 6-digit code from the secret plus the current time. The secret is
encrypted by the app (Fernet, with a key that is only in `.env`) before it's stored in
`Users.MfaSecretEnc`, so a stolen database doesn't reveal it. Wrong codes count
towards the same lockout as wrong passwords.

**12. Why not MFA for SQL Server logins?**
SQL authentication has no built-in MFA. (MFA for database logins exists with
Microsoft Entra ID, for example in Azure SQL.) Users log in to the website, so that's
where MFA protects them. Staff could use Windows/Entra authentication with MFA.

**13. What does `CHECK_POLICY = ON` actually do?**
SQL Server applies the operating system's password policy to SQL logins: complexity
(at least 8 characters from 3 of 4 character types). On Windows it also applies the
account lockout and minimum length from Local Security Policy. `CHECK_EXPIRATION = ON`
adds password expiry, and `MUST_CHANGE` forces a new password at the first login.
→ `02_password_policy.sql` Part A.

**14. How do you protect the audit log from an attacker who wants to hide their tracks?**
Only the procedures write to it (they insert, nothing else). `UPDATE` and `DELETE` on
`AuditLog` are **DENIED** to every role, including admin, and auditors can only read
it. Next step in production: SQL Server Audit writing to a file or SIEM outside the
database.

**15. Your web shop has a vulnerable login. Isn't that dangerous?**
It's there to *demonstrate* the attack, and it's locked down: it runs only when
`ENABLE_VULNERABLE_DEMO=1`, answers only requests from `127.0.0.1`, the app listens
only on `127.0.0.1`, and it uses a separate login (`legacy_app`). After the
presentation you set the flag to 0.

---

### Bonus quick answers

* **Why SQL Server Developer and not Express?** Express doesn't support TDE. Developer is free and has all the features (not for production use).
* **Data in transit?** The app connects with `Encrypt=yes` (TLS). In the lab the server certificate is self-signed (`TrustServerCertificate=yes`). In production you'd install a trusted certificate.
* **What is `SESSION_CONTEXT`?** Key-value pairs attached to one database connection. After login the app stores `CustomerID` there (read-only), and RLS and the order procedures read it, so a customer can't see or create orders for someone else, even by editing a form.
* **What is the "authenticator" in `ENCRYPTBYKEY`?** An extra value (the PaymentID) mixed into the encryption. If someone copies an encrypted card number to another row, it won't decrypt there (shown in `06_tde.sql` TEST D).
* **Why are the risk ratings correct?** They're my estimates (Likelihood × Impact, 1–3 each) for a typical small online shop. In a real company you'd set them together with the business owner.

### Questions about the web shop

* **How does the staff portal work? Is it safe to log in to SQL Server from a web page?** Staff type their own SQL Server login and password; the portal connects to SQL Server *as that person*, so SQL Server's own RBAC, RLS, masking and key permissions decide what they see. Only the five staff logins are accepted, every failure says "Login failed.", and the password is kept only in the server's memory (never in the cookie) for 30 minutes.
* **The "What does SQL Server let me do?" tests change data?** No. Each test runs inside a transaction that is always rolled back; it only asks SQL Server "may I?".
* **How is the cart protected against injection?** The cart is sent to `app.sp_PlaceOrderCart` as a JSON *parameter*. `OPENJSON … WITH (ProductID INT, Quantity INT)` converts it into a typed table; text that is not a number is rejected. It is never executed as SQL.
* **Could a customer order or look at orders as someone else?** No. The customer number is never sent by the browser: the app puts it in `SESSION_CONTEXT` (read-only) after login, the procedures read it from there, and Row-Level Security (filter + block predicates) enforces it in the database.
* **Where are card numbers entered at checkout?** Nowhere, on purpose: in a real shop a payment gateway (Telebirr, CBE Birr, card processor) handles them, so the shop never stores new card numbers (PCI DSS). The encrypted card numbers in the database are historical sample data for the column-encryption demo.
