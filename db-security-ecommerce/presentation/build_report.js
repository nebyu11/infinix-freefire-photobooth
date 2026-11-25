/*
 * build_report.js - builds docs/ShopDB_Database_Security_Report.docx
 * (the written report to submit). All figures are real screenshots /
 * outputs from ../screenshots.
 *
 * Rebuild:  cd presentation && npm install && node build_report.js
 */
const fs = require("fs");
const path = require("path");
const sharp = require("sharp");
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Table, TableRow, TableCell, WidthType,
  ShadingType, AlignmentType, HeadingLevel, PageBreak, Header, Footer, PageNumber,
  LevelFormat, BorderStyle, TableOfContents, VerticalAlign,
} = require("docx");

const ROOT = path.resolve(__dirname, "..");
const SHOT = (p) => path.join(ROOT, "screenshots", p);
const IMG = (p) => path.join(__dirname, "img", p);

// A4, 1-inch margins -> content width 9026 DXA (6.27 in)
const CONTENT_DXA = 9026;
const MAX_W_PX = 600;   // 6.25 in at 96 dpi
const MAX_H_PX = 720;   // 7.5 in

const NAVY = "14213D", TEAL = "1B998B", CORAL = "E4572E", GOLD = "B7791F", GREY = "5F6B7A", LIGHT = "EEF2F7";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
const body = [];
let fig = 0, tab = 0;
const FIGS = [];

const P = (text, o = {}) => new Paragraph({ spacing: { after: 120, line: 276 }, ...o,
  children: (Array.isArray(text) ? text : [text]).map((t) => (typeof t === "string" ? new TextRun(t) : t)) });
const B = (t) => new TextRun({ text: t, bold: true });
const I = (t) => new TextRun({ text: t, italics: true });
const CODE = (t) => new TextRun({ text: t, font: "Consolas", size: 20, color: "1A2233" });
const H1 = (t) => body.push(new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [new TextRun(t)] }));
const H2 = (t) => body.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] }));
const H3 = (t) => body.push(new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] }));
const para = (...a) => body.push(P(...a));
let listNo = 0;
const bullets = (items, ref = "bullets") => { const inst = ++listNo; items.forEach((t) => body.push(new Paragraph({
  numbering: { reference: ref, level: 0, instance: inst }, spacing: { after: 60, line: 276 },
  children: (Array.isArray(t) ? t : [t]).map((x) => (typeof x === "string" ? new TextRun(x) : x)) }))); };
const numbered = (items) => bullets(items, "numbers");

function note(text, color = TEAL, fill = "E3F4F2") {
  body.push(new Paragraph({
    spacing: { before: 60, after: 160, line: 276 },
    shading: { type: ShadingType.CLEAR, color: "auto", fill },
    border: { left: { style: BorderStyle.SINGLE, size: 18, color, space: 6 } },
    indent: { left: 120, right: 120 },
    children: (Array.isArray(text) ? text : [text]).map((t) => (typeof t === "string" ? new TextRun(t) : t)),
  }));
}

async function figure(file, caption, explain) {
  const m = await sharp(file).metadata();
  let w = MAX_W_PX, h = Math.round((w * m.height) / m.width);
  if (h > MAX_H_PX) { h = MAX_H_PX; w = Math.round((h * m.width) / m.height); }
  fig += 1;
  FIGS.push([fig, caption, path.relative(ROOT, file)]);
  body.push(new Paragraph({ alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 120, after: 60 },
    children: [new ImageRun({ type: "png", data: fs.readFileSync(file), transformation: { width: w, height: h },
      altText: { title: `Figure ${fig}`, description: caption, name: `figure${fig}` } })] }));
  body.push(new Paragraph({ alignment: AlignmentType.CENTER, keepNext: !!explain, spacing: { after: explain ? 60 : 200 },
    children: [new TextRun({ text: `Figure ${fig}: `, bold: true, size: 20, color: NAVY }),
               new TextRun({ text: caption, italics: true, size: 20, color: GREY })] }));
  if (explain) note([B("What this shows: "), ...(Array.isArray(explain) ? explain : [explain]).map((t) => (typeof t === "string" ? new TextRun(t) : t))]);
}

function table(headers, rows, widths, opts = {}) {
  const total = widths.reduce((a, b) => a + b, 0);
  const border = { style: BorderStyle.SINGLE, size: 4, color: "C9D1DC" };
  const borders = { top: border, bottom: border, left: border, right: border };
  const cell = (t, i, isHead, fill) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA }, borders, verticalAlign: VerticalAlign.CENTER,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    shading: { type: ShadingType.CLEAR, color: "auto", fill: isHead ? NAVY : fill },
    children: [new Paragraph({ children: [new TextRun({ text: String(t), bold: isHead || (opts.boldFirst && i === 0),
      color: isHead ? "FFFFFF" : (opts.colorFn ? opts.colorFn(t, i) : "1A2233"), size: opts.size || 19 })] })],
  });
  tab += 1;
  body.push(new Table({
    width: { size: total, type: WidthType.DXA }, columnWidths: widths,
    rows: [new TableRow({ tableHeader: true, children: headers.map((h, i) => cell(h, i, true)) }),
      ...rows.map((r, ri) => new TableRow({ children: r.map((v, i) => cell(v, i, false,
        opts.fillFn ? opts.fillFn(v, i, ri) : (ri % 2 ? "FFFFFF" : LIGHT))) }))],
  }));
  if (opts.caption) body.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 60, after: 200 },
    children: [new TextRun({ text: `Table ${tab}: `, bold: true, size: 20, color: NAVY }),
               new TextRun({ text: opts.caption, italics: true, size: 20, color: GREY })] }));
}

