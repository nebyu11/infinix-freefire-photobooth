"""
smoke_test.py - check the whole demo end-to-end in ~15 seconds.

Use it on the morning of the presentation:
    1. start the app:          python app.py
    2. in a second terminal:    python smoke_test.py

It drives the RUNNING website like a browser and prints PASS/FAIL for every
security behaviour that the live demo relies on. It cleans up after itself
(the 1-ETB price "attack" is reverted). It registers one new random test
customer per run and places two small test orders.
"""
import os
import re
import secrets
import sys
from pathlib import Path

import pyotp
import requests
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")
BASE = "http://127.0.0.1:5000"
DEMO_PWD = os.environ["DEMO_USER_PASSWORD"]
STAFF_PWD = os.environ["STAFF_PASSWORD"]
HASH = re.compile(r"0x[0-9A-F]{40}")          # a dumped password hash looks like this
results = []


def check(name, condition):
    condition = bool(condition)
    results.append(condition)
    print(f"[{'PASS' if condition else 'FAIL'}] {name}")


class Browser(requests.Session):
    """A fresh 'browser' (cookie jar) that always sends the current CSRF token."""
    def __init__(self):
        super().__init__()
        self.csrf = ""
        self.get_("/")

    def _grab(self, r):
        m = re.search(r'name="csrf" value="([^"]+)"', r.text)
        if m:
            self.csrf = m.group(1)
        return r

    def get_(self, path, **params):
        return self._grab(self.get(BASE + path, params=params))

    def post_(self, path, **data):
        return self._grab(self.post(BASE + path, data={"csrf": self.csrf, **data}))


def check_of(html, label):
    """Return 'yes' / 'no' for a capability card in the staff portal."""
    m = re.search(r'class="check (yes|no)"[^>]*>\s*<span class="mark">.</span>\s*<div><b>' + re.escape(label), html)
    return m.group(1) if m else "?"


# ---------------- Storefront ----------------
b = Browser()
r = b.get_("/", q="coffee")
check("Storefront search 'coffee' shows 2 products", r.text.count('<article class="product">') == 2)
r = b.get_("/", category="Food", sort="PriceDesc")
check("Category filter + sort (allow-listed) work", "Yirgacheffe" in r.text and "Smartphone" not in r.text)
r = b.get_("/", sort="Price; DROP TABLE dbo.Products --")
check("Injection in the sort parameter ignored, catalog intact", r.text.count('<article class="product">') == 10)

# ---------------- Security lab: SQL injection ----------------
union = "' UNION SELECT Username, Role + ' | ' + CONVERT(varchar(200), PasswordHash, 1), 0 FROM dbo.Users --"
r = b.get_("/lab/search", q=union)
check("Hardened search: UNION payload returns nothing", "No products found" in r.text and not HASH.search(r.text))
r = b.get_("/vuln/search", q=union)
check("Vulnerable search: UNION payload DUMPS usernames + hashes", "<td>admin.tsehay</td>" in r.text and HASH.search(r.text))
r = b.get_("/vuln/search", q="' AND 1=CONVERT(int, @@VERSION) --")
check("Vulnerable search: error message leaks the server version", "Microsoft SQL Server" in r.text)
b.get_("/vuln/search", q="'; UPDATE dbo.Products SET Price = 1 WHERE SKU = 'EL-LAP-002' --")
r = b.get_("/", q="Laptop")
check("Vulnerable search: stacked query changed laptop price to 1 ETB (visible in the shop)", ">1.00 <small>" in r.text)
b.get_("/vuln/search", q="'; UPDATE dbo.Products SET Price = 65000 WHERE SKU = 'EL-LAP-002' --")
r = b.get_("/", q="Laptop")
check("(cleanup) laptop price restored to 65,000", ">65,000.00 <small>" in r.text)

r = b.post_("/vuln/login", username="' OR '1'='1' --", password="x")
check("Vulnerable login: ' OR '1'='1' -- logs in WITHOUT password", "through the VULNERABLE path" in r.text)

b = Browser()
r = b.post_("/login", username="' OR '1'='1' --", password="x", next="lab")
check("Hardened login: same payload rejected", "Invalid username or password" in r.text)

# ---------------- Customer: login, cart, checkout, RLS ----------------
r = b.post_("/login", username="selam.g", password=DEMO_PWD)
check("Hardened login: selam.g with correct password works", "Welcome selam.g" in r.text)
r = b.get_("/account")
ids = set(re.findall(r"#(\d{4})", r.text))
check(f"My account shows ONLY Selam's orders (RLS) - got {sorted(ids)}", {"1001", "1009"} <= ids and "1003" not in ids)

