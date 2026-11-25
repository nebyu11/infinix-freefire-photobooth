"""
ShopDB - demo e-commerce web shop (Flask) that shows database security
=======================================================================

Run:   python app.py      then open  http://127.0.0.1:5000

PAGES AND THE SECURITY FEATURE EACH ONE DEMONSTRATES
  /                 Storefront: product search through app.sp_SearchProducts
                    (parameters + allow-listed sort column)
  /cart, /checkout  Cart + checkout: app.sp_PlaceOrderCart; the customer comes
                    from SESSION_CONTEXT, never from the form (no IDOR)
  /login, /register Hardened login (lockout, MFA) and registration (password policy)
  /account          My orders (Row-Level Security), change password, MFA set-up
  /staff            STAFF PORTAL: staff log in with their OWN SQL Server login,
                    so every query runs with their real permissions -> RBAC,
                    ABAC (RLS), masking and column encryption visible in the browser
  /lab              SECURITY LAB: deliberately vulnerable vs hardened login/search
                    (SQL injection demo, localhost only)

TWO DATABASE LOGINS USED BY THE WEBSITE ITSELF
  shop_app    hardened path; may ONLY execute procedures in schema [app]
  legacy_app  vulnerable lab path only; over-privileged on purpose (anti-pattern)

The vulnerable routes exist only when ENABLE_VULNERABLE_DEMO=1 and only answer
requests from this computer. The app listens on 127.0.0.1 only.
"""

import base64
import io
import json
import os
import secrets
import time
from functools import wraps
from pathlib import Path

import pyodbc
import pyotp
import qrcode
from cryptography.fernet import Fernet, InvalidToken
from dotenv import load_dotenv
from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)

# ---------------------------------------------------------------------------
# Configuration: everything secret comes from ../.env (never from the code)
# ---------------------------------------------------------------------------
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

DB_SERVER = os.getenv("DB_SERVER", "localhost")
DB_NAME = os.getenv("DB_NAME", "ShopDB")
ODBC_DRIVER = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
VULN_ENABLED = os.getenv("ENABLE_VULNERABLE_DEMO", "0") == "1"
fernet = Fernet(os.environ["MFA_ENCRYPTION_KEY"].encode())

# Connection pooling OFF: every request opens a fresh connection, so the
# read-only SESSION_CONTEXT (CustomerID) of one user can never be reused by
# the next request. For a small demo the extra few milliseconds don't matter.
pyodbc.pooling = False

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ["FLASK_SECRET_KEY"],  # signs the session cookie
    SESSION_COOKIE_HTTPONLY=True,               # JavaScript cannot read it
    SESSION_COOKIE_SAMESITE="Lax",              # basic CSRF protection
)

CATEGORIES = ["Electronics", "Clothing", "Home", "Books", "Food"]
PAYMENT_METHODS = ["Telebirr", "CBE Birr", "Card", "Cash on Delivery"]
SORTS = {"Name": "Name", "Price": "Price", "Category": "Category"}
MAX_CART_LINES, MAX_QTY = 10, 10

# The ONLY SQL logins that may use the staff portal (never sa, shop_app, legacy_app)
STAFF_LOGINS = ["shop_admin", "sales_addis", "sales_hawassa", "support_dawit", "auditor_meron"]


