# ShopDB: E-commerce Database Security (SQL Server)

Practical implementation for the **Database Security, Chapter 2** assignment
(Access Control, Authentication and Data Protection).
Application area: an Ethiopian online shop with customers, products, orders,
payments and staff.

| Requirement (assignment)            | Where it is implemented                                   |
|-------------------------------------|-----------------------------------------------------------|
| 1. Risk identification checklist    | `docs/risk_checklist.md` / `.xlsx`                        |
| 2. Database, tables, constraints, data | `sql/01_schema.sql`                                    |
| 3 + 5. Strong password policy       | `sql/02_password_policy.sql` (+ lockout in `05`)          |
| 4.i RBAC                            | `sql/03_rbac.sql`                                         |
| 4.ii ABAC                           | `sql/04_abac.sql` (Row-Level Security + attributes + masking) |
| 6 + 7. Stored procedures, query hardening, SQL injection | `sql/05_stored_procedures.sql` + `app/` |
| 8. TDE + column encryption + tests  | `sql/06_tde.sql`, `sql/06b_tde_lost_cert_drill.sql`       |
| 9. MFA (optional)                   | `sql/07_mfa.sql` + `app/` (TOTP / Google Authenticator)   |

**Written report to submit:** `docs/ShopDB_Database_Security_Report.docx` (37 pages, 31 figures).
Fill in your name, ID and date on the cover page, then in Word use *File → Save As → PDF*
if a PDF is required.

---

## 1. What you need (Windows 10/11)

| Tool | Why | Get it |
|------|-----|--------|
| **SQL Server 2022 Developer** (free) | the database. *Express does NOT support TDE.* | microsoft.com → SQL Server downloads → "Developer". Choose **Custom** install. On *Database Engine Configuration* choose **Mixed Mode** (SQL Server + Windows authentication) and add your Windows user as administrator. |
| **SSMS** (SQL Server Management Studio) | run the demo queries, take screenshots | microsoft.com → "Download SSMS" |
| **sqlcmd** | the runner script uses it | Usually installed with SQL Server. Check with `sqlcmd -?`. If missing: `winget install sqlcmd` |
| **ODBC Driver 18 for SQL Server** | lets Python talk to SQL Server | Often installed with SSMS. If not, download it from Microsoft ("ODBC Driver 18 for SQL Server"). |
| **Python 3.11+** | the demo web app | python.org (tick **"Add python.exe to PATH"**) |
| A phone with **Google / Microsoft Authenticator** | MFA demo (optional) | app store |

> **macOS / Linux / Docker alternative.** Run SQL Server in Docker:
> `docker run -d --name shopdb-sql -e ACCEPT_EULA=Y -e MSSQL_PID=Developer -e "MSSQL_SA_PASSWORD=<your sa password>" -p 1433:1433 mcr.microsoft.com/mssql/server:2022-latest`
> then use `./run_sql.sh` instead of `run_sql.ps1`. This project was developed and
> tested exactly this way: SQL Server 2022 CU28 Developer, ODBC Driver 18, Python 3.13.

## 2. Configure your secrets

```powershell
cd db-security-ecommerce
copy .env.example .env
notepad .env
```

Replace **every** `Change-Me…` value with your own strong password (12+ characters,
upper case, lower case, digit and symbol). Don't use `"`, `'` or `$` in values.

Generate the two app keys:

```powershell
python -c "import secrets; print(secrets.token_hex(32))"
```

Paste the output as `FLASK_SECRET_KEY`. Then install the app's packages (step 4)
and run this, pasting its output as `MFA_ENCRYPTION_KEY`:

```powershell
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

`.env` is in `.gitignore`. It is never committed, and no `.sql` or `.py` file
contains a real password.

## 3. Build the database (one command)

Open **PowerShell** in the `db-security-ecommerce` folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass      # allow the script for this window only
.\run_sql.ps1                                  # runs 01 -> 07 in order (about 10 s)
.\run_sql.ps1 sql\06b_tde_lost_cert_drill.sql  # optional: "lost certificate" drill
```

* Uses your **Windows login** by default. Add `-SqlAuth` to use `sa` from `.env`.
* A named instance? Add `-Server "localhost\SQLEXPRESS"` (or set `DB_SERVER` in `.env`).
* Start over at any time: `.\run_sql.ps1 sql\00_reset.sql` then `.\run_sql.ps1`.
* Every script can be run again safely (idempotent). `01_schema.sql` **re-creates** ShopDB.

### Order and expected output

| # | Script | What it does | You should see |
|---|--------|--------------|----------------|
| 01 | `01_schema.sql` | DB + 8 tables, constraints, salted hashes, sample data | row counts (Staff 5, Customers 8, Users 10, Products 10, Orders 10, OrderItems 14, Payments 10); 4 × `OK … rejected` constraint tests |
| 02 | `02_password_policy.sql` | SQL login policy + website password rules + history | `OK weak password "shop123" REJECTED`; policy table; `Strong … Result=0`; `Reuse old … Result=1` |
| 03 | `03_rbac.sql` | 7 logins, 5 roles, GRANT/DENY | **permission matrix**: website_app DENIED on every table, ALLOWED on `EXEC app procedure` |
| 04 | `04_abac.sql` | RLS policy + attributes + masking | admin 10 orders, sales_addis 4, sales_hawassa 3; support sees `sXXX@XXXX.com` |
| 05 | `05_stored_procedures.sql` | login, register, search, order procedures | injection payloads → `Invalid username or password`; account locked after 5 attempts; `Products table still exists` |
| 06 | `06_tde.sql` | column encryption, TDE, cert backup, classification | `ShopDB 3 ENCRYPTED AES-256 CERTIFICATE`; admin sees card numbers, sales sees `NULL` |
| 07 | `07_mfa.sql` | MFA procedures | `Secret stored.` / `Wrong code` / `OK` |
| 06b | `06b_tde_lost_cert_drill.sql` | simulate a lost certificate | **Msg 33111 Cannot find server certificate** (expected!) then `RESTORE SUCCEEDED` |

> On Windows the weak-password error number is 15116/15118; on Linux it is 33062.
> The message text is the same.

## 4. Run the web app

```powershell
cd app
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Open **http://127.0.0.1:5000**. The page has a **green (hardened)** and a **red
(vulnerable, lab only)** version of the login and the search.

