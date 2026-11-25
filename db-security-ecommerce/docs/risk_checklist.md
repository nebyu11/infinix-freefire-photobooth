# Risk Identification Checklist: E-commerce Database ("ShopDB")

**Application area:** an online shop that stores customers, products, orders,
payments, and staff/admin accounts in Microsoft SQL Server.

## How the risk rating is calculated

Each risk gets a score from 1 to 3 for **Likelihood** (how probable the attack is)
and for **Impact** (how much damage it would cause):

| Level  | Score |
|--------|-------|
| Low    | 1     |
| Medium | 2     |
| High   | 3     |

**Risk score = Likelihood × Impact** (from 1 to 9):

| Score | Risk Rating |
|-------|-------------|
| 9     | Critical    |
| 6     | High        |
| 3–4   | Medium      |
| 1–2   | Low         |

Critical and High risks must be fixed first. Every mitigation below is a
control that this project **actually implements**. The last column names the
script where it is implemented.

## Checklist

| # | Asset | Threat | Vulnerability | Likelihood | Impact | Risk Rating | Mitigation (implemented in) |
|---|-------|--------|---------------|------------|--------|-------------|-----------------------------|
| 1 | Customer records (name, email, phone, address) | Unauthorized access / account takeover | Weak or reused passwords, no lockout after failed logins | High | High | **Critical** (9) | Strong password policy + account lockout + MFA (`02_password_policy.sql`, `05_stored_procedures.sql`, `07_mfa.sql`) |
| 2 | Customer, order and user tables | SQL injection through the login/search form | App builds SQL by joining strings with user input | High | High | **Critical** (9) | Stored procedures with typed parameters, input validation, parameterized queries in the app (`05_stored_procedures.sql`, `app/`) |
| 3 | Payment / card data | Theft or disclosure, including by insiders (DBAs, support staff) | Card numbers stored as readable plaintext | Medium | High | **High** (6) | Column-level encryption with `ENCRYPTBYKEY` + Dynamic Data Masking (`06_tde.sql`, `04_abac.sql`) |
| 4 | Database files (.mdf/.ldf) and backups (.bak) | Stolen disk or stolen backup file opened on another server | Data files and backups are not encrypted at rest | Medium | High | **High** (6) | Transparent Data Encryption (TDE) (`06_tde.sql`) |
| 5 | User credentials (Users table) | Offline password cracking after a data leak | Passwords stored in plaintext or as unsalted hashes | Medium | High | **High** (6) | Salted hashes only, never plaintext (`01_schema.sql`, `05_stored_procedures.sql`) |
| 6 | Admin / privileged accounts (`sa`, `db_owner`) | Privilege abuse or escalation; full DB takeover if the app is hacked | App connects as `sa`/`db_owner`; every user has too many rights | Medium | High | **High** (6) | RBAC with least privilege: app login can only EXECUTE procedures, no direct table access (`03_rbac.sql`) |
| 7 | Orders and customer data seen by staff | Insider browses orders outside their job (other region / other customers) | Every staff member can read every row | High | Medium | **High** (6) | ABAC via Row-Level Security using user attributes (region, customer id) (`04_abac.sql`) |
| 8 | Product catalog and prices | Unauthorized price or stock change (fraud) | Too many accounts have UPDATE rights on Products | Medium | Medium | Medium (4) | RBAC: only the admin role may change prices; sales/support are DENIED (`03_rbac.sql`) |
| 9 | TDE certificate and encryption keys | Key loss, so encrypted backups can never be restored | Certificate and private key not backed up | Low | High | Medium (3) | Back up certificate + private key with a password, store them apart from the data backups, test a restore (`06_tde.sql`) |
| 10 | Audit log (AuditLog table) | Attacker deletes or edits log rows to hide their tracks | Log table writable by application users | Low | Medium | Low (2) | Logs written only through procedures; UPDATE/DELETE DENIED; auditor role has read-only access (`03_rbac.sql`, `05_stored_procedures.sql`) |

## Summary

- **2 Critical, 5 High, 2 Medium, 1 Low.**
- The two Critical risks (weak passwords and SQL injection) are the most
  common real-world causes of e-commerce breaches, so the live demo shows them
  first.
- Every risk maps to one or more scripts in `/sql`, so the checklist doubles as
  the project's table of contents.