def connect(uid: str, pwd: str) -> pyodbc.Connection:
    """Open an encrypted (TLS) connection with the given SQL Server login."""
    return pyodbc.connect(
        f"DRIVER={{{ODBC_DRIVER}}};SERVER={DB_SERVER};DATABASE={DB_NAME};"
        f"UID={uid};PWD={pwd};Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=True, timeout=5)


def secure_conn() -> pyodbc.Connection:
    """Hardened website connection (shop_app). If a customer is logged in, their
    CustomerID goes into SESSION_CONTEXT (read-only): Row-Level Security and the
    order procedures use it, so a customer can only see/create their own orders."""
    conn = connect("shop_app", os.environ["APP_PASSWORD"])
    user = session.get("user")
    if user and user.get("customer_id"):
        conn.execute("EXEC sys.sp_set_session_context @key = N'CustomerID', @value = ?, @read_only = 1",
                     user["customer_id"])
    return conn


def rows_as_dicts(cursor) -> list[dict]:
    cols = [c[0] for c in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def call_proc(sql: str, *params) -> list[dict]:
    """Execute a stored procedure with PARAMETERS. The '?' placeholders are
    sent separately from the SQL text, so input can never become SQL code."""
    with secure_conn() as conn:
        cur = conn.execute(sql, params)
        while cur.description is None and cur.nextset():   # skip non-result messages
            pass
        return rows_as_dicts(cur) if cur.description else []


def all_products() -> dict:
    """ProductID -> product (used by the cart)."""
    return {p["ProductID"]: p for p in call_proc("EXEC app.sp_SearchProducts")}


# ---------------------------------------------------------------------------
# Small security helpers
# ---------------------------------------------------------------------------
def csrf_token() -> str:
    """One random token per session; every POST form must send it back."""
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


def cart_count() -> int:
    return sum(session.get("cart", {}).values())


app.jinja_env.globals.update(csrf_token=csrf_token, vuln_enabled=VULN_ENABLED, cart_count=cart_count,
                             categories=CATEGORIES)


@app.before_request
def check_csrf():
    if request.method == "POST":
        if not secrets.compare_digest(request.form.get("csrf", ""), session.get("csrf", "")):
            abort(400, "Invalid form token")


@app.after_request
def security_headers(resp):
    resp.headers["X-Frame-Options"] = "DENY"                 # no clickjacking
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data:"
    resp.headers["Referrer-Policy"] = "no-referrer"
    return resp


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not session.get("user"):
            flash("Please log in first.", "error")
            return redirect(url_for("login_page"))
        return view(*args, **kwargs)
    return wrapper


def local_lab_only(view):
    """Vulnerable routes: only when enabled AND only from this computer."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not VULN_ENABLED or request.remote_addr not in ("127.0.0.1", "::1"):
            abort(404)
        return view(*args, **kwargs)
    return wrapper


def start_session(user: dict, via: str):
    """Log the user in. session.clear() first = new session after login
    (prevents session fixation). The cart is kept."""
    cart = session.get("cart", {})
    session.clear()
    session["user"] = {"id": user["UserID"], "username": user["Username"], "role": user["Role"],
                       "customer_id": user.get("CustomerID"), "via": via}
    session["cart"] = cart
    csrf_token()


# ======================= STOREFRONT ========================================
@app.get("/")
def shop():
    q = request.args.get("q", "")[:50]
    category = request.args.get("category", "")
    category = category if category in CATEGORIES else None
    sort = request.args.get("sort", "Name")
    sort_by, sort_dir = (("Price", "DESC") if sort == "PriceDesc" else (SORTS.get(sort, "Name"), "ASC"))
    products = call_proc("EXEC app.sp_SearchProducts @SearchTerm = ?, @Category = ?, @SortBy = ?, @SortDir = ?",
                         q or None, category, sort_by, sort_dir)
    return render_template("shop.html", products=products, q=q, category=category, sort=sort,
                           call=f"EXEC app.sp_SearchProducts @SearchTerm = ?, @Category = ?, @SortBy = ?, @SortDir = ?"
                                f"   -- values sent separately: {[q or None, category, sort_by, sort_dir]}")


# ======================= CART & CHECKOUT ===================================
def _int(name, lo, hi):
    try:
        v = int(request.form.get(name, ""))
    except ValueError:
        return None
    return v if lo <= v <= hi else None


@app.post("/cart/add")
def cart_add():
    pid, qty = _int("product_id", 1, 10**6), _int("quantity", 1, MAX_QTY)
    if pid is None or qty is None:
        flash(f"Quantity must be between 1 and {MAX_QTY}.", "error")
        return redirect(request.referrer or url_for("shop"))
    cart = session.get("cart", {})
    if str(pid) not in cart and len(cart) >= MAX_CART_LINES:
        flash(f"A cart can hold at most {MAX_CART_LINES} different products.", "error")
    else:
        cart[str(pid)] = min(MAX_QTY, cart.get(str(pid), 0) + qty)
        session["cart"] = cart
        flash("Added to your cart.", "ok")
    return redirect(request.referrer or url_for("shop"))


@app.post("/cart/update")
def cart_update():
    pid, qty = _int("product_id", 1, 10**6), _int("quantity", 0, MAX_QTY)
    cart = session.get("cart", {})
    if pid is not None and qty is not None:
        if qty == 0:
            cart.pop(str(pid), None)
        elif str(pid) in cart:
            cart[str(pid)] = qty
        session["cart"] = cart
    return redirect(url_for("cart"))


@app.get("/cart")
def cart():
    products = all_products()
    lines, total = [], 0
    for pid, qty in session.get("cart", {}).items():
        p = products.get(int(pid))
        if p:
            lines.append({"p": p, "qty": qty, "subtotal": p["Price"] * qty})
            total += p["Price"] * qty
    return render_template("cart.html", lines=lines, total=total, methods=PAYMENT_METHODS)


@app.post("/checkout")
def checkout():
    user = session.get("user")
    if not user or not user.get("customer_id"):
        flash("Please log in with a customer account to check out.", "error")
        return redirect(url_for("login_page"))
    cart = session.get("cart", {})
    if not cart:
        flash("Your cart is empty.", "error")
        return redirect(url_for("cart"))
    items = json.dumps([{"p": int(k), "q": v} for k, v in cart.items()])
    rows = call_proc("EXEC app.sp_PlaceOrderCart @ItemsJson = ?, @PaymentMethod = ?",
                     items, request.form.get("method", ""))
    r = rows[0]
    if r["ResultCode"] == 0:
        session["cart"] = {}
        flash(f"Thank you! Order #{r['OrderID']} was placed.", "ok")
        return redirect(url_for("account"))
    flash(r["Message"], "error")
    return redirect(url_for("cart"))


# ======================= CUSTOMER ACCOUNTS (HARDENED) ======================
@app.get("/login")
def login_page():
    return render_template("login.html")


@app.post("/login")
def login():
    back = url_for("lab") if request.form.get("next") == "lab" else url_for("login_page")
    rows = call_proc("EXEC app.sp_Login @Username = ?, @Password = ?",
                     request.form.get("username", "")[:30], request.form.get("password", "")[:128])
    result = rows[0] if rows else {"ResultCode": 1, "Message": "Login failed."}
    if result["ResultCode"] != 0:
        flash(result["Message"], "error")
        return redirect(back)

    if result["MfaEnabled"]:
        # password OK, but the second factor is still missing
        cart = session.get("cart", {})
        session.clear()
        session["cart"] = cart
        session["mfa_pending"] = {"id": result["UserID"], "username": result["Username"],
                                  "role": result["Role"], "customer_id": result["CustomerID"]}
        return redirect(url_for("mfa_verify"))

    start_session(result, via="hardened")
    flash(f"Welcome {result['Username']} (logged in through the HARDENED path).", "ok")
    return redirect(url_for("shop"))


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        f = request.form
        rows = call_proc("EXEC app.sp_RegisterCustomer ?, ?, ?, ?, ?, ?, ?, ?",
                         f.get("username", ""), f.get("password", ""), f.get("first", ""),
                         f.get("last", ""), f.get("email", ""), f.get("phone", ""),
                         f.get("city", ""), f.get("region", ""))
        flash(rows[0]["Message"], "ok" if rows[0]["ResultCode"] == 0 else "error")
        if rows[0]["ResultCode"] == 0:
            return redirect(url_for("login_page"))
    return render_template("register.html")


@app.route("/account", methods=["GET", "POST"])
@login_required
def account():
    if request.method == "POST":
        rows = call_proc(
            "SET NOCOUNT ON; DECLARE @r INT, @m NVARCHAR(400); "
            "EXEC app.sp_ChangePassword ?, ?, ?, @r OUTPUT, @m OUTPUT; SELECT @r AS ResultCode, @m AS Message;",
            session["user"]["username"], request.form.get("old", ""), request.form.get("new", ""))
        flash(rows[0]["Message"], "ok" if rows[0]["ResultCode"] == 0 else "error")
    # app.sp_GetMyOrders has NO WHERE clause: Row-Level Security filters rows
    orders = call_proc("EXEC app.sp_GetMyOrders") if session["user"].get("customer_id") else []
    return render_template("account.html", orders=orders)


# ----------------------------- MFA (TOTP) ----------------------------------
@app.route("/mfa/setup", methods=["GET", "POST"])
@login_required
def mfa_setup():
    user = session["user"]
    if request.method == "GET":
        # 1. new random secret (160 bits), stored ENCRYPTED, not enabled yet
        secret = pyotp.random_base32()
        call_proc("EXEC app.sp_SaveMfaSecret @UserID = ?, @SecretEnc = ?",
                  user["id"], fernet.encrypt(secret.encode()))
        uri = pyotp.TOTP(secret).provisioning_uri(name=user["username"], issuer_name="ShopDB Demo")
        img = io.BytesIO()
        qrcode.make(uri).save(img, format="PNG")
        qr = base64.b64encode(img.getvalue()).decode()
        return render_template("mfa_setup.html", qr=qr, secret=secret)

    # 2. user types the first code from the phone -> enable MFA
    if _check_totp(user["id"], request.form.get("code", "")):
        call_proc("EXEC app.sp_EnableMfa @UserID = ?", user["id"])
        flash("MFA enabled. From now on you need your phone to log in.", "ok")
        return redirect(url_for("account"))
    flash("Wrong code - scan the QR code again.", "error")
    return redirect(url_for("mfa_setup"))


@app.route("/mfa/verify", methods=["GET", "POST"])
def mfa_verify():
    pending = session.get("mfa_pending")
    if not pending:
        return redirect(url_for("login_page"))
    if request.method == "POST":
        ok = _check_totp(pending["id"], request.form.get("code", ""))
        rows = call_proc("EXEC app.sp_RecordMfaResult @UserID = ?, @Success = ?", pending["id"], ok)
        if ok:
            start_session({"UserID": pending["id"], "Username": pending["username"],
                           "Role": pending["role"], "CustomerID": pending["customer_id"]}, via="hardened + MFA")
            flash(f"Welcome {pending['username']} (password + one-time code).", "ok")
            return redirect(url_for("shop"))
        flash(rows[0]["Message"], "error")
        if rows[0]["ResultCode"] == 2:      # locked
            session.pop("mfa_pending", None)
            return redirect(url_for("login_page"))
    return render_template("mfa_verify.html", username=pending["username"])


def _check_totp(user_id: int, code: str) -> bool:
    """Decrypt the stored secret and compare the 6-digit code.
    valid_window=1 accepts the previous/next 30-second code (clock drift)."""
    code = code.strip()
    if not (code.isdigit() and len(code) == 6):
        return False
    rows = call_proc("EXEC app.sp_GetMfaSecret @UserID = ?", user_id)
    if not rows or not rows[0]["MfaSecretEnc"]:
        return False
    try:
        secret = fernet.decrypt(bytes(rows[0]["MfaSecretEnc"])).decode()
    except InvalidToken:
        return False
    return pyotp.TOTP(secret).verify(code, valid_window=1)


@app.post("/logout")
def logout():
    cart = session.get("cart", {})
    session.clear()
    session["cart"] = cart
    flash("Logged out.", "ok")
    return redirect(url_for("shop"))


# ======================= STAFF PORTAL ======================================
# Staff authenticate DIRECTLY against SQL Server with their own login
# (CHECK_POLICY / CHECK_EXPIRATION apply). Every query on the dashboard runs
# as that login, so SQL Server itself decides what they may see - the web
# page only displays the result or the "permission denied" error.
#
# The SQL password must be re-used for each request, but it is NOT put in the
# cookie: it stays in this server's memory (STAFF_SESSIONS), referenced by a
# random token, and expires after 30 minutes or at logout.
STAFF_SESSIONS: dict[str, dict] = {}
STAFF_TTL = 30 * 60


def staff_conn():
    token = session.get("staff_token")
    s = STAFF_SESSIONS.get(token or "")
    if not s or s["expires"] < time.time():
        STAFF_SESSIONS.pop(token or "", None)
        return None, None
    s["expires"] = time.time() + STAFF_TTL
    return connect(s["login"], s["pwd"]), s["login"]


# Each check runs inside a transaction that is ALWAYS rolled back,
# so the portal never changes data - it only asks SQL Server "may I?".
STAFF_CHECKS = [
    ("Read orders", "SELECT COUNT(*) FROM dbo.Orders", "count"),
    ("Change order status", "UPDATE dbo.Orders SET Status = Status", "rows"),
    ("Change product prices", "UPDATE dbo.Products SET Price = Price", "rows"),
    ("Decrypt card numbers", "SELECT COUNT(CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), "
                             "NULL, CardNumberEnc, 1, CONVERT(VARBINARY(4), PaymentID)))) FROM dbo.Payments", "decrypt"),
    ("Read password hashes", "SELECT TOP (1) PasswordHash FROM dbo.Users", "plain"),
    ("Read the audit log", "SELECT COUNT(*) FROM dbo.AuditLog", "count"),
    ("Delete the audit log (hide tracks)", "DELETE FROM dbo.AuditLog", "rows"),
    ("Drop a table", "DROP TABLE dbo.Customers", "plain"),
]

STAFF_PANELS = [
    ("orders", "Orders", "SELECT OrderID, CustomerID, CONVERT(VARCHAR(10), OrderDate, 120) AS OrderDate, Status, "
                         "ShipRegion, TotalAmount FROM dbo.Orders ORDER BY OrderID",
     "Row-Level Security: you only get the rows your Region attribute allows."),
    ("customers", "Customers", "SELECT CustomerID, FirstName, LastName, Email, Phone, Region FROM dbo.Customers "
                               "ORDER BY CustomerID",
     "Row-Level Security + Dynamic Data Masking on Email and Phone."),
    ("payments", "Payments", "SELECT PaymentID, OrderID, Amount, Method, Status, CardLast4, "
                             "CONVERT(VARCHAR(19), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CardDataCert'), NULL, CardNumberEnc, 1, "
                             "CONVERT(VARBINARY(4), PaymentID))) AS CardNumber FROM dbo.Payments ORDER BY PaymentID",
     "Column-level permissions + column encryption: only the key holder sees card numbers."),
    ("audit", "Audit log", "SELECT TOP (15) AuditID, CONVERT(VARCHAR(19), EventTime, 120) AS EventTime, EventType, "
                           "AppUsername, DbLogin, LEFT(Details, 60) AS Details FROM dbo.AuditLog ORDER BY AuditID DESC",
     "Only admin and auditor may read the audit trail."),
]


def _short_error(e: pyodbc.Error) -> str:
    msg = str(e.args[1]) if len(e.args) > 1 else str(e)
    msg = msg.split("[SQL Server]")[-1]
    return msg.split(" (")[0].strip()


@app.route("/staff/login", methods=["GET", "POST"])
def staff_login():
    if request.method == "POST":
        login_name = request.form.get("login", "")
        pwd = request.form.get("password", "")
        if login_name not in STAFF_LOGINS:
            flash("This portal is for staff accounts only.", "error")
            return redirect(url_for("staff_login"))
        try:
            connect(login_name, pwd).close()      # SQL Server checks the password
        except pyodbc.Error:
            flash("Login failed.", "error")       # same message for every failure
            return redirect(url_for("staff_login"))
        token = secrets.token_urlsafe(32)
        STAFF_SESSIONS[token] = {"login": login_name, "pwd": pwd, "expires": time.time() + STAFF_TTL}
        session["staff_token"] = token
        return redirect(url_for("staff"))
    return render_template("staff_login.html", logins=STAFF_LOGINS)


@app.get("/staff")
def staff():
    conn, login_name = staff_conn()
    if not conn:
        return redirect(url_for("staff_login"))
    with conn:
        me = rows_as_dicts(conn.execute("EXEC sec.sp_MyAttributes"))[0]
        checks = []
        for label, sql, kind in STAFF_CHECKS:
            conn.autocommit = False
            try:
                cur = conn.execute(sql)
                if kind == "count":
                    detail = f"{cur.fetchone()[0]} rows visible"
                elif kind == "rows":
                    detail = f"{cur.rowcount} rows (rolled back)"
                elif kind == "decrypt":
                    n = cur.fetchone()[0]
                    detail = f"{n} decrypted" if n else "query runs, but 0 decrypted (no key permission)"
                else:
                    detail = "allowed (rolled back)"
                ok = not (kind == "decrypt" and n == 0)
                checks.append({"label": label, "ok": ok, "detail": detail, "sql": sql})
            except pyodbc.Error as e:
                checks.append({"label": label, "ok": False, "detail": _short_error(e), "sql": sql})
            finally:
                conn.rollback()
                conn.autocommit = True
        panels = []
        for key, title, sql, why in STAFF_PANELS:
            try:
                rows = rows_as_dicts(conn.execute(sql))
                panels.append({"key": key, "title": title, "rows": rows, "error": None, "sql": sql, "why": why})
            except pyodbc.Error as e:
                panels.append({"key": key, "title": title, "rows": [], "error": _short_error(e), "sql": sql, "why": why})
    return render_template("staff.html", me=me, checks=checks, panels=panels, login_name=login_name)


@app.post("/staff/logout")
def staff_logout():
    STAFF_SESSIONS.pop(session.pop("staff_token", ""), None)
    flash("Logged out of the staff portal.", "ok")
    return redirect(url_for("staff_login"))


# ======================= SECURITY LAB ======================================
@app.get("/lab")
@local_lab_only
def lab():
    return render_template("lab.html")


@app.get("/lab/search")
@local_lab_only
def lab_search():
    q = request.args.get("q", "")[:50]
    products = call_proc("EXEC app.sp_SearchProducts @SearchTerm = ?", q)
    return render_template("lab.html", products=products, q=q, mode="hardened",
                           sql_shown=f"EXEC app.sp_SearchProducts @SearchTerm = ?   -- value sent separately: {[q]}")


# !!! NEVER WRITE CODE LIKE THIS. It exists only to demonstrate the attack. !!!
@app.post("/vuln/login")
@local_lab_only
def vuln_login():
    u = request.form.get("username", "")
    p = request.form.get("password", "")
    # BAD: user input is pasted straight into the SQL text
    sql = ("SELECT TOP 1 UserID, Username, Role, CustomerID FROM dbo.Users "
           f"WHERE Username = N'{u}' AND PasswordHash = dbo.fn_HashPassword(N'{p}', PasswordSalt)")
    try:
        with connect("legacy_app", os.environ["LEGACY_APP_PASSWORD"]) as conn:
            row = conn.execute(sql).fetchone()
    except pyodbc.Error as e:
        # BAD: raw database error shown to the user (leaks table/column names)
        return render_template("lab.html", vuln_sql=sql, vuln_error=str(e))
    if not row:
        return render_template("lab.html", vuln_sql=sql, vuln_error="Invalid username or password.")
    start_session({"UserID": row.UserID, "Username": row.Username, "Role": row.Role,
                   "CustomerID": row.CustomerID}, via="VULNERABLE")
    flash(f"Logged in as {row.Username} ({row.Role}) through the VULNERABLE path.", "warn")
    return render_template("lab.html", vuln_sql=sql)


@app.get("/vuln/search")
@local_lab_only
def vuln_search():
    q = request.args.get("q", "")
    # BAD: string concatenation again
    sql = f"SELECT Name, Category, Price FROM dbo.Products WHERE IsActive = 1 AND Name LIKE N'%{q}%'"
    try:
        with connect("legacy_app", os.environ["LEGACY_APP_PASSWORD"]) as conn:
            cur = conn.execute(sql)
            products = rows_as_dicts(cur) if cur.description else []
    except pyodbc.Error as e:
        return render_template("lab.html", vuln_sql=sql, vuln_error=str(e), q=q)
    return render_template("lab.html", products=products, q=q, mode="vulnerable", vuln_sql=sql)


@app.errorhandler(Exception)
def generic_error(e):
    """Hardened behaviour: log details on the server, show a generic message."""
    if hasattr(e, "code") and isinstance(e.code, int):      # normal HTTP errors (404, 400)
        return e
    app.logger.exception("Unhandled error")
    return render_template("error.html"), 500


if __name__ == "__main__":
    # 127.0.0.1 = reachable from this computer only. debug=False: no stack traces.
    app.run(host="127.0.0.1", port=5000, debug=False)