Sample website accounts all use the `DEMO_USER_PASSWORD` from `.env`:

| Username | Role | Notes |
|----------|------|-------|
| `selam.g` | Customer (Addis Ababa) | has orders 1001, 1009 |
| `liya.t` | Customer (Hawassa) | has orders 1003, 1010 |
| `yonas.b`, `samuel.g`, `bethel.a`, `kidus.w` | Customer | |
| `admin.tsehay` | Admin | good account for the MFA demo |
| `sales.abebe`, `support.dawit`, `audit.meron` | staff | |

**Check everything in 10 seconds.** With the app running, open a second terminal and run:

```powershell
cd app; .\.venv\Scripts\Activate.ps1; pip install requests; python smoke_test.py
```

Expected: `22/22 checks passed`. (It registers one random test customer per run.)

## 5. Live demo in SSMS

Open `sql/99_demo_queries.sql` in SSMS, then highlight one block (D1…D10) at a time
and press **F5**. Each block shows one concept: constraints, hashes, password policy,
RBAC, RLS, masking, TDE, column encryption and the audit log.
`06b_tde_lost_cert_drill.sql` uses `:ON ERROR`, so in SSMS switch on
**Query → SQLCMD Mode** first. It's easier to run it with `run_sql.ps1`.

## 6. Project structure

```
db-security-ecommerce/
├── README.md                 ← you are here
├── .env.example              ← copy to .env (secrets, never committed)
├── run_sql.ps1 / run_sql.sh  ← run the SQL scripts with values from .env
├── sql/
│   ├── 00_reset.sql                 remove everything
│   ├── 01_schema.sql                database, tables, constraints, data
│   ├── 02_password_policy.sql       password policy (logins + website)
│   ├── 03_rbac.sql                  roles, logins, GRANT/DENY
│   ├── 04_abac.sql                  RLS + attributes + dynamic data masking
│   ├── 05_stored_procedures.sql     hardened procedures + tests
│   ├── 06_tde.sql                   TDE, column encryption, classification
│   ├── 06b_tde_lost_cert_drill.sql  certificate loss / restore drill
│   ├── 07_mfa.sql                   MFA procedures (optional)
│   └── 99_demo_queries.sql          live demo blocks for SSMS
├── app/                      ← Flask demo (vulnerable vs hardened) + smoke_test.py
├── docs/                     ← REPORT (.docx), risk checklist, speaker notes, Q&A cheat sheet
├── presentation/             ← slides (.pptx) with speaker notes
└── screenshots/              ← app/ and sql/ result images + SCREENSHOTS.md
```

## 7. Security notes (be ready to explain these)

* **The vulnerable login/search is deliberate** and exists only for the demo. It runs
  only when `ENABLE_VULNERABLE_DEMO=1`, answers only requests from `127.0.0.1`, and
  the app listens only on `127.0.0.1`. Set the flag to `0` after the presentation.
* `legacy_app` (db_datareader + db_datawriter) is a deliberately **over-privileged**
  login that imitates a badly configured app. The hardened app uses `shop_app`,
  which can only `EXECUTE` procedures in schema `app`.
* **Honest limitations.**
  * SQL Server has no feature literally called ABAC. This project builds it from
    Row-Level Security, attributes and `SESSION_CONTEXT`.
  * SQL logins have no MFA, so MFA happens in the app with TOTP.
  * Password hashing in T-SQL uses salted, iterated SHA-512. A production system
    would use bcrypt or Argon2 in the application.
  * Cell-level encryption does not hide data from a `sysadmin`. That needs
    Always Encrypted, which keeps the keys on the client.
* `ShopDB_before_TDE.bak` contains **plaintext card numbers** (that's the point of
  the comparison). Delete it after the demo, and keep the `.cer`/`.pvk` files and
  their password somewhere safe, away from the server.
* `TrustServerCertificate=yes` and `sqlcmd -C` accept SQL Server's self-signed
  certificate. The connection is still encrypted with TLS, but in production you
  would install a trusted certificate.
