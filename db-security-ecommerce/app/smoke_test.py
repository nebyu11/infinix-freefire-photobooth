"""
smoke_test.py - check the whole demo end-to-end in ~10 seconds.

Use it on the morning of the presentation:
    1. start the app:          python app.py
    2. in a second terminal:    python smoke_test.py

It drives the RUNNING website like a browser and prints PASS/FAIL for every
security behaviour that the live demo relies on. It cleans up after itself
(the 1-ETB price "attack" is reverted). It registers one new random test
customer per run.
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
results = []


def check(name, condition):
    condition = bool(condition)
    results.append(condition)
    print(f"[{'PASS' if condition else 'FAIL'}] {name}")


def new_browser():
    """A fresh 'browser' (cookie jar) with a CSRF token."""
    s = requests.Session()
    html = s.get(BASE + "/").text
    s.csrf = re.search(r'name="csrf" value="([^"]+)"', html).group(1)
    return s


def post(s, path, **data):
    return s.post(BASE + path, data={"csrf": s.csrf, **data})


def refresh_csrf(s, html):
    m = re.search(r'name="csrf" value="([^"]+)"', html)
    if m:
        s.csrf = m.group(1)


b = new_browser()
# ---------------- SQL injection: search ----------------
r = b.get(BASE + "/search", params={"q": "coffee"})
check("Hardened search 'coffee' returns 2 products", r.text.count("Coffee") >= 2)

union = "' UNION SELECT Username, Role + ' | ' + CONVERT(varchar(200), PasswordHash, 1), 0 FROM dbo.Users --"
r = b.get(BASE + "/search", params={"q": union})
HASH = re.compile(r"0x[0-9A-F]{40}")          # a dumped password hash looks like this
check("Hardened search: UNION payload returns nothing", "No products found" in r.text and not HASH.search(r.text))
r = b.get(BASE + "/vuln/search", params={"q": union})
check("Vulnerable search: UNION payload DUMPS usernames + hashes", "<td>admin.tsehay</td>" in r.text and HASH.search(r.text))

r = b.get(BASE + "/vuln/search", params={"q": "' AND 1=CONVERT(int, @@VERSION) --"})
check("Vulnerable search: error message leaks the server version", "Microsoft SQL Server" in r.text)

b.get(BASE + "/vuln/search", params={"q": "'; UPDATE dbo.Products SET Price = 1 WHERE SKU = 'EL-LAP-002' --"})
r = b.get(BASE + "/search", params={"q": "Laptop"})
check("Vulnerable search: stacked query changed laptop price to 1 ETB", ">1.00<" in r.text)
b.get(BASE + "/vuln/search", params={"q": "'; UPDATE dbo.Products SET Price = 65000 WHERE SKU = 'EL-LAP-002' --"})
r = b.get(BASE + "/search", params={"q": "Laptop"})
check("(cleanup) laptop price restored to 65000", ">65000.00<" in r.text)

r = b.get(BASE + "/search", params={"q": "e", "sort": "Price; DROP TABLE dbo.Products --"})
check("Hardened search: injection in sort column ignored, table intact", "Smartphone" in r.text)

# ---------------- SQL injection: login ----------------
r = post(b, "/vuln/login", username="' OR '1'='1' --", password="x")
check("Vulnerable login: ' OR '1'='1' -- logs in WITHOUT password", "through the VULNERABLE path" in r.text)

b = new_browser()
r = post(b, "/login", username="' OR '1'='1' --", password="x")
check("Hardened login: same payload rejected", "Invalid username or password" in r.text)

r = post(b, "/login", username="selam.g", password=DEMO_PWD)
check("Hardened login: selam.g with correct password works", "Welcome selam.g" in r.text)
refresh_csrf(b, r.text)

# ---------------- RLS through the app ----------------
r = b.get(BASE + "/orders")
ids = set(re.findall(r"#(\d{4})", r.text))
check(f"My orders shows ONLY Selam's orders (got {sorted(ids)})", {"1001", "1009"} <= ids and "1003" not in ids)

r = post(b, "/order", product_id="10", quantity="1", method="Telebirr")
check("Place order through app.sp_PlaceOrder", "Order placed successfully" in r.text)
r = post(b, "/order", product_id="10", quantity="99", method="Telebirr")
check("Order validation: quantity 99 rejected", "between 1 and 10" in r.text)

# ---------------- CSRF ----------------
r = b.post(BASE + "/order", data={"product_id": "10", "quantity": "1", "method": "Telebirr"})
check("POST without CSRF token is refused (400)", r.status_code == 400)

# ---------------- Registration + password policy ----------------
b = new_browser()
user = "test." + secrets.token_hex(3)
pwd = "Tea#Garden" + str(secrets.randbelow(900) + 100)
form = dict(first="Test", last="User", email=f"{user}@mail.et",
            phone="+2519" + str(secrets.randbelow(10**8)).zfill(8), city="Adama", region="Hawassa")
r = post(b, "/register", username=user, password="weakpass", **form)
check("Register with weak password rejected by policy", "Registration rejected" in r.text)
r = post(b, "/register", username=user, password=pwd, **form)
check(f"Register {user} with strong password", "Account created" in r.text)

# ---------------- MFA ----------------
r = post(b, "/login", username=user, password=pwd)
refresh_csrf(b, r.text)
r = b.get(BASE + "/mfa/setup")
secret = re.search(r"manually: <code>([A-Z2-7]+)</code>", r.text).group(1)
refresh_csrf(b, r.text)
r = post(b, "/mfa/setup", code=pyotp.TOTP(secret).now())
check("MFA enabled after first correct TOTP code", "MFA enabled" in r.text)

b = new_browser()
r = post(b, "/login", username=user, password=pwd)
check("Login with MFA: password alone is NOT enough", "Second factor" in r.text)
refresh_csrf(b, r.text)
r = post(b, "/mfa/verify", code="000000")
check("Wrong one-time code rejected", "Wrong code" in r.text)
r = post(b, "/mfa/verify", code=pyotp.TOTP(secret).now())
check("Correct one-time code completes login", f"Welcome {user}" in r.text)

# ---------------- Lockout ----------------
b = new_browser()
for _ in range(5):
    r = post(b, "/login", username=user, password="Wrong#Pass123")
check("5 wrong passwords lock the account", "Account locked" in r.text)
r = post(b, "/login", username=user, password=pwd)
check("Correct password refused while locked", "Account locked" in r.text)

print(f"\n{sum(results)}/{len(results)} checks passed")
sys.exit(0 if all(results) else 1)