b.post_("/cart/add", product_id="10", quantity="2")
b.post_("/cart/add", product_id="9", quantity="1")
r = b.get_("/cart")
check("Cart holds 2 products with the right total (2×320 + 950 = 1,590)", "1,590.00 ETB" in r.text)
r = b.post_("/cart/add", product_id="10", quantity="99")
check("Cart validation: quantity 99 rejected", "Quantity must be between 1 and 10" in r.text)
r = b.post_("/checkout", method="Telebirr")
new_order = re.search(r"Order #(\d+) was placed", r.text)
check("Checkout through app.sp_PlaceOrderCart creates ONE order with both products",
      new_order and "2 x Berbere Spice 500g" in r.text and "1 x Yirgacheffe Coffee 1kg" in r.text)
r = b.get_("/cart")
check("Cart is empty after checkout", "Your cart is empty" in r.text)
r = b.post(BASE + "/cart/add", data={"product_id": "10", "quantity": "1"})
check("POST without CSRF token is refused (400)", r.status_code == 400)

# ---------------- Registration + password policy ----------------
b = Browser()
user = "test." + secrets.token_hex(3)
pwd = "Tea#Garden" + str(secrets.randbelow(900) + 100)
form = dict(first="Test", last="User", email=f"{user}@mail.et",
            phone="+2519" + str(secrets.randbelow(10**8)).zfill(8), city="Adama", region="Hawassa")
r = b.post_("/register", username=user, password="weakpass", **form)
check("Register with weak password rejected by policy", "Registration rejected" in r.text)
r = b.post_("/register", username=user, password=pwd, **form)
check(f"Register {user} with strong password", "Account created" in r.text)

# ---------------- MFA ----------------
b.post_("/login", username=user, password=pwd)
r = b.get_("/mfa/setup")
secret = re.search(r"manually: <code>([A-Z2-7]+)</code>", r.text).group(1)
r = b.post_("/mfa/setup", code=pyotp.TOTP(secret).now())
check("MFA enabled after first correct TOTP code", "MFA enabled" in r.text)

b = Browser()
r = b.post_("/login", username=user, password=pwd)
check("Login with MFA: password alone is NOT enough", "Second factor" in r.text)
r = b.post_("/mfa/verify", code="000000")
check("Wrong one-time code rejected", "Wrong code" in r.text)
r = b.post_("/mfa/verify", code=pyotp.TOTP(secret).now())
check("Correct one-time code completes login", f"Welcome {user}" in r.text)

# ---------------- Lockout ----------------
b = Browser()
for _ in range(5):
    r = b.post_("/login", username=user, password="Wrong#Pass123")
check("5 wrong passwords lock the account", "Account locked" in r.text)
r = b.post_("/login", username=user, password=pwd)
check("Correct password refused while locked", "Account locked" in r.text)

# ---------------- Staff portal: RBAC / ABAC through SQL Server logins ----------------
def staff(login, password=STAFF_PWD):
    s = Browser()
    s.get_("/staff/login")
    return s, s.post_("/staff/login", login=login, password=password)


_, r = staff("sales_addis", "Wrong#Pass123")
check("Staff portal: wrong SQL password -> 'Login failed.'", "Login failed." in r.text)
_, r = staff("shop_app", os.environ["APP_PASSWORD"])
check("Staff portal refuses non-staff logins (e.g. the website's shop_app)", "staff accounts only" in r.text)

_, r = staff("sales_addis")
check("sales_addis: identity + ABAC attributes shown (Sales · Addis Ababa)", "sales_role" in r.text and "Addis Ababa" in r.text)
m = re.search(r"Orders <span class=\"pill\">(\d+) rows", r.text)
check(f"sales_addis sees only Addis orders via RLS (got {m.group(1) if m else '?'})", m and "Hawassa</td>" not in r.text.split("<h3>Customers")[0])
check("sales_addis: 'Change product prices' DENIED by SQL Server", check_of(r.text, "Change product prices") == "no")
check("sales_addis: card numbers stay NULL (no key permission)", "0 decrypted (no key permission)" in r.text)
check("sales_addis: audit log DENIED", "Denied by SQL Server: The SELECT permission was denied on the object &#39;AuditLog&#39;" in r.text)

_, r = staff("support_dawit")
check("support_dawit: customer e-mails are MASKED", "XXX@XXXX.com" in r.text)
check("support_dawit: payments DENIED", "denied on the object &#39;Payments&#39;" in r.text)

_, r = staff("shop_admin")
check("shop_admin: may change prices and decrypts card numbers",
      check_of(r.text, "Change product prices") == "yes" and "4111111111111111" in r.text)
check("shop_admin: may NOT read password hashes or delete the audit log",
      check_of(r.text, "Read password hashes") == "no" and check_of(r.text, "Delete the audit log") == "no")

_, r = staff("auditor_meron")
check("auditor_meron: reads the audit log but may not change anything",
      check_of(r.text, "Read the audit log") == "yes" and check_of(r.text, "Change order status") == "no")

print(f"\n{sum(results)}/{len(results)} checks passed")
sys.exit(0 if all(results) else 1)
