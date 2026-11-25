# Screenshots

There are two sets:

1. **Already included** (`app/` and `sql/`). These were captured from the real
   system during development (SQL Server 2022 Developer in Docker), and the
   slides use them as the "results" and as a **fallback** if the live demo fails.
2. **To capture yourself on Windows.** Take these on your own laptop so the
   examiner sees *your* environment. Save them in `screenshots/windows/` with the
   file names below. In SSMS, set **Results to Grid** (Ctrl+D), and use
   Win+Shift+S to snip.

## A. Capture yourself (Windows): checklist

| ✓ | File name | Step | What must be visible |
|---|-----------|------|----------------------|
| ☐ | `w00_version.png` | Setup | SSMS: `SELECT @@VERSION, SERVERPROPERTY('Edition')` → **Developer Edition** |
| ☐ | `w01_run_all.png` | Setup | PowerShell window after `.\run_sql.ps1` ending in **Done.** |
| ☐ | `w02_tables.png` | 01 | SSMS Object Explorer: ShopDB → Tables (8 tables) + Keys/Constraints expanded on `Users` |
| ☐ | `w03_constraint.png` | 01 | `99_demo_queries.sql` block D1 → error *CHECK constraint "CK_Products_Price"* |
| ☐ | `w04_hashes.png` | 01 | Block D2 → `PasswordSalt` / `PasswordHash` binary columns (no plaintext) |
| ☐ | `w05_weak_login.png` | 02 | Block D3 → *Password validation failed* |
| ☐ | `w06_policy_function.png` | 02 | Block D3 (second query) → policy results table |
| ☐ | `w07_secpol.png` | 02 | `secpol.msc` → Account Policies → Password Policy + Account Lockout Policy (the Windows policy that `CHECK_POLICY` uses) |
| ☐ | `w08_roles.png` | 03 | Object Explorer: ShopDB → Security → Roles → Database Roles (admin_role, sales_role…) |
| ☐ | `w09_rbac_denied.png` | 03 | Block D4 → *UPDATE permission was denied* + *SELECT permission was denied … Customers* |
| ☐ | `w10_matrix.png` | 03 | Output of `.\run_sql.ps1 sql\03_rbac.sql` → permission matrix |
| ☐ | `w11_rls.png` | 04 | Block D5 → two result grids: Addis rows vs Hawassa rows |
| ☐ | `w12_masking.png` | 04 | Block D6 → real e-mails vs `sXXX@XXXX.com` |
| ☐ | `w13_tde_state.png` | 06 | Block D7 → `encryption_state = 3` for ShopDB |
| ☐ | `w14_cert_files.png` | 06 | File Explorer: SQL Server **Backup** folder showing `TDE_ShopDB_Cert_xxxx.cer` + `.pvk` + the two `.bak` files |
| ☐ | `w15_bak_compare.png` | 06 | PowerShell: `Select-String -Path "<backup folder>\ShopDB_before_TDE.bak","<backup folder>\ShopDB_after_TDE.bak" -Pattern "EL-PHN-001" -SimpleMatch -List` (before → match, after → nothing) |
| ☐ | `w16_card_decrypt.png` | 06 | Block D8 → admin sees card numbers, sales sees `NULL` |
| ☐ | `w17_drill.png` | 06b | Output of `.\run_sql.ps1 sql\06b_tde_lost_cert_drill.sql` with **Msg 33111** and **RESTORE SUCCEEDED** |
| ☐ | `w18_app_vuln_login.png` | 05 | Browser: red login with `' OR '1'='1' --` → "Logged in … VULNERABLE" + SQL text |
| ☐ | `w19_app_secure_login.png` | 05 | Green login with the same payload → "Invalid username or password" |
| ☐ | `w20_app_union.png` | 05 | Red search with the UNION payload → usernames + hashes listed |
| ☐ | `w21_app_lockout.png` | 05 | Green login after 5 wrong passwords → "Account locked" |
| ☐ | `w22_mfa_qr.png` | 07 | Account & MFA → QR code page |
| ☐ | `w23_mfa_phone.png` | 07 | Photo of your phone's authenticator showing *ShopDB Demo* |
| ☐ | `w24_audit.png` | all | Block D9 → audit log after the web demo |
| ☐ | `w25_smoke.png` | all | Terminal: `python smoke_test.py` → **22/22 checks passed** |

## B. Already included (captured from the running system)

### `app/` (Flask demo, real browser screenshots)
| File | Shows |
|------|-------|
| `01_home.png` | Home page: hardened (green) vs vulnerable (red) forms |
| `02_vulnerable_login_bypassed.png` | `' OR '1'='1' --` logs in as selam.g without a password; the built SQL is shown |
| `03_hardened_login_rejected.png` | Same payload on the hardened login → "Invalid username or password" |
| `04_vulnerable_search_union_dump.png` | UNION injection dumps every username + password hash |
| `05_hardened_search_union_blocked.png` | Same payload on the hardened search → no rows, parameters shown |
| `06_vulnerable_error_leak.png` | Error-based injection leaks the SQL Server version |
| `07a_vulnerable_price_attack.png` / `07b_laptop_now_costs_1_ETB.png` | Stacked query changes the laptop price to 1 ETB |
| `08_account_locked_after_5_attempts.png` | Lockout after 5 wrong passwords |
| `09_my_orders_rls.png` | Customer sees only their own orders (RLS + SESSION_CONTEXT) |
| `10a_search_logged_in_with_buy.png` / `10b_order_placed.png` | Placing an order through `app.sp_PlaceOrder` |
| `11_register_weak_password_rejected.png` | Registration rejected by the password policy |
| `12_mfa_setup_qr.png` … `16_mfa_login_success.png` | MFA setup, second-factor prompt, wrong code, success |

### `sql/` (real `sqlcmd` output, rendered as images)
| File | Shows |
|------|-------|
| `sql_01_constraints.png` | 4 bad inserts rejected (CHECK, UNIQUE, FK, CHECK) |
| `sql_02_password_policy.png` | Weak SQL login rejected, website policy results, change-password tests |
| `sql_03_permission_matrix.png` | ALLOWED/DENIED for 10 actions × 6 users |
| `sql_04_rls_masking.png` | Orders per user (RLS) + masked vs unmasked customers |
| `sql_04_attribute_change.png` | Changing Region / IsActive changes access instantly |
| `sql_05_procedures.png` | Injection payloads, lockout, UNION/sort injection, direct SELECT denied |
| `sql_06_tde_status.png` | `encryption_state = 3` + plaintext found only in the pre-TDE backup |
| `sql_06_column_encryption.png` | Admin decrypts card numbers, sales gets NULL |
| `sql_06_classification.png` | Sensitivity labels |
| `sql_06b_lost_cert_drill.png` | Restore fails without the certificate (Msg 33111), works after restoring it |
