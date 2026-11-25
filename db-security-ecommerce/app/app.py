"""
ShopDB demo web app (Flask) - SQL injection: vulnerable vs hardened
=====================================================================

Run:   python app.py      then open  http://127.0.0.1:5000

The page shows TWO ways to log in and search:

  RED  "vulnerable" path  (LAB DEMO ONLY)
       - builds SQL by gluing user input into a string (f-string)
       - connects as legacy_app, an over-privileged login (db_datareader +
         db_datawriter), like many badly configured real apps
       - shows the raw database error to the user (information leak)

  GREEN "hardened" path
       - calls stored procedures in schema [app] with PARAMETERS (?)
       - connects as shop_app, which may ONLY execute those procedures
       - generic error messages, account lockout, optional TOTP MFA

The vulnerable routes are only registered when ENABLE_VULNERABLE_DEMO=1 and
only answer requests from this computer (127.0.0.1). The app itself listens
on 127.0.0.1 only, so nobody else on the network can reach it.
"""

import base64
import io
import os
import secrets
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


def connect(login: str) -> pyodbc.Connection:
    """Open a connection as 'shop_app' (hardened) or 'legacy_app' (vulnerable)."""
    password = os.environ["APP_PASSWORD" if login == "shop_app" else "LEGACY_APP_PASSWORD"]
    conn = pyodbc.connect(
        f"DRIVER={{{ODBC_DRIVER}}};SERVER={DB_SERVER};DATABASE={DB_NAME};"
        f"UID={login};PWD={password};Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=True, timeout=5)
    return conn


def secure_conn() -> pyodbc.Connection:
    """Hardened connection. If a customer is logged in, store their CustomerID
    in SESSION_CONTEXT (read-only) - Row-Level Security (04_abac.sql) and the
    order procedures use it, so a customer can only ever see/create their own
    orders. A fresh connection per request keeps users apart (pooling is off)."""
    conn = connect("shop_app")
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


# ---------------------------------------------------------------------------
# Small security helpers
# ---------------------------------------------------------------------------
def csrf_token() -> str:
    """One random token per session; every POST form must send it back."""
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


app.jinja_env.globals["csrf_token"] = csrf_token
app.jinja_env.globals["vuln_enabled"] = VULN_ENABLED


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
            return redirect(url_for("index"))
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
    (prevents session fixation)."""
    session.clear()
    session["user"] = {"id": user["UserID"], "username": user["Username"], "role": user["Role"],
                       "customer_id": user.get("CustomerID"), "via": via}
    csrf_token()


# ---------------------------------------------------------------------------
# Home page: search + both login forms
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")


# ======================= HARDENED (GREEN) PATH ==============================
@app.post("/login")
def login():
    rows = call_proc("EXEC app.sp_Login @Username = ?, @Password = ?",
                     request.form.get("username", "")[:30], request.form.get("password", "")[:128])
    result = rows[0] if rows else {"ResultCode": 1, "Message": "Login failed."}
    if result["ResultCode"] != 0:
        flash(result["Message"], "error")
        return redirect(url_for("index"))

    if result["MfaEnabled"]:
        # password OK, but the second factor is still missing
        session.clear()
        session["mfa_pending"] = {"id": result["UserID"], "username": result["Username"],
                                  "role": result["Role"], "customer_id": result["CustomerID"]}
        return redirect(url_for("mfa_verify"))

    start_session(result, via="hardened")
    flash(f"Welcome {result['Username']} (logged in through the HARDENED path).", "ok")
    return redirect(url_for("index"))


@app.get("/search")
def search():
    q = request.args.get("q", "")[:50]
    sort = request.args.get("sort", "Name")[:20]
    direction = request.args.get("dir", "ASC")[:4]
    products = call_proc("EXEC app.sp_SearchProducts @SearchTerm = ?, @SortBy = ?, @SortDir = ?",
                         q, sort, direction)
    return render_template("index.html", products=products, q=q, mode="hardened",
                           sql_shown="EXEC app.sp_SearchProducts @SearchTerm = ?, @SortBy = ?, @SortDir = ?"
                                     f"   -- parameters sent separately: {[q, sort, direction]}")


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
            return redirect(url_for("index"))
    return render_template("register.html")


@app.get("/orders")
@login_required
def orders():
    if not session["user"].get("customer_id"):
        flash("Only customer accounts have orders.", "error")
        return redirect(url_for("index"))
    # app.sp_GetMyOrders has NO WHERE clause: Row-Level Security filters rows
    return render_template("orders.html", orders=call_proc("EXEC app.sp_GetMyOrders"))


@app.post("/order")
@login_required
def place_order():
    try:
        product_id = int(request.form["product_id"])
        quantity = int(request.form["quantity"])
    except (KeyError, ValueError):
        flash("Invalid order.", "error")
        return redirect(url_for("index"))
    rows = call_proc("EXEC app.sp_PlaceOrder @ProductID = ?, @Quantity = ?, @PaymentMethod = ?",
                     product_id, quantity, request.form.get("method", ""))
    flash(rows[0]["Message"] + (f" (order #{rows[0]['OrderID']})" if rows[0]["OrderID"] else ""),
          "ok" if rows[0]["ResultCode"] == 0 else "error")
    return redirect(url_for("orders") if rows[0]["ResultCode"] == 0 else url_for("index"))


@app.route("/account", methods=["GET", "POST"])
@login_required
def account():
    if request.method == "POST":
        rows = call_proc(
            "SET NOCOUNT ON; DECLARE @r INT, @m NVARCHAR(400); "
            "EXEC app.sp_ChangePassword ?, ?, ?, @r OUTPUT, @m OUTPUT; SELECT @r AS ResultCode, @m AS Message;",
            session["user"]["username"], request.form.get("old", ""), request.form.get("new", ""))
        flash(rows[0]["Message"], "ok" if rows[0]["ResultCode"] == 0 else "error")
    return render_template("account.html")


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
        return redirect(url_for("index"))
    if request.method == "POST":
        ok = _check_totp(pending["id"], request.form.get("code", ""))
        rows = call_proc("EXEC app.sp_RecordMfaResult @UserID = ?, @Success = ?", pending["id"], ok)
        if ok:
            start_session({"UserID": pending["id"], "Username": pending["username"],
                           "Role": pending["role"], "CustomerID": pending["customer_id"]}, via="hardened + MFA")
            flash(f"Welcome {pending['username']} (password + one-time code).", "ok")
            return redirect(url_for("index"))
        flash(rows[0]["Message"], "error")
        if rows[0]["ResultCode"] == 2:      # locked
            session.clear()
            return redirect(url_for("index"))
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
    session.clear()
    flash("Logged out.", "ok")
    return redirect(url_for("index"))


# ===================== VULNERABLE (RED) PATH - LAB ONLY =====================
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
        with connect("legacy_app") as conn:
            row = conn.execute(sql).fetchone()
    except pyodbc.Error as e:
        # BAD: raw database error shown to the user (leaks table/column names)
        return render_template("index.html", vuln_sql=sql, vuln_error=str(e))
    if not row:
        return render_template("index.html", vuln_sql=sql, vuln_error="Invalid username or password.")
    start_session({"UserID": row.UserID, "Username": row.Username, "Role": row.Role,
                   "CustomerID": row.CustomerID}, via="VULNERABLE")
    flash(f"Logged in as {row.Username} ({row.Role}) through the VULNERABLE path.", "warn")
    return render_template("index.html", vuln_sql=sql)


@app.get("/vuln/search")
@local_lab_only
def vuln_search():
    q = request.args.get("q", "")
    # BAD: string concatenation again
    sql = f"SELECT Name, Category, Price FROM dbo.Products WHERE IsActive = 1 AND Name LIKE N'%{q}%'"
    try:
        with connect("legacy_app") as conn:
            cur = conn.execute(sql)
            products = rows_as_dicts(cur) if cur.description else []
    except pyodbc.Error as e:
        return render_template("index.html", vuln_sql=sql, vuln_error=str(e), q=q)
    return render_template("index.html", products=products, q=q, mode="vulnerable", vuln_sql=sql)


@app.errorhandler(Exception)
def generic_error(e):
    """Hardened behaviour: log details on the server, show a generic message."""
    if hasattr(e, "code") and isinstance(e.code, int):      # normal HTTP errors (404, 400)
        return e
    app.logger.exception("Unhandled error")
    return render_template("index.html", fatal="Something went wrong. Please try again later."), 500


if __name__ == "__main__":
    # 127.0.0.1 = reachable from this computer only. debug=False: no stack traces.
    app.run(host="127.0.0.1", port=5000, debug=False)