// ---------------------------------------------------------------------------
(async () => {
  // =========================== COVER PAGE ==================================
  const cover = [
    new Paragraph({ spacing: { before: 1600, after: 200 }, alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "Ethiopian Technical Excellence · Frontier Institute of Technology", size: 24, color: GREY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 600 },
      children: [new TextRun({ text: "Database Security (CyTe3031) · Chapter 2", size: 24, color: GREY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
      children: [new TextRun({ text: "Securing an E-commerce Database", font: "Cambria", size: 56, bold: true, color: NAVY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 900 },
      children: [new TextRun({ text: "Practical implementation of access control, authentication and data protection on Microsoft SQL Server 2022", size: 28, color: TEAL })] }),
  ];
  const coverRows = [["Student", "[Your full name]"], ["Student ID", "[Your ID]"], ["Course", "Database Security (CyTe3031)"],
    ["Instructor", "Talema A."], ["Application area", "E-commerce: online shop \"ShopDB\""], ["DBMS", "Microsoft SQL Server 2022 Developer Edition"],
    ["Submission date", "[Date]"]];
  const cw = [2600, 4400];
  cover.push(new Table({ width: { size: 7000, type: WidthType.DXA }, columnWidths: cw, alignment: AlignmentType.CENTER,
    rows: coverRows.map(([a, b]) => new TableRow({ children: [
      new TableCell({ width: { size: cw[0], type: WidthType.DXA }, shading: { type: ShadingType.CLEAR, color: "auto", fill: LIGHT },
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun({ text: a, bold: true, color: NAVY })] })] }),
      new TableCell({ width: { size: cw[1], type: WidthType.DXA }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun(b)] })] })] })) }));

  const toc = [
    new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("Table of contents")] }),
    new TableOfContents("Table of contents", { hyperlink: true, headingStyleRange: "1-2" }),
    P(I("If the table of contents is empty, right-click it in Word and choose \"Update Field\" → \"Update entire table\"."), { spacing: { before: 200 } }),
  ];

  // =========================== 1. INTRODUCTION =============================
  H1("1. Introduction");
  para("This report documents my practical implementation of the concepts in Chapter 2 of the Database Security course: access control, authentication and data protection. I chose e-commerce as the application area and built a complete, working, security-hardened database for a fictional Ethiopian online shop called ShopDB. It stores customers, products, orders, payments (including card numbers) and staff accounts.");
  para("Every result in this report comes from the real system. All screenshots and outputs were captured while the scripts and the demo web application were running. Nothing was edited by hand.");
  H2("1.1 Objectives");
  bullets(["Identify the risks to the shop's digital assets and plan a control for each one.",
    "Create the database with proper constraints, a login (user) table and realistic sample data.",
    "Enforce strong password policies, both for SQL Server logins and for website users.",
    "Implement Role-Based Access Control (RBAC) and Attribute-Based Access Control (ABAC).",
    "Protect the database against SQL injection with hardened stored procedures and query-hardening techniques, and prove it with a live attack demo.",
    "Enable Transparent Data Encryption (TDE), encrypt a sensitive column, and test who can and cannot read it.",
    "(Optional) Add multi-factor authentication (MFA)."]);
  H2("1.2 How the assignment requirements are covered");
  table(["#", "Assignment requirement", "Where it is implemented", "Section"], [
    ["1", "Risk identification checklist", "docs/risk_checklist.md / .xlsx", "3"],
    ["2", "Database, tables, constraints, user table, sample data", "sql/01_schema.sql", "4"],
    ["3, 5", "Strong password policy (implement + demonstrate)", "sql/02_password_policy.sql (+ lockout in 05)", "5"],
    ["4.i", "Role-Based Access Control", "sql/03_rbac.sql", "6.1"],
    ["4.ii", "Attribute-Based Access Control", "sql/04_abac.sql", "6.2"],
    ["6, 7", "Stored procedures, query hardening, SQL injection defence", "sql/05_stored_procedures.sql + app/", "7"],
    ["8", "TDE + column encryption + access tests", "sql/06_tde.sql, sql/06b_tde_lost_cert_drill.sql", "8"],
    ["9", "MFA (optional)", "sql/07_mfa.sql + app/", "9"],
  ], [700, 3600, 3526, 1200], { caption: "Mapping of assignment requirements to project files" });

  // =========================== 2. ENVIRONMENT ==============================
  H1("2. Environment, tools and project structure");
  H2("2.1 Software used");
  table(["Component", "Version / choice", "Why"], [
    ["DBMS", "Microsoft SQL Server 2022 Developer (CU28)", "Free, full-featured edition. TDE is not available in Express."],
    ["Command-line tool", "sqlcmd 18 (ODBC)", "Runs the numbered scripts; passes passwords as variables"],
    ["Management tool", "SQL Server Management Studio (SSMS)", "Live demo queries (sql/99_demo_queries.sql)"],
    ["Demo application", "Python 3 + Flask 3.1, pyodbc 5.5 (ODBC Driver 18)", "Small and readable; parameterized queries with \"?\""],
    ["MFA library", "pyotp 2.12 (TOTP, RFC 6238) + cryptography (Fernet)", "Google Authenticator-compatible codes; encrypted secret"],
    ["Testing", "smoke_test.py (22 automated checks)", "Proves every security behaviour end-to-end"],
  ], [2000, 3500, 3526], { caption: "Tools and versions" });
  para([B("Development note: "), "the project was developed and tested with SQL Server 2022 Developer running in Docker. The same scripts run on a Windows installation of SQL Server 2022 Developer (the README explains both). The only difference I observed is the error number for a rejected weak login password: 15116/15118 on Windows and 33062 on Linux, with the same message text."]);
  H2("2.2 Project structure");
  table(["Folder / file", "Content"], [
    ["sql/00_reset.sql", "Removes everything (start from zero)"],
    ["sql/01 … 07_*.sql", "One numbered script per security layer, run in order"],
    ["sql/06b_tde_lost_cert_drill.sql", "Disaster-recovery drill: what happens if the TDE certificate is lost"],
    ["sql/99_demo_queries.sql", "Short blocks (D1–D10) for the live SSMS demo"],
    ["run_sql.ps1 / run_sql.sh", "Runner: reads passwords from .env and passes them to sqlcmd (-v)"],
    ["app/", "Flask demo: vulnerable vs hardened login/search, orders, registration, MFA; smoke_test.py"],
    ["docs/", "Risk checklist, this report, speaker notes, Q&A cheat sheet"],
    ["presentation/", "Slides (.pptx) with speaker notes"],
    ["screenshots/", "All figures used in this report"],
  ], [3300, 5726], { caption: "Project structure" });
  H2("2.3 Secrets management");
  para("No real password or key is written in any .sql or .py file. The scripts contain sqlcmd variables such as $(APP_PASSWORD). The runner script reads the real values from a .env file and passes them with -v NAME=\"value\". The .env file is listed in .gitignore, so it is never committed, and a template (.env.example) shows which values are needed. This follows the lecture's secure-coding rule: \"Secrets management: store credentials in secure vaults, not in source code.\"");
  await figure(SHOT("sql/sql_00_rebuild.png"), "The whole database is built from an empty server with one command",
    "all seven scripts ran in order without a single error (the runner uses sqlcmd -b, which stops at the first unexpected error). A full rebuild takes about 10 seconds, and every script can safely be run again (idempotent).");

  // =========================== 3. RISK CHECKLIST ===========================
  H1("3. Risk identification checklist");
  para("Before building anything, I identified the shop's digital assets and analysed what could go wrong with each, using the form from the assignment. Each risk gets a Likelihood and an Impact score from 1 (Low) to 3 (High). The risk rating is their product: 9 = Critical, 6 = High, 3–4 = Medium, 1–2 = Low.");
  const RC = { Critical: "F9D5CC", High: "FCE7C3", Medium: "DCE6F2", Low: "D7F0EB" };
  table(["#", "Asset", "Threat", "Vulnerability", "L", "I", "Rating", "Mitigation (script)"], [
    ["1", "Customer records", "Unauthorized access / account takeover", "Weak or reused passwords, no lockout", "High", "High", "Critical", "Password policy + lockout + MFA (02, 05, 07)"],
    ["2", "Customer, order, user tables", "SQL injection", "App builds SQL by joining strings", "High", "High", "Critical", "Stored procedures, parameters, validation (05, app)"],
    ["3", "Payment / card data", "Theft or insider reading", "Card numbers in plaintext", "Med", "High", "High", "Column encryption + masking (06, 04)"],
    ["4", "Database files & backups", "Stolen disk or backup", "Files not encrypted at rest", "Med", "High", "High", "TDE (06)"],
    ["5", "User credentials", "Offline password cracking", "Plaintext / unsalted hashes", "Med", "High", "High", "Salted, iterated hash (01, 05)"],
    ["6", "Admin accounts (sa, db_owner)", "Privilege abuse / escalation", "App uses sa; too many rights", "Med", "High", "High", "RBAC least privilege (03)"],
    ["7", "Orders seen by staff", "Insider browsing", "All staff see all rows", "High", "Med", "High", "ABAC with Row-Level Security (04)"],
    ["8", "Product prices", "Price fraud", "Too many UPDATE rights", "Med", "Med", "Medium", "DENY UPDATE to sales (03)"],
    ["9", "TDE certificate & keys", "Key loss → backups unusable", "No certificate backup", "Low", "High", "Medium", "Certificate backup + restore drill (06, 06b)"],
    ["10", "Audit log", "Log tampering to hide tracks", "Log writable by app users", "Low", "Med", "Low", "DENY UPDATE/DELETE (03, 05)"],
  ], [350, 1250, 1400, 1500, 550, 500, 900, 2576], { size: 17, caption: "Risk identification checklist (L = likelihood, I = impact)",
    fillFn: (v, i, ri) => (i === 6 ? RC[v] : (ri % 2 ? "FFFFFF" : LIGHT)) });
  para([B("Result: "), "2 Critical, 5 High, 2 Medium and 1 Low risk. The two Critical risks (weak passwords and SQL injection) are the most common causes of e-commerce breaches, so I implemented and demonstrate their controls first. Every row maps to a script, so the checklist is also the plan for the whole project. The same table is in docs/risk_checklist.xlsx."]);

  // =========================== 4. DATABASE =================================
  H1("4. Database design, constraints and sample data");
  para("Script 01_schema.sql creates the database ShopDB with eight tables and fills every table with realistic (fictional) Ethiopian sample data. Constraints are the first security layer: the database itself rejects invalid data, even if the application has a bug.");
  table(["Table", "Purpose", "Key constraints"], [
    ["Staff", "Employees; Department and Region are ABAC attributes", "PK, UNIQUE (Email, DbUserName), CHECK (Department, Region), DEFAULT (IsActive, HiredAt)"],
    ["Customers", "Personal data (PII)", "PK, UNIQUE (Email), CHECK (e-mail shape, +251 phone format, Region)"],
    ["Users", "Website login accounts (customers and staff)", "PK, UNIQUE (Username), CHECK (Role, Status, allowed characters, customer-or-staff link), FK, DEFAULT"],
    ["Products", "Catalog", "PK, UNIQUE (SKU), CHECK (Price > 0, Stock ≥ 0, Category), DEFAULT"],
    ["Orders", "Orders; ShipRegion is an ABAC resource attribute", "PK, FK → Customers, CHECK (Status, Region, Total ≥ 0), DEFAULT"],
    ["OrderItems", "Order lines", "Composite PK (OrderID, ProductID), FK, CHECK (Quantity 1–100, UnitPrice > 0)"],
    ["Payments", "Payments incl. card numbers", "PK, FK, UNIQUE (one payment per order), CHECK (Method, Status, card only for card payments)"],
    ["AuditLog", "Who did what, when", "PK, DEFAULT (EventTime, DbLogin = ORIGINAL_LOGIN())"],
  ], [1400, 3000, 4626], { caption: "Tables and constraints (all columns that must have a value are NOT NULL)" });
  H2("4.1 Password storage (never plaintext)");
  para("Passwords are never stored. The function dbo.fn_HashPassword computes a salted, iterated SHA-512 hash:");
  bullets([["A ", B("salt"), " of 16 random bytes (CRYPT_GEN_RANDOM) is generated for every user, so two users with the same password get different hashes and pre-computed rainbow tables are useless."],
    ["The hash is repeated ", B("5,000 times"), " (key stretching, the same idea as PBKDF2), so every guess costs an attacker 5,000 hash calculations."],
    "SHA-512 is one-way: the hash cannot be turned back into the password, not even by the administrator."]);
  note([B("Honest note: "), "in a production system I would use bcrypt or Argon2 from a tested library in the application. T-SQL has no built-in slow hash, so this function demonstrates the same principle inside the database."], GOLD, "FFF4DC");
  await figure(SHOT("sql/sql_01_rowcounts.png"), "Every table contains sample data; passwords are stored only as salt + hash",
    "the row counts of all eight tables (Staff 5, Customers 8, Users 10, Products 10, Orders 10, OrderItems 14, Payments 10, AuditLog 1), and that each user has a different random salt and a 64-byte hash. No plaintext password exists anywhere in the table.");
  await figure(SHOT("sql/sql_01_constraints.png"), "Four invalid inserts are rejected by the database itself",
    "a negative price (CHECK), a duplicate e-mail (UNIQUE), an order for a customer that does not exist (FOREIGN KEY) and a username containing a quote and \"--\" (CHECK) are all refused, each with the name of the constraint that stopped it.");

  // =========================== 5. PASSWORD POLICY ==========================
  H1("5. Strong password policy");
  para("The lecture explains that weak and reused passwords are a top cause of breaches, and that a good policy combines minimum length, complexity, a blocklist, lockout, history and safe storage. The size of the search space is Cᴺ (C = number of possible characters, N = length). Six lower-case letters give 26⁶ ≈ 3.1 × 10⁸ possibilities, which a computer tries in seconds. My minimum of 10 characters from all four character groups allows up to 94¹⁰ ≈ 5.4 × 10¹⁹. I enforce the policy at two levels (script 02_password_policy.sql).");
  H2("5.1 Level A: SQL Server logins (CHECK_POLICY / CHECK_EXPIRATION)");
  bullets([[B("CHECK_POLICY = ON: "), "SQL Server applies the operating system's password policy. A password must have at least 8 characters from 3 of the 4 character groups, and on Windows the account-lockout policy also applies."],
    [B("CHECK_EXPIRATION = ON: "), "passwords expire (maximum password age), for human accounts."],
    [B("MUST_CHANGE: "), "the user must choose a new password at the first login, which the lecture recommends after an administrator resets a password."]]);
  para("On Windows, the lockout values come from Local Security Policy (secpol.msc → Account Policies). I recommend: minimum length 12, complexity enabled, maximum age 90 days, history 5, lockout threshold 5 attempts for 15 minutes. A locked login is unlocked with ALTER LOGIN … WITH PASSWORD = '…' UNLOCK.");
  H2("5.2 Level B: website users (enforced in T-SQL)");
  para("SQL Server does not know about the website's users, so I wrote one policy function, dbo.fn_PasswordPolicyErrors. It is used by both the registration procedure and the change-password procedure, and returns every rule that failed:");
  bullets(["at least 10 characters; upper case, lower case, a digit and a symbol;",
    "must not contain the username;",
    "must not be in a blocklist of common breached passwords (e.g. \"Password123!\");",
    "must not repeat one of the last 3 passwords (PasswordHistory table, compared using each old salt)."]);
  await figure(SHOT("sql/sql_02_password_policy.png"), "Password policy demonstration: weak passwords rejected, strong password accepted",
    ["Part A: the weak login password \"shop123\" and a password equal to the login name are rejected by CHECK_POLICY, while a strong password is accepted with MUST_CHANGE. Part B: the policy function explains exactly why each weak candidate fails, and the change-password procedure rejects a weak password and a wrong current password, accepts a strong one, and blocks re-use of an old password."]);
  await figure(SHOT("app/11_register_weak_password_rejected.png"), "The same policy enforced in the web application's registration form",
    "a new customer who chooses \"abel1234\" is refused with the list of missing requirements. The rule is enforced inside the database procedure, so it cannot be bypassed from the browser.");

  // =========================== 6. ACCESS CONTROL ===========================
  H1("6. Access control");
  para("Access control decides what an authenticated user may see, query, modify or execute. The lecture describes four models: RBAC, DAC, MAC and ABAC. I implemented RBAC (script 03) and ABAC (script 04) following the principle of least privilege.");
  H2("6.1 Role-Based Access Control (RBAC)");
  para("Permissions are given to roles (job functions), never to individual people. Every person or application connects with its own login, which maps to a database user that is a member of exactly one role. GRANT gives a right; DENY forbids it and always wins over a GRANT.");
  table(["Role / login", "Can", "Cannot (DENY or not granted)"], [
    ["admin_role (shop_admin)", "Manage customers, products, orders, payments; unlock accounts; read the audit log", "Drop tables, read password hashes, change or delete the audit log (it is NOT db_owner)"],
    ["sales_role (sales_addis, sales_hawassa)", "Read customers/orders/products; update order status; read payments without the card column", "Change prices (DENY UPDATE on Products); read card numbers"],
    ["support_role (support_dawit)", "Read customers, orders, products", "Any access to Payments; unmasked contact data"],
    ["auditor_role (auditor_meron)", "Read everything including the audit log", "Any INSERT, UPDATE or DELETE (DENY on schema dbo)"],
    ["customer_role (shop_app = the website)", "EXECUTE the procedures in schema [app] only", "Any direct SELECT/INSERT/UPDATE/DELETE on tables (DENY on schema dbo)"],
    ["legacy_app (demo only)", "Read and write every table (db_datareader + db_datawriter)", "Deliberately over-privileged anti-pattern for the SQL-injection demo"],
  ], [2500, 3300, 3226], { caption: "Roles and least-privilege permissions", boldFirst: true });
  para([B("Why can the website work without table rights? "), "The app procedures (schema app) and the tables (schema dbo) have the same owner, so SQL Server only checks the EXECUTE permission on the procedure. This is called ownership chaining. Even if an attacker found a bug in the website, its login could not read a single table."]);
  await figure(SHOT("sql/sql_03_permission_matrix.png"), "Permission matrix: 10 actions tried by 6 users (EXECUTE AS each user)",
    "the script impersonates each user, tries each action inside a transaction that is always rolled back, and records whether SQL Server allowed or denied it. The website login (website_app) is denied on every table and only allowed to execute app procedures. Nobody can read password hashes or delete the audit log, not even admin, and DROP TABLE is denied for everyone. Only the deliberately bad legacy_app can do the dangerous actions, which is why SQL injection through it is so damaging (Section 7).");
  H2("6.2 Attribute-Based Access Control (ABAC)");
  note([B("Honest note: "), "SQL Server has no feature literally called ABAC. I implemented the ABAC model with native features: Row-Level Security (RLS), attributes stored in the Staff table and in SESSION_CONTEXT, and Dynamic Data Masking."], GOLD, "FFF4DC");
  para("A security policy (sec.ShopAccessPolicy) attaches a predicate function to the Orders and Customers tables. For every row, the function compares attributes and decides whether the row is visible:");
  bullets([[B("admin and auditor: "), "every row;"],
    [B("active Sales or Support staff: "), "rows where the row's region equals the staff member's Region attribute (head-office staff have Region = ALL);"],
    [B("the website (customer_role): "), "only rows of the customer whose ID the app stored in SESSION_CONTEXT right after login;"],
    [B("anyone else: "), "no rows."]]);
  para("A BLOCK predicate also stops the website from inserting an order for a different customer. Dynamic Data Masking hides customer e-mails and phone numbers from users without the UNMASK permission. Only admin and sales, who must contact customers, can see the real values.");
  await figure(SHOT("sql/sql_04_rls_masking.png"), "Same query, different rows (RLS) and different column values (masking)",
    "one SELECT on Orders returns 10 rows for admin, auditor and support (region ALL), 4 rows for sales_addis (Addis Ababa only) and 3 rows for sales_hawassa (Hawassa only). The same SELECT on Customers shows sales_addis only Addis customers with real contact data, while support_dawit sees all customers but with masked e-mail (sXXX@XXXX.com) and phone (+251XXXXXX567).");
  await figure(SHOT("sql/sql_04_attribute_change.png"), "Changing an attribute (not a role) changes access immediately",
    "when Abebe is moved to the Hawassa branch, only his Region attribute changes and he immediately sees the Hawassa orders. When he is deactivated (IsActive = 0), he sees nothing. No role or GRANT was changed: this is what makes the control attribute-based.");
  await figure(SHOT("app/09_my_orders_rls.png"), "In the web app, a customer sees only their own orders",
    "the procedure app.sp_GetMyOrders has no WHERE clause at all. Row-Level Security adds the filter automatically, using the CustomerID that the app stored in SESSION_CONTEXT at login. Selam sees only her orders (#1001, #1009, plus one placed during testing).");

  // =========================== 7. SQL INJECTION ============================
  H1("7. Stored procedures, query hardening and SQL injection");
  para("SQL injection happens when an application glues user input into the SQL text. The input \"' OR '1'='1' --\" turns WHERE Username = '…' into a condition that is always true, and comments out the rest of the query. To demonstrate this, the Flask application has two clearly separated paths:");
  bullets([[B("Red, vulnerable path (lab only): "), "builds SQL with string concatenation, connects as the over-privileged legacy_app login, and shows raw database errors. It is only enabled when ENABLE_VULNERABLE_DEMO=1 and only answers requests from 127.0.0.1."],
    [B("Green, hardened path: "), "calls stored procedures with parameters, connects as shop_app (EXECUTE-only), and shows generic error messages."]]);
  H2("7.1 Query-hardening techniques used (script 05_stored_procedures.sql)");
  numbered([[B("Typed parameters: "), "user input is passed as data, never as SQL code, both in the procedures and in the app (pyodbc \"?\" placeholders)."],
    [B("Input validation with allow-lists: "), "usernames may only contain letters, digits, dot and underscore; e-mail, phone, region, quantity and payment method are all checked."],
    [B("Dynamic SQL only where unavoidable: "), "the user-chosen sort column must be in an allow-list, is wrapped in QUOTENAME(), and every value still goes through sp_executesql parameters. LIKE wildcards in the search text are escaped."],
    [B("Error handling: "), "TRY/CATCH writes the real error to the AuditLog and returns a generic message, so there is no information leakage."],
    [B("Least privilege + schema qualification: "), "the website can only EXECUTE app.* procedures, and every object is schema-qualified (dbo., app.)."],
    [B("Account lockout and safe messages: "), "5 wrong passwords lock the account for 15 minutes. The message is always \"Invalid username or password\", and unknown users are hashed too, so timing reveals nothing."],
    [B("No IDOR: "), "the customer is never a form field. Orders use the CustomerID from SESSION_CONTEXT."]]);
  await figure(SHOT("app/01_home.png"), "The demo application: hardened (green) and vulnerable (red) forms side by side",
    "both forms receive exactly the same input during the demo, so the difference in outcome comes only from how the input reaches the database.");
  await figure(SHOT("app/02_vulnerable_login_bypassed.png"), "Attack 1 on the vulnerable login: ' OR '1'='1' -- logs in without a password",
    "the red box shows the SQL that the vulnerable code built. The WHERE clause became always true and the password check was commented out, so the attacker is logged in as the first user (selam.g) without knowing any password.");
  await figure(SHOT("app/03_hardened_login_rejected.png"), "The same input on the hardened login is rejected",
    "app.sp_Login received the input as a parameter, its allow-list validation rejected the quote characters, and the user only sees the generic message \"Invalid username or password\". The attempt is also written to the audit log.");
  await figure(IMG("union_dump_crop.png"), "Attack 2 on the vulnerable search: a UNION injection dumps every username and password hash",
    "the attacker appends a second SELECT to the product query and reads the Users table through the search results. The salted, iterated hashes are hard to crack, but they should never leak.");
  await figure(SHOT("app/05_hardened_search_union_blocked.png"), "The same UNION payload on the hardened search returns nothing",
    "the parameters are sent separately from the SQL text (shown in the green box), so the payload is only a strange product name, and 0 rows are returned.");
  await figure(SHOT("app/06_vulnerable_error_leak.png"), "Attack 3: error-based injection leaks internal information",
    "the vulnerable path shows the raw database error, which here reveals the exact SQL Server version. The hardened path never shows internal errors.");
  await figure(SHOT("app/07b_laptop_now_costs_1_ETB.png"), "Attack 4: a stacked UPDATE through the vulnerable search changed a price to 1 ETB",
    "the payload '; UPDATE dbo.Products SET Price = 1 WHERE SKU = 'EL-LAP-002' -- ran a second statement, so the Laptop Pro now costs 1.00 ETB. That is real fraud. It worked only because the vulnerable login has write rights on every table.");
  await figure(SHOT("sql/sql_05_procedures.png"), "Procedure tests, run as the website login (shop_app)",
    "the injection payloads used as usernames are rejected; five wrong passwords lock the account and even the correct password is refused while locked; the UNION payload in the search returns 0 rows; a DROP TABLE hidden in the sort parameter is ignored (falls back to sorting by Name); a direct SELECT by the website login is denied; and the Products table still exists.");
  await figure(SHOT("app/08_account_locked_after_5_attempts.png"), "Account lockout in the web application after 5 wrong passwords",
    "this stops online brute-force and password-guessing attacks (lecture: \"Account lockout policies should be used\").");
  await figure(SHOT("sql/sql_05_register_orders.png"), "Registration and order procedures with validation and SESSION_CONTEXT",
    "registration rejects a weak password, accepts a valid one, refuses a duplicate username or e-mail (UNIQUE constraint) and rejects a username containing an injection attempt. Orders are placed for the customer stored in the session, a quantity of 50 is rejected, and switching the session customer shows completely different orders.");
  await figure(SHOT("app/10b_order_placed.png"), "Placing an order through the hardened path",
    "the order is created by app.sp_PlaceOrder in one transaction: stock check, order, order line, payment and audit entry. The customer is taken from the session, never from the form.");

  // =========================== 8. ENCRYPTION ===============================
  H1("8. Transparent Data Encryption and column encryption");
  para("The lecture describes encryption as a layered defence for data at rest, in motion and in use. Script 06_tde.sql implements two different protections, which complement each other:");
  table(["", "TDE (Transparent Data Encryption)", "Column (cell-level) encryption"], [
    ["What is encrypted", "The whole database files on disk: .mdf, .ldf and backups", "One column: Payments.CardNumberEnc"],
    ["Protects against", "Stolen disk, stolen backup, copied data file", "Users who may query the table but must not read the value"],
    ["Who sees plaintext", "Anyone with SELECT (decrypted automatically)", "Only users allowed to use the key (admin_role)"],
    ["Application changes", "None (\"transparent\")", "ENCRYPTBYKEY / DECRYPTBYKEY"],
  ], [1800, 3600, 3626], { caption: "TDE compared with column encryption", boldFirst: true });
  H2("8.1 TDE implementation");
  para("Key hierarchy: Service Master Key → Database Master Key in [master] → certificate TDE_ShopDB_Cert → Database Encryption Key (AES-256) in ShopDB → every data page written to disk. The script creates the master key and the certificate, backs up the certificate with its private key to .cer + .pvk files protected by a password (before encrypting), creates the database encryption key and runs ALTER DATABASE ShopDB SET ENCRYPTION ON. To prove the effect, it takes one backup before and one after enabling TDE.");
  await figure(SHOT("sql/sql_06_tde_status.png"), "TDE verified with sys.dm_database_encryption_keys, and both backups searched for plaintext",
    "ShopDB has encryption_state 3 (encrypted) with AES-256, protected by TDE_ShopDB_Cert. SQL Server also encrypts tempdb automatically. In the backup taken before TDE, a product code and a test card number are readable as plain text (2 and 1 matches). In the backup taken after TDE there are 0 matches: a stolen backup is unreadable.");
  H2("8.2 What if the TDE certificate is lost? (restore drill)");
  para("Script 06b_tde_lost_cert_drill.sql simulates moving an encrypted backup to a server without the certificate. It takes an encrypted backup, removes the certificate, tries to restore, recreates the certificate from the .cer/.pvk backup files, and restores again. It finishes by switching TDE back on.");
  await figure(SHOT("sql/sql_06b_lost_cert_drill.png"), "Restore fails without the certificate (Msg 33111) and succeeds after restoring it",
    "without the certificate, SQL Server cannot read the encrypted backup: \"Cannot find server certificate with thumbprint\". After the certificate is recreated from its backup files and password, the restore succeeds with all data intact (customers, orders and products present). Lesson: the certificate, its private key and the password must be backed up and stored safely away from the server. Losing them means losing the data forever.");
  H2("8.3 Column encryption of card numbers");
  para("Inside ShopDB, a database master key protects the certificate CardDataCert, which protects the symmetric key CardDataKey (AES-256). Existing card numbers are encrypted with ENCRYPTBYKEY into CardNumberEnc, only the last 4 digits are kept readable for receipts, and the plaintext column is dropped. The PaymentID is used as an \"authenticator\", so an encrypted value copied to another row will not decrypt. Only admin_role receives permission to use the key; sales and auditors can select the ciphertext but cannot decrypt it. New orders never accept card numbers at all, because a payment gateway handles them (PCI DSS).");
  await figure(SHOT("sql/sql_06_column_encryption.png"), "Authorized user decrypts card numbers; unauthorized user gets NULL",
    "shop_admin (admin_role, has key permission) sees the real card numbers (official test numbers, not real cards). sales_addis can SELECT the same column, but decryption returns NULL, and trying to open the key fails with \"Cannot find the symmetric key … or you do not have permission\".");
  H2("8.4 Data discovery and classification");
  para("Following the lecture's \"Data Protection in Databases\" section, sensitive columns are labelled with ADD SENSITIVITY CLASSIFICATION, so auditing and security tools know what each column contains.");
  await figure(SHOT("sql/sql_06_classification.png"), "Sensitivity labels on the sensitive columns",
    "the card number is labelled Highly Confidential / Credit Card (rank CRITICAL), password hashes and MFA secrets Highly Confidential / Credentials, and customer e-mail and phone Confidential / Contact Info.");
  note([B("Data in motion: "), "the web application connects with Encrypt=yes, so traffic between the app and SQL Server is protected with TLS. In this lab the server certificate is self-signed (TrustServerCertificate=yes); in production a trusted certificate would be installed."]);

  // =========================== 9. MFA ======================================
  H1("9. Multi-factor authentication (optional requirement)");
  note([B("Honest note: "), "SQL Server logins have no built-in MFA (for database logins it exists only with Microsoft Entra ID, e.g. in Azure SQL). Customers and staff log in to the website, so I implemented MFA there."], GOLD, "FFF4DC");
  para("I used TOTP (Time-based One-Time Password, RFC 6238), the 6-digit codes of Google or Microsoft Authenticator. This combines something you know (the password) with something you have (the phone):");
  numbered(["After a correct password, if MFA is enabled, the app does not start the session yet. It asks for the 6-digit code.",
    "The phone and the app share a random 160-bit secret. Both compute the code from the secret plus the current time, and the code changes every 30 seconds.",
    "The secret is encrypted by the app with Fernet (AES + HMAC), using a key that exists only in the .env file. Only the ciphertext is stored in Users.MfaSecretEnc, so a stolen database or backup does not reveal it.",
    "Wrong codes count towards the same 5-attempt lockout as wrong passwords, and every MFA event is written to the audit log (procedures in 07_mfa.sql)."]);
  await figure(SHOT("app/12_mfa_setup_qr.png"), "MFA set-up: the user scans the QR code with an authenticator app",
    "the QR code contains the secret in the standard otpauth:// format. The user confirms the set-up by typing the first code, and only then is MFA enabled.");
  await figure(SHOT("app/14_mfa_second_factor_prompt.png"), "After a correct password, the second factor is required",
    "knowing the password is no longer enough to log in.");
  await figure(SHOT("app/15_mfa_wrong_code.png"), "A wrong one-time code is rejected", "the attempt is counted and audited.");
  await figure(SHOT("app/16_mfa_login_success.png"), "Login completed with password + one-time code",
    "the header shows that the session was created through the \"hardened + MFA\" path.");
  await figure(SHOT("sql/sql_07_mfa.png"), "MFA procedures tested as the website login",
    "storing the encrypted secret, recording a wrong code (attempt counted) and recording a correct code, each with an audit entry.");

  // =========================== 10. AUDIT ===================================
  H1("10. Auditing and monitoring");
  para("Every security-relevant event is written to dbo.AuditLog by the stored procedures: successful and failed logins, rejected input, lockouts, password changes, registrations, orders, MFA events and internal errors. The database login that performed the action is recorded automatically (ORIGINAL_LOGIN()). The log is append-only: UPDATE and DELETE are denied to every role, including admin, and auditors have read-only access.");
  await figure(SHOT("sql/sql_audit_log.png"), "The audit log after running the automated tests",
    "the complete story of a test user is visible: registration, MFA set-up, password login, a wrong MFA code, a successful MFA login, four failed passwords, the lockout and a blocked attempt while locked. The rejected injection attempt (LOGIN_REJECTED_INPUT) is recorded too. (The jump in AuditID numbers is normal: SQL Server pre-allocates identity values and skips some after a restart.)");

  // =========================== 11. TESTING =================================
  H1("11. Testing and verification");
  para("To make sure everything really works, and not only on my screen, I wrote app/smoke_test.py. It uses the running website like a browser and checks 22 security behaviours. I also re-ran every SQL script a second time to prove they are idempotent, and rebuilt everything from an empty server several times.");
  await figure(SHOT("sql/smoke_test.png"), "22 out of 22 automated end-to-end security checks pass",
    "SQL-injection attacks succeed on the vulnerable path and fail on the hardened path; the sort-column injection is ignored; RLS shows only the customer's own orders; order validation works; forms without the CSRF token are refused; the password policy rejects a weak password; MFA works (enable, password-only refused, wrong code rejected, correct code accepted); and lockout blocks even the correct password.");
  table(["Test area", "Result"], [
    ["Constraints (4 invalid inserts)", "All 4 rejected"],
    ["Password policy (SQL logins + website)", "Weak rejected, strong accepted, reuse blocked"],
    ["RBAC permission matrix (10 actions × 6 users)", "Exactly as designed; website login denied on all tables"],
    ["ABAC / RLS (same query, 5 users)", "10 / 10 / 10 / 4 / 3 rows; masking for support"],
    ["SQL injection (login, UNION, stacked query, error leak, sort column)", "Vulnerable path compromised; hardened path blocked every attack"],
    ["Lockout", "Locked after 5 failures, correct password refused while locked"],
    ["TDE", "encryption_state 3; plaintext only in the pre-TDE backup"],
    ["Certificate loss drill", "Msg 33111 without certificate; success after restoring it"],
    ["Column encryption", "Admin decrypts; sales gets NULL"],
    ["MFA", "Password alone refused; TOTP required; secret stored encrypted"],
    ["Automated smoke test", "22/22 passed"],
    ["Idempotency", "All scripts re-run without errors; full rebuild ≈ 10 s"],
  ], [5200, 3826], { caption: "Summary of test results", boldFirst: true });

  // =========================== 12. LIMITATIONS =============================
  H1("12. Limitations and future improvements");
  table(["Limitation (honest)", "What I would do in production"], [
    ["SQL Server has no native ABAC", "Keep RLS + attributes; add more attributes (time of day, device) to the predicate"],
    ["No MFA for SQL Server logins", "Use Windows / Microsoft Entra authentication with MFA for staff"],
    ["Iterated SHA-512 in T-SQL", "bcrypt or Argon2 in the application layer"],
    ["Cell-level encryption does not hide data from a sysadmin", "Always Encrypted (keys stay in the client application)"],
    ["Audit log is a normal table", "SQL Server Audit to a protected file + alerts in a SIEM (e.g. Microsoft Sentinel)"],
    ["Self-signed TLS certificate in the lab", "Trusted certificate, Force Encryption on the server"],
    ["Dynamic Data Masking can be bypassed by inference queries", "Combine with RLS and least privilege (done); never rely on masking alone"],
  ], [4300, 4726], { caption: "Limitations and next steps" });

  // =========================== 13. CONCLUSION ==============================
  H1("13. Conclusion");
  para("This project shows that database security is not one feature but several layers, where each layer still protects the data if another one fails:");
  bullets([[B("Network: "), "the app listens only on 127.0.0.1 and uses an encrypted connection."],
    [B("Authentication: "), "a strong password policy at two levels, account lockout and TOTP multi-factor authentication."],
    [B("Authorization: "), "RBAC with least privilege, ABAC with Row-Level Security, and dynamic data masking."],
    [B("Query hardening: "), "stored procedures, parameters, allow-list validation and safe error handling."],
    [B("Data protection: "), "TDE for data at rest, column encryption for card numbers, certificate backup and data classification."],
    [B("Monitoring: "), "an append-only audit log."]]);
  para("The live comparison of the vulnerable and the hardened paths shows the difference clearly. The same attacker input that logs in without a password, steals password hashes and changes prices on the vulnerable path is completely harmless on the hardened path. Every result is reproducible: one command rebuilds the system, and 22 automated checks confirm that it behaves as described.");

  // =========================== APPENDICES ==================================
  H1("Appendix A: How to run the project");
  numbered(["Install SQL Server 2022 Developer (Mixed Mode authentication), SSMS, ODBC Driver 18 and Python 3.",
    "Copy .env.example to .env and set your own strong passwords and keys.",
    "In PowerShell, in the project folder: .\\run_sql.ps1 (runs 01 → 07). Optional: .\\run_sql.ps1 sql\\06b_tde_lost_cert_drill.sql",
    "Start the app: cd app → python -m venv .venv → .\\.venv\\Scripts\\Activate.ps1 → pip install -r requirements.txt → python app.py, then open http://127.0.0.1:5000",
    "Verify: python smoke_test.py should print 22/22 checks passed.",
    "Live demo queries: open sql/99_demo_queries.sql in SSMS and run blocks D1–D10."]);
  para("Full details, expected output for every script and troubleshooting are in README.md.");
  H2("Sample website accounts (password = DEMO_USER_PASSWORD from .env)");
  table(["Username", "Role", "Notes"], [
    ["selam.g", "Customer (Addis Ababa)", "Orders 1001 and 1009"], ["liya.t", "Customer (Hawassa)", "Orders 1003 and 1010"],
    ["yonas.b, samuel.g, bethel.a, kidus.w", "Customer", ""], ["admin.tsehay", "Admin", "Used for the MFA demo"],
    ["sales.abebe, support.dawit, audit.meron", "Staff", ""],
  ], [3600, 2600, 2826]);
  H1("Appendix B: List of figures");
  body.push(P(I("All figures were captured from the running system: browser screenshots of the Flask application, and sqlcmd output of the SQL scripts rendered as images. The file names are listed in screenshots/SCREENSHOTS.md.")));
  table(["Figure", "Caption", "Source file"], FIGS.map(([n, c, f]) => [String(n), c, f.replace("presentation/img/", "cropped: ")]),
    [800, 5200, 3026], { size: 17 });

  // =========================== DOCUMENT ====================================
  const doc = new Document({
    creator: "ShopDB project", title: "Securing an E-commerce Database",
    description: "Database Security practical implementation report",
    features: { updateFields: true },
    styles: {
      default: { document: { run: { font: "Calibri", size: 22 } } },
      paragraphStyles: [
        { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: "Cambria", size: 34, bold: true, color: NAVY }, paragraph: { spacing: { before: 240, after: 160 }, keepNext: true, outlineLevel: 0 } },
        { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: "Cambria", size: 27, bold: true, color: TEAL }, paragraph: { spacing: { before: 240, after: 120 }, keepNext: true, outlineLevel: 1 } },
        { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: "Cambria", size: 24, bold: true, color: NAVY }, paragraph: { spacing: { before: 180, after: 100 }, keepNext: true, outlineLevel: 2 } },
      ],
    },
    numbering: { config: [
      { reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 540, hanging: 300 } } } }] },
      { reference: "numbers", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 540, hanging: 360 } } } }] },
    ] },
    sections: [{
      properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } },
        titlePage: true },
      headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
        children: [new TextRun({ text: "ShopDB · Database Security Practical Implementation", size: 18, color: GREY })] })] }) },
      footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
        children: [new TextRun({ children: ["Page ", PageNumber.CURRENT, " of ", PageNumber.TOTAL_PAGES], size: 18, color: GREY })] })] }) },
      children: [...cover, ...toc, ...body],
    }],
  });
  const out = path.join(ROOT, "docs", "ShopDB_Database_Security_Report.docx");
  fs.writeFileSync(out, await Packer.toBuffer(doc));
  console.log("wrote", out, "figures:", fig, "tables:", tab);
})().catch((e) => { console.error(e); process.exit(1); });
