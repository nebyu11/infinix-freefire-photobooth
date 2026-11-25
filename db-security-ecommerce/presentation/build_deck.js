/*
 * build_deck.js - builds presentation/DB_Security_Ecommerce.pptx
 *                 and docs/speaker_notes.md (same notes as in the slides)
 *
 * Rebuild:  cd presentation && npm install && node build_deck.js
 * Screenshots are taken from ../screenshots (real outputs of this project).
 */
const path = require("path");
const fs = require("fs");
const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const fa = require("react-icons/fa");

const ROOT = path.resolve(__dirname, "..");
const SHOT = (p) => path.join(ROOT, "screenshots", p);
const IMG = path.join(__dirname, "img");
fs.mkdirSync(IMG, { recursive: true });

// --------------------------------------------------------------------------
// Theme: dark navy (trust) + teal-green (secured) + coral-red (attack)
// --------------------------------------------------------------------------
const THEME = {
  name: "ShopDB Secure",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1A2233", lt1: "FFFFFF", dk2: "14213D", lt2: "EEF2F7",
    accent1: "1B998B", accent2: "E4572E", accent3: "F3A712",
    accent4: "3D5A80", accent5: "7A8599", accent6: "6A4C93",
    hlink: "1B998B", folHlink: "6A4C93",
  },
};
const HEX = THEME.colors;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.333 x 7.5 in
pres.title = "Securing an E-commerce Database";
pres.subject = "Database Security - Chapter 2 practical implementation";
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;

// --------------------------------------------------------------------------
// Layouts (frames)
// --------------------------------------------------------------------------
pres.defineSlideMaster({
  title: "TITLE",
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.2, w: 8.6, h: 1.9,
        fontSize: 44, bold: true, color: C.background1, valign: "bottom", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 4.3, w: 8.6, h: 1.8,
        fontSize: 18, color: C.background2, valign: "top", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "SECTION",
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 2.6, y: 2.75, w: 9.9, h: 1.2,
        fontSize: 40, bold: true, color: C.background1, valign: "middle", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 2.6, y: 3.95, w: 9.9, h: 1.0,
        fontSize: 18, color: C.accent3, valign: "top", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.3, w: 12.1, h: 0.85,
        fontSize: 32, bold: true, color: C.text2, valign: "middle", margin: 0 }, text: "" } },
    { text: { text: "ShopDB · E-commerce Database Security · Chapter 2",
        options: { x: 0.6, y: 7.02, w: 7, h: 0.3, fontSize: 10, color: C.accent5, margin: 0 } } },
  ],
  slideNumber: { x: 12.2, y: 7.02, w: 0.5, h: 0.3, fontSize: 10, color: C.accent5, align: "right" },
});

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
const ICON_CACHE = {};
async function icon(name, hex) {
  const key = name + hex;
  if (!ICON_CACHE[key]) {
    const svg = ReactDOMServer.renderToStaticMarkup(
      React.createElement(fa[name], { color: "#" + hex, size: 256 }));
    const buf = await sharp(Buffer.from(svg)).resize(256, 256).png().toBuffer();
    ICON_CACHE[key] = "image/png;base64," + buf.toString("base64");
  }
  return ICON_CACHE[key];
}
// icon in a coloured circle = the deck's visual motif
async function badge(slide, name, x, y, d, fill, iconHex = "FFFFFF") {
  slide.addShape(pres.shapes.OVAL, { x, y, w: d, h: d, fill: { color: fill }, line: { color: fill },
    objectName: "badge-" + name });
  const p = d * 0.22;
  slide.addImage({ data: await icon(name, iconHex), x: x + p, y: y + p, w: d - 2 * p, h: d - 2 * p,
    altText: name.replace(/^Fa/, "") + " icon" });
}
function text(slide, t, o) { slide.addText(t, { isTextBox: true, margin: 0, valign: "top", ...o }); }
function card(slide, x, y, w, h, fill = C.background2) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.12, fill: { color: fill },
    line: { color: fill } });
}
function box(slide, t, x, y, w, h, fill, color = C.background1, o = {}) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fill },
    line: { color: fill } });
  slide.addText(t, { isTextBox: true, x, y, w, h, margin: 0.08, align: "center", valign: "middle",
    fontSize: 14, color, bold: true, ...o });
}
function arrow(slide, x1, y1, x2, y2, color = C.accent5, w = 2) {
  slide.addShape(pres.shapes.LINE, { x: Math.min(x1, x2), y: Math.min(y1, y2),
    w: Math.abs(x2 - x1) || 0.001, h: Math.abs(y2 - y1) || 0.001,
    flipH: x2 < x1, flipV: y2 < y1, line: { color, width: w, endArrowType: "triangle" } });
}
function tag(slide, t, x, y, fill = C.accent1, w = 1.6) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h: 0.3, rectRadius: 0.15,
    fill: { color: fill }, line: { color: fill } });
  slide.addText(t, { isTextBox: true, x, y, w, h: 0.3, margin: 0, align: "center", valign: "middle",
    fontSize: 11, bold: true, color: C.background1 });
}
const META = {};
async function imgFit(slide, file, x, y, maxW, maxH, alt, border = true) {
  if (!META[file]) META[file] = await sharp(file).metadata();
  const { width, height } = META[file];
  let w = maxW, h = (maxW * height) / width;
  if (h > maxH) { h = maxH; w = (maxH * width) / height; }
  const ox = x + (maxW - w) / 2;
  if (border) slide.addShape(pres.shapes.RECTANGLE, { x: ox - 0.03, y: y - 0.03, w: w + 0.06, h: h + 0.06,
    fill: { color: C.background2 }, line: { color: C.background2 } });
  slide.addImage({ path: file, x: ox, y, w, h, altText: alt });
  return { x: ox, y, w, h };
}
async function crop(src, out, top, height) {
  const m = await sharp(src).metadata();
  await sharp(src).extract({ left: 0, top, width: m.width, height: Math.min(height, m.height - top) })
    .toFile(out);
  return out;
}

async function cropBox(src, out, left, top, width, height) {
  await sharp(src).extract({ left, top, width, height }).toFile(out);
  return out;
}

const NOTES = []; // collected for docs/speaker_notes.md
let SECTION = "";
function newSlide(layout, title, notes, minutes) {
  const s = pres.addSlide({ masterName: layout, sectionTitle: SECTION });
  if (title) s.addText(title, { placeholder: "title" });
  s.addNotes(notes);
  NOTES.push({ n: NOTES.length + 1, title: title || "(untitled)", section: SECTION, minutes, notes });
  return s;
}
function section(title) { SECTION = title; pres.addSection({ title }); }

// --------------------------------------------------------------------------
(async () => {
  // ======================= OPENING =======================================
  section("Opening");
  let s = newSlide("TITLE", "Securing an E-commerce Database",
    `Good morning everyone. My name is [your name]. Today I will show how I secured the database of an online shop called ShopDB, using Microsoft SQL Server 2022.
I follow the six parts of the assignment: key concepts from Chapter 2, why they matter, how I built it, a live demonstration, my conclusion, and then your questions.
Everything I show was really built and tested. The code, the scripts and the screenshots are all in my project folder.`, 1);
  s.addText([
    { text: "Access control, authentication & data protection on SQL Server 2022", options: { breakLine: true } },
    { text: "[Your name] · Frontier Institute of Technology · Database Security (CyTe3031)",
      options: { fontSize: 14, color: C.accent3 } },
  ], { placeholder: "body" });
  await badge(s, "FaShieldAlt", 10.0, 2.3, 2.5, C.accent1);
  text(s, "ShopDB", { x: 10.0, y: 4.95, w: 2.5, h: 0.5, fontSize: 20, bold: true, color: C.background1, align: "center" });

  s = newSlide("CONTENT", "Today's journey: six parts in about 50 minutes",
    `This is my plan for the next fifty minutes. First I explain the key ideas of Chapter 2 in my own words. Then I explain why they matter for a real online shop.
In part three I show HOW I built the solution, using diagrams instead of code. Part four is the live demonstration: you will see attacks fail against my hardened version.
I finish with my conclusion and ask you for feedback, then we have time for questions.`, 1);
  const parts = [
    ["1", "Key concepts", "15 min", "FaBook"], ["2", "Why it matters", "5 min", "FaGlobe"],
    ["3", "Implementation approach", "10 min", "FaSitemap"], ["4", "Results & live demo", "15 min", "FaLaptopCode"],
    ["5", "Conclusion & feedback", "4 min", "FaComments"], ["6", "Q&A", "5 min", "FaQuestionCircle"],
  ];
  const sx = 0.6, gap = 2.07;
  s.addShape(pres.shapes.LINE, { x: sx + 0.6, y: 3.05, w: gap * 5, h: 0, line: { color: C.background2, width: 4 } });
  for (let i = 0; i < 6; i++) {
    const x = sx + i * gap;
    await badge(s, parts[i][3], x + 0.1, 2.05, 1.0, i === 3 ? C.accent2 : C.accent1);
    text(s, parts[i][0], { x, y: 3.35, w: 1.9, h: 0.6, fontSize: 28, bold: true, color: C.text2 });
    text(s, parts[i][1], { x, y: 3.95, w: 1.9, h: 0.8, fontSize: 16, bold: true, color: C.text1 });
    text(s, parts[i][2], { x, y: 4.75, w: 1.9, h: 0.4, fontSize: 14, color: C.accent5 });
  }
  text(s, "Application area: an online shop (customers, products, orders, payments, staff) in Ethiopia",
    { x: 0.6, y: 5.9, w: 12.1, h: 0.5, fontSize: 16, italic: true, color: C.accent4 });

  // ======================= PART 1: KEY CONCEPTS ==========================
  section("1 · Key concepts");
  s = newSlide("SECTION", "Key concepts from Chapter 2",
    `Part one: the key concepts. I will go through the chapter in the same order as the lecture: access control, authentication and passwords, MFA, roles and attributes, secure coding, and encryption.
For each idea I will also say where you will see it later in my project.`, 0.5);
  s.addText("Part 1 · access control · authentication · secure coding · encryption", { placeholder: "body" });
  await badge(s, "FaBook", 0.9, 2.75, 1.3, C.accent1);

  // --- access control models
  s = newSlide("CONTENT", "Access control: who may see, query, modify or execute what",
    `Access control decides what an already-authenticated user is allowed to do in the database.
There are four common models. In RBAC, rights belong to job roles, like "sales", not to individual people. In DAC, the owner of the data decides who gets access. In MAC, a central authority gives security labels that users cannot change, like in the military. In ABAC, the decision depends on attributes: the user's department, the location, the time, or properties of the data itself.
In my project I implemented RBAC and ABAC, and you will see both in the demo. DAC and MAC I only explain.`, 1.5);
  const models = [
    ["RBAC", "Role-Based", "Rights belong to job roles, not people. A person gets the rights of their job.", "FaUserTag", true],
    ["DAC", "Discretionary", "The owner of the data decides who may access it (GRANT by the owner).", "FaUserLock", false],
    ["MAC", "Mandatory", "A central authority sets clearance labels that users cannot change.", "FaBalanceScale", false],
    ["ABAC", "Attribute-Based", "Decision uses attributes: department, region, time, device, data owner.", "FaSlidersH", true],
  ];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + (i % 2) * 6.15, y = 1.45 + Math.floor(i / 2) * 2.7;
    card(s, x, y, 5.95, 2.45);
    await badge(s, models[i][3], x + 0.3, y + 0.35, 1.0, models[i][4] ? C.accent1 : C.accent4);
    text(s, models[i][0], { x: x + 1.55, y: y + 0.3, w: 2.2, h: 0.55, fontSize: 26, bold: true, color: C.text2 });
    text(s, models[i][1], { x: x + 1.55, y: y + 0.85, w: 2.6, h: 0.4, fontSize: 15, color: C.accent5 });
    text(s, models[i][2], { x: x + 1.55, y: y + 1.3, w: 4.2, h: 1.0, fontSize: 15, color: C.text1 });
    if (models[i][4]) tag(s, "Implemented", x + 4.1, y + 0.38, C.accent1);
    else tag(s, "Explained", x + 4.1, y + 0.38, C.accent5);
  }

  // --- authN vs authZ
  s = newSlide("CONTENT", "Authentication first, then authorization",
    `These two words sound similar but they answer different questions.
Authentication asks "who are you?". It is like showing your passport at the airport security check. It always happens first.
Authorization asks "what are you allowed to do?". It is like the boarding pass that lets you sit only in your own seat.
In ShopDB, authentication is the login procedure with the password check, lockout and optional MFA. Authorization is the roles, the GRANT and DENY permissions, and the row-level rules.`, 1.5);
  const ab = [
    ["Authentication", "Who are you?", "FaIdCard", C.accent4,
      ["Verifies identity: password, OTP, fingerprint", "Always happens FIRST", "Airport: showing your passport"],
      "ShopDB: app.sp_Login · lockout · TOTP MFA"],
    ["Authorization", "What can you do?", "FaUserCheck", C.accent1,
      ["Grants or denies access to data and actions", "Happens AFTER authentication", "Airport: boarding pass → your seat only"],
      "ShopDB: roles · GRANT/DENY · Row-Level Security"],
  ];
  for (let i = 0; i < 2; i++) {
    const x = 0.6 + i * 6.45;
    card(s, x, 1.45, 5.65, 5.2);
    await badge(s, ab[i][2], x + 0.35, 1.75, 1.1, ab[i][3]);
    text(s, ab[i][0], { x: x + 1.7, y: 1.75, w: 3.8, h: 0.6, fontSize: 26, bold: true, color: C.text2 });
    text(s, ab[i][1], { x: x + 1.7, y: 2.35, w: 3.8, h: 0.5, fontSize: 18, italic: true, color: ab[i][3] });
    s.addText(ab[i][4].map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < 2 } })),
      { isTextBox: true, x: x + 0.4, y: 3.2, w: 4.9, h: 2.0, fontSize: 17, color: C.text1, paraSpaceAfter: 8, margin: 0, valign: "top" });
    box(s, ab[i][5], x + 0.35, 5.6, 4.95, 0.7, ab[i][3], C.background1, { fontSize: 15 });
  }
  arrow(s, 6.3, 4.0, 7.0, 4.0, C.accent3, 4);

  // --- authentication methods
  s = newSlide("CONTENT", "Authentication methods: what can prove who you are?",
    `The lecture lists six families of authentication methods.
Something you KNOW, like a password or PIN. Something you HAVE, like a phone with an authenticator app or a security key. Something you ARE, like a fingerprint or your face. SOMEWHERE you are, like an allowed IP address. ADAPTIVE methods look at the risk, for example a new device or a login at 3 a.m. And FEDERATED login lets a trusted third party like Google or Microsoft confirm your identity.
My project combines the first two: a password you know, plus a one-time code from your phone.`, 1.5);
  const am = [
    ["Know", "Password, PIN, security question", "FaKey", true],
    ["Have", "Authenticator app (TOTP), USB key, smart card", "FaMobileAlt", true],
    ["Are", "Fingerprint, face, iris, voice", "FaFingerprint", false],
    ["Where", "IP allow-list, geofencing, impossible travel", "FaMapMarkerAlt", false],
    ["Adaptive", "Device, time of day, behaviour → risk score", "FaChartLine", false],
    ["Federated", "SSO with SAML, OAuth 2.0 / OpenID Connect", "FaHandshake", false],
  ];
  for (let i = 0; i < 6; i++) {
    const x = 0.6 + (i % 3) * 4.1, y = 1.45 + Math.floor(i / 3) * 2.6;
    card(s, x, y, 3.9, 2.35, am[i][3] ? "E3F4F2" : C.background2);
    await badge(s, am[i][2], x + 0.3, y + 0.3, 0.95, am[i][3] ? C.accent1 : C.accent4);
    text(s, am[i][0], { x: x + 1.45, y: y + 0.45, w: 2.3, h: 0.6, fontSize: 24, bold: true, color: C.text2 });
    text(s, am[i][1], { x: x + 0.3, y: y + 1.4, w: 3.4, h: 0.8, fontSize: 15, color: C.text1 });
  }
  text(s, "Green = used in ShopDB: password (know) + one-time code on the phone (have)",
    { x: 0.6, y: 6.55, w: 12.1, h: 0.4, fontSize: 14, italic: true, color: C.accent1 });

  // --- password policy
  s = newSlide("CONTENT", "Password policy: length beats complexity",
    `Passwords are still the first line of defence, and weak or reused passwords are a top cause of breaches.
A good policy has these elements: a minimum length, a mix of character types, a blocklist of common passwords, lockout after repeated failures, password history so old passwords cannot be reused, and safe storage. Storage means never plaintext: we store a random salt and a slow hash.
On the right you see why length matters. The number of possible passwords is C to the power N: C is the size of the character set and N is the length. Six lower-case letters give about 300 million options, which a computer tries in seconds. My policy needs at least 10 characters from all four groups. That gives up to 94 to the power 10: about 54 billion billion options.`, 1.5);
  const pol = [["Minimum length", "10+ characters"], ["Complexity", "upper · lower · digit · symbol"],
    ["Blocklist", "no 'Password123!'"], ["Lockout", "5 failures → 15 min"],
    ["History", "no reuse of last 3"], ["Storage", "salt + slow hash, never plaintext"]];
  for (let i = 0; i < 6; i++) {
    const y = 1.45 + i * 0.86;
    await badge(s, "FaCheckCircle", 0.6, y + 0.08, 0.55, C.accent1);
    text(s, pol[i][0], { x: 1.35, y: y, w: 2.4, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
    text(s, pol[i][1], { x: 1.35, y: y + 0.38, w: 4.6, h: 0.4, fontSize: 15, color: C.accent5 });
  }
  card(s, 6.5, 1.45, 6.2, 5.2, C.text2);
  text(s, "Key space = Cᴺ", { x: 6.85, y: 1.65, w: 5.5, h: 0.5, fontSize: 20, bold: true, color: C.accent3 });
  text(s, "C = number of possible characters, N = length", { x: 6.85, y: 2.15, w: 5.5, h: 0.4, fontSize: 14, color: C.background2 });
  text(s, "26⁶ ≈ 3.1 × 10⁸", { x: 6.85, y: 2.75, w: 5.5, h: 0.8, fontSize: 40, bold: true, color: C.accent2 });
  text(s, "6 lower-case letters: cracked in seconds", { x: 6.85, y: 3.55, w: 5.5, h: 0.4, fontSize: 15, color: C.background2 });
  text(s, "94¹⁰ ≈ 5.4 × 10¹⁹", { x: 6.85, y: 4.25, w: 5.5, h: 0.8, fontSize: 40, bold: true, color: C.accent1 });
  text(s, "10 characters from all 94 printable: ShopDB minimum", { x: 6.85, y: 5.05, w: 5.5, h: 0.4, fontSize: 15, color: C.background2 });
  text(s, "≈ 170 billion times more guesses", { x: 6.85, y: 5.75, w: 5.5, h: 0.5, fontSize: 18, bold: true, italic: true, color: C.accent3 });

  // --- threats & cracking
  s = newSlide("CONTENT", "How passwords are attacked, and what stops each attack",
    `Passwords are attacked in many ways: disclosure, guessing, snooping with key loggers, and automated cracking.
The lecture names three cracking types. A dictionary attack tries every word in a list. My blocklist rejects the most common passwords. A hybrid attack adds numbers and symbols, like "Password123!". The complexity rules plus the blocklist stop that. A brute-force attack tries every combination. Against that, lockout stops online guessing after five tries, and the slow salted hash makes offline guessing very expensive.
The salt is a random value per user, so two users with the same password still get different hashes, and pre-computed "rainbow tables" are useless.`, 1.5);
  const atk = [
    ["Dictionary attack", "tries every word in a list", "Blocklist of common passwords", "FaBook"],
    ["Hybrid attack", "word + digits/symbols: 'Password123!'", "Complexity rules + blocklist", "FaRandom"],
    ["Brute force (online)", "tries every combination at the login", "Lockout after 5 failures + audit log", "FaUserLock"],
    ["Offline cracking", "attacker steals the hash table", "Per-user salt + 5,000× SHA-512 (slow)", "FaHashtag"],
  ];
  text(s, "ATTACK", { x: 1.6, y: 1.35, w: 4, h: 0.35, fontSize: 13, bold: true, color: C.accent2 });
  text(s, "DEFENCE IN SHOPDB", { x: 7.9, y: 1.35, w: 4, h: 0.35, fontSize: 13, bold: true, color: C.accent1 });
  for (let i = 0; i < 4; i++) {
    const y = 1.8 + i * 1.22;
    card(s, 0.6, y, 5.6, 1.05, "FCE9E4");
    await badge(s, atk[i][3], 0.8, y + 0.15, 0.75, C.accent2);
    text(s, atk[i][0], { x: 1.75, y: y + 0.12, w: 4.3, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
    text(s, atk[i][1], { x: 1.75, y: y + 0.55, w: 4.3, h: 0.4, fontSize: 14, color: C.text1 });
    arrow(s, 6.35, y + 0.52, 7.25, y + 0.52, C.accent5, 3);
    box(s, atk[i][2], 7.4, y, 5.3, 1.05, C.accent1, C.background1, { fontSize: 16 });
  }
  text(s, "Other threats from the lecture: disclosure · inference · exposure · loss · snooping (key loggers, sniffing) → user awareness, TLS, audit",
    { x: 0.6, y: 6.75 - 0.15, w: 12.1, h: 0.4, fontSize: 13, italic: true, color: C.accent5 });

  // --- MFA
  s = newSlide("CONTENT", "MFA: one stolen password is not enough",
    `Multi-factor authentication combines two or more DIFFERENT types of proof. The timeline shows the evolution: single factor is a password only, two-factor adds a device or a biometric, and full MFA can combine all three.
The big advantage: even if an attacker steals the password, they still need my phone. The disadvantages are a slower login, more setup, and a problem if you lose your phone.
In my project, after the password is correct, the user types a six-digit code from Google Authenticator. The code changes every 30 seconds and is computed from a shared secret plus the current time. That standard is called TOTP.`, 1.5);
  const ev = [["Single-factor", "Basic", "Password", C.accent5], ["Two-factor (2FA)", "Moderate", "Password + phone OR biometric", C.accent4],
    ["Multi-factor (MFA)", "High", "Password + phone + biometric", C.accent1]];
  s.addShape(pres.shapes.LINE, { x: 0.8, y: 2.55, w: 11.7, h: 0, line: { color: C.background2, width: 6, endArrowType: "triangle" } });
  for (let i = 0; i < 3; i++) {
    const x = 0.6 + i * 4.1;
    s.addShape(pres.shapes.OVAL, { x: x + 1.65, y: 2.3, w: 0.5, h: 0.5, fill: { color: ev[i][3] }, line: { color: C.background1, width: 3 } });
    text(s, ev[i][0], { x, y: 1.45, w: 3.8, h: 0.5, fontSize: 20, bold: true, color: C.text2, align: "center" });
    text(s, ev[i][1] + " security", { x, y: 2.95, w: 3.8, h: 0.4, fontSize: 16, bold: true, color: ev[i][3], align: "center" });
    text(s, ev[i][2], { x, y: 3.35, w: 3.8, h: 0.4, fontSize: 15, color: C.text1, align: "center" });
  }
  card(s, 0.6, 4.2, 3.9, 2.45, "E3F4F2");
  text(s, "Advantages", { x: 0.85, y: 4.35, w: 3.4, h: 0.4, fontSize: 18, bold: true, color: C.accent1 });
  s.addText(["Stolen password alone is useless", "Layered protection", "Stops credential stuffing"].map((t, k) =>
    ({ text: t, options: { bullet: true, breakLine: k < 2 } })), { isTextBox: true, x: 0.85, y: 4.85, w: 3.5, h: 1.7, fontSize: 15, color: C.text1, margin: 0, paraSpaceAfter: 6, valign: "top" });
  card(s, 4.7, 4.2, 3.9, 2.45, "FCE9E4");
  text(s, "Disadvantages", { x: 4.95, y: 4.35, w: 3.4, h: 0.4, fontSize: 18, bold: true, color: C.accent2 });
  s.addText(["Slower login", "Setup takes effort", "Lost phone = access problem"].map((t, k) =>
    ({ text: t, options: { bullet: true, breakLine: k < 2 } })), { isTextBox: true, x: 4.95, y: 4.85, w: 3.5, h: 1.7, fontSize: 15, color: C.text1, margin: 0, paraSpaceAfter: 6, valign: "top" });
  card(s, 8.8, 4.2, 3.9, 2.45, C.text2);
  await badge(s, "FaMobileAlt", 9.05, 4.45, 0.8, C.accent1);
  text(s, "In ShopDB", { x: 10.0, y: 4.55, w: 2.5, h: 0.5, fontSize: 18, bold: true, color: C.background1 });
  text(s, "Password + 6-digit TOTP code (Google Authenticator). Secret stored encrypted.", { x: 9.05, y: 5.35, w: 3.45, h: 1.2, fontSize: 15, color: C.background2 });

  // --- role/attribute based privileges
  s = newSlide("CONTENT", "Role- and attribute-based privileges: the building blocks",
    `The lecture describes four basic elements. USERS are the accounts that connect. AUTHENTICATION verifies them. ROLES group privileges together. PRIVILEGES are the actual rights, like SELECT, INSERT, UPDATE, DELETE or EXECUTE.
The key principle is least privilege: give only what the job needs.
RBAC stops at the table level: "sales may read Orders". ABAC adds a rule about each row: "and only orders from my own region". I will show exactly this in the demo.`, 1.5);
  const chain = [["Users", "accounts that connect", "FaUsers"], ["Authentication", "verify identity", "FaIdCard"],
    ["Roles", "group privileges", "FaUserTag"], ["Privileges", "SELECT · UPDATE · EXECUTE", "FaKey"]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + i * 3.15;
    card(s, x, 1.5, 2.75, 2.2);
    await badge(s, chain[i][2], x + 0.92, 1.7, 0.9, C.accent4);
    text(s, chain[i][0], { x: x + 0.1, y: 2.7, w: 2.55, h: 0.45, fontSize: 19, bold: true, color: C.text2, align: "center" });
    text(s, chain[i][1], { x: x + 0.1, y: 3.15, w: 2.55, h: 0.45, fontSize: 14, color: C.accent5, align: "center" });
    if (i < 3) arrow(s, x + 2.8, 2.6, x + 3.1, 2.6, C.accent5, 3);
  }
  card(s, 0.6, 4.1, 5.95, 2.55, C.background2);
  text(s, "RBAC: table level", { x: 0.9, y: 4.3, w: 5.4, h: 0.45, fontSize: 20, bold: true, color: C.accent4 });
  text(s, "sales_role → SELECT on Orders", { x: 0.9, y: 4.9, w: 5.4, h: 0.45, fontSize: 18, color: C.text1 });
  text(s, "Every salesperson sees every order", { x: 0.9, y: 5.5, w: 5.4, h: 0.45, fontSize: 15, italic: true, color: C.accent5 });
  card(s, 6.75, 4.1, 5.95, 2.55, "E3F4F2");
  text(s, "ABAC: row level, by attributes", { x: 7.05, y: 4.3, w: 5.4, h: 0.45, fontSize: 20, bold: true, color: C.accent1 });
  text(s, "… AND Order.Region = Staff.Region", { x: 7.05, y: 4.9, w: 5.4, h: 0.45, fontSize: 18, color: C.text1 });
  text(s, "Abebe (Addis) sees only Addis orders", { x: 7.05, y: 5.5, w: 5.4, h: 0.45, fontSize: 15, italic: true, color: C.accent5 });
  text(s, "Principle: least privilege", { x: 0.6, y: 6.7 - 0.05, w: 6, h: 0.35, fontSize: 13, bold: true, color: C.accent3 });

  // --- secure coding & query hardening
  s = newSlide("CONTENT", "Query hardening: data must never become code",
    `Secure coding means building security into the database code from the start. The lecture calls this the secure development life cycle. Fixing problems after deployment can cost up to 100 times more.
The most famous problem is SQL injection. On the left, the program glues the user's input into the SQL text. The input contains a quote and OR 1=1, so the WHERE clause is always true and the attacker logs in without a password.
On the right, the same input is sent as a PARAMETER. SQL Server compiles the query first and only then plugs in the value, so the quote is just a character in a username that does not exist.
The other principles on the left of the slide: defence in depth, fail securely, least privilege, input validation, no secrets in code, and error messages that do not leak details.`, 2);
  const pr = ["Defence in depth", "Fail securely", "Least privilege", "Input validation", "Secrets out of code", "Safe error handling"];
  for (let i = 0; i < 6; i++) {
    const y = 1.45 + i * 0.86;
    card(s, 0.6, y, 3.3, 0.7, C.background2);
    text(s, pr[i], { x: 0.8, y: y + 0.17, w: 3.0, h: 0.4, fontSize: 16, bold: true, color: C.text2 });
  }
  text(s, "Input typed in the username box:", { x: 4.3, y: 1.45, w: 8.4, h: 0.4, fontSize: 15, color: C.accent5 });
  box(s, "' OR '1'='1' --", 4.3, 1.9, 8.4, 0.6, C.text1, C.accent3, { fontSize: 20, fontFace: "Courier New" });
  card(s, 4.3, 2.8, 4.1, 3.85, "FCE9E4");
  text(s, "✗ String concatenation", { x: 4.5, y: 2.95, w: 3.8, h: 0.4, fontSize: 18, bold: true, color: C.accent2 });
  text(s, "WHERE Username = '' OR '1'='1' --' AND …", { x: 4.5, y: 3.5, w: 3.75, h: 1.1, fontSize: 15, fontFace: "Courier New", color: C.text1 });
  text(s, "Always TRUE → logged in as the first user, no password needed", { x: 4.5, y: 4.85, w: 3.75, h: 1.4, fontSize: 15, color: C.text1 });
  card(s, 8.6, 2.8, 4.1, 3.85, "E3F4F2");
  text(s, "✓ Parameter / stored procedure", { x: 8.8, y: 2.95, w: 3.8, h: 0.4, fontSize: 18, bold: true, color: C.accent1 });
  text(s, "WHERE Username = @Username", { x: 8.8, y: 3.5, w: 3.75, h: 0.5, fontSize: 15, fontFace: "Courier New", color: C.text1 });
  text(s, "@Username = \"' OR '1'='1' --\"", { x: 8.8, y: 4.05, w: 3.75, h: 0.5, fontSize: 15, fontFace: "Courier New", color: C.text1 });
  text(s, "Just text → no such user → login refused", { x: 8.8, y: 4.85, w: 3.75, h: 1.4, fontSize: 15, color: C.text1 });

  // --- encryption & data protection
  s = newSlide("CONTENT", "Encryption & data protection: protect data in every state",
    `Encryption is a layered defence. Data has three states. AT REST means stored on disk or in a backup. IN MOTION means travelling over the network. IN USE means being processed and shown to users.
Each state has its own tool. TDE encrypts the database files and backups. TLS encrypts the connection. Dynamic data masking hides parts of values like e-mail addresses from people who do not need them.
The lecture also shows column-level encryption for very sensitive fields like card numbers, and Always Encrypted, where even the DBA cannot read the data because the keys stay in the client application.
Finally, data classification: you label sensitive columns so that you know what to protect. I implemented TDE, column encryption, masking and classification, and my app uses an encrypted connection.`, 2);
  const st = [["At rest", "files, logs, backups", "TDE (AES-256)", "FaHdd", true],
    ["In motion", "client ↔ server", "TLS (Encrypt=yes)", "FaExchangeAlt", true],
    ["In use", "query results on screen", "Dynamic data masking", "FaEyeSlash", true]];
  for (let i = 0; i < 3; i++) {
    const x = 0.6 + i * 4.1;
    card(s, x, 1.45, 3.9, 2.2, C.background2);
    await badge(s, st[i][3], x + 0.3, 1.7, 0.85, C.accent4);
    text(s, st[i][0], { x: x + 1.35, y: 1.72, w: 2.4, h: 0.45, fontSize: 22, bold: true, color: C.text2 });
    text(s, st[i][1], { x: x + 1.35, y: 2.2, w: 2.45, h: 0.4, fontSize: 14, color: C.accent5 });
    box(s, st[i][2], x + 0.3, 2.85, 3.3, 0.55, C.accent1, C.background1, { fontSize: 15 });
  }
  const lay = [["TDE", "whole DB files + backups; stolen disk is useless", "Implemented", C.accent1],
    ["Column encryption", "card numbers; only key holders can decrypt", "Implemented", C.accent1],
    ["Always Encrypted", "keys stay in the app; even DBAs see ciphertext", "Explained", C.accent5],
    ["Classification", "label columns: Highly Confidential, Credit Card", "Implemented", C.accent1]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + i * 3.08;
    card(s, x, 3.95, 2.9, 2.7, i === 2 ? C.background2 : "E3F4F2");
    text(s, lay[i][0], { x: x + 0.2, y: 4.1, w: 2.5, h: 0.45, fontSize: 18, bold: true, color: C.text2 });
    text(s, lay[i][1], { x: x + 0.2, y: 4.65, w: 2.5, h: 1.3, fontSize: 15, color: C.text1 });
    tag(s, lay[i][2], x + 0.2, 6.15, lay[i][3]);
  }

  // ======================= PART 2: IMPORTANCE ============================
  section("2 · Why it matters");
  s = newSlide("SECTION", "Why it matters for an online shop",
    `Part two: why does this matter in the real world, especially for an online shop?`, 0.3);
  s.addText("Part 2 · real-world applications and importance", { placeholder: "body" });
  await badge(s, "FaGlobe", 0.9, 2.75, 1.3, C.accent1);

  s = newSlide("CONTENT", "An online shop is a target: money, personal data and trust",
    `An online shop stores exactly what attackers want: customers' personal data, payment data and money flows.
Injection is still in the OWASP Top 10 list of the most critical web application risks; in the 2021 edition it is number three. The lecture reminds us that fixing a vulnerability after deployment can cost up to 100 times more than during development.
Card payments come with the PCI DSS standard, which requires stored card numbers to be unreadable, for example encrypted. And privacy laws such as the EU's GDPR, and Ethiopia's own personal data protection law from 2024, make companies responsible for protecting customer data.
For a shop in Addis Ababa, a breach means fraud, lost customers and legal problems.`, 2);
  const why = [["#3", "Injection in the OWASP Top 10 (2021)", C.accent2],
    ["100×", "cost of fixing after deployment vs during development (lecture)", C.accent3],
    ["PCI DSS", "stored card numbers must be unreadable", C.accent4],
    ["Privacy law", "GDPR · Ethiopia's 2024 personal data protection proclamation", C.accent1]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + (i % 2) * 6.15, y = 1.45 + Math.floor(i / 2) * 2.0;
    card(s, x, y, 5.95, 1.8, C.background2);
    text(s, why[i][0], { x: x + 0.3, y: y + 0.25, w: 2.4, h: 1.3, fontSize: why[i][0].length > 5 ? 28 : 48, bold: true, color: why[i][2], valign: "middle" });
    text(s, why[i][1], { x: x + 2.8, y: y + 0.25, w: 2.95, h: 1.3, fontSize: 16, color: C.text1, valign: "middle" });
  }
  const harm = [["FaUserSecret", "Stolen customer data"], ["FaCreditCard", "Card fraud"], ["FaTags", "Price manipulation"], ["FaHeartBroken", "Lost trust"]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + i * 3.08;
    await badge(s, harm[i][0], x, 5.65, 0.75, C.accent2);
    text(s, harm[i][1], { x: x + 0.9, y: 5.82, w: 2.1, h: 0.45, fontSize: 16, bold: true, color: C.text2 });
  }

  s = newSlide("CONTENT", "Risk identification checklist: 10 digital assets of ShopDB",
    `Before building anything I made a risk checklist, using the form from the assignment.
For each digital asset I wrote the threat, the weakness that allows it, and how likely and how harmful it is. Likelihood times impact, each from 1 to 3, gives the rating: 9 is critical, 6 is high.
Two risks are critical: weak passwords and SQL injection, so I fixed those first and I demonstrate them first. Every row has a control, and the last column shows which script implements it. So this table is also the map of my whole project.`, 2);
  const R = { Critical: HEX.accent2, High: "E08E0B", Medium: HEX.accent4, Low: HEX.accent1 };
  const risks = [
    ["1", "Customer records", "Account takeover", "High", "High", "Critical", "Password policy, lockout, MFA · 02/05/07"],
    ["2", "Customer/order tables", "SQL injection", "High", "High", "Critical", "Stored procedures, parameters · 05 + app"],
    ["3", "Payment card data", "Theft, insider reading", "Med", "High", "High", "Column encryption + masking · 06/04"],
    ["4", "DB files & backups", "Stolen disk / backup", "Med", "High", "High", "TDE (AES-256) · 06"],
    ["5", "User credentials", "Offline cracking", "Med", "High", "High", "Salted slow hash · 01/05"],
    ["6", "Admin accounts", "Privilege abuse", "Med", "High", "High", "RBAC least privilege · 03"],
    ["7", "Orders seen by staff", "Insider browsing", "High", "Med", "High", "ABAC with RLS · 04"],
    ["8", "Product prices", "Price fraud", "Med", "Med", "Medium", "DENY UPDATE to sales · 03"],
    ["9", "TDE certificate", "Key loss", "Low", "High", "Medium", "Cert backup + restore drill · 06b"],
    ["10", "Audit log", "Log tampering", "Low", "Med", "Low", "DENY UPDATE/DELETE · 03"],
  ];
  const hdr = ["#", "Asset", "Threat", "Likelihood", "Impact", "Rating", "Mitigation · script"].map((t) =>
    ({ text: t, options: { bold: true, color: HEX.lt1, fill: { color: HEX.dk2 } } }));
  const rows = [hdr, ...risks.map((r, i) => r.map((v, c) => ({ text: v, options: {
    fill: { color: c === 5 ? R[v] : (i % 2 ? HEX.lt1 : HEX.lt2) },
    color: c === 5 ? HEX.lt1 : HEX.dk1, bold: c === 5 } })))];
  s.addTable(rows, { x: 0.6, y: 1.35, w: 12.1, colW: [0.45, 2.3, 2.35, 1.25, 0.95, 1.15, 3.65],
    fontSize: 13, rowH: 0.46, valign: "middle", border: { type: "solid", color: HEX.lt1, pt: 1 }, margin: 0.06 });

  // ======================= PART 3: APPROACH ==============================
  section("3 · Implementation approach");
  s = newSlide("SECTION", "How I built it",
    `Part three: my implementation approach. As the assignment asks, I show it with diagrams, not with code.`, 0.3);
  s.addText("Part 3 · architecture · build order · data model · flows (no code)", { placeholder: "body" });
  await badge(s, "FaSitemap", 0.9, 2.75, 1.3, C.accent1);

  s = newSlide("CONTENT", "Architecture: three doors into the same database",
    `This is the architecture. A browser talks to my ShopDB web shop, a small Flask application. It runs only on 127.0.0.1, so nobody else on the network can reach it.
The shop has three "doors" into SQL Server. The green door is used by customers: the storefront, cart, checkout and account pages. It connects as shop_app, a login that may only EXECUTE the stored procedures in the "app" schema; it cannot read any table directly.
The gold door is the staff portal. Staff log in with their OWN SQL Server login, for example sales_addis. Every query on their dashboard runs with their real permissions, so SQL Server itself decides what they may see.
The red door is the security lab: a deliberately vulnerable login and search, for the demo only. It glues input into SQL strings and connects as legacy_app, which can read and write every table.
Inside SQL Server the tables live in dbo, the procedures in app, and the row-level security rules in sec. On disk everything is encrypted with TDE. All passwords are in a .env file, never in the code.`, 2);
  box(s, "Browser", 0.6, 3.2, 1.6, 1.0, C.accent4, C.background1, { fontSize: 18 });
  card(s, 2.6, 1.45, 3.6, 4.45, C.background2);
  text(s, "ShopDB web shop (Flask)", { x: 2.75, y: 1.55, w: 3.3, h: 0.4, fontSize: 17, bold: true, color: C.text2, align: "center" });
  text(s, "listens on 127.0.0.1 only", { x: 2.75, y: 1.95, w: 3.3, h: 0.3, fontSize: 13, color: C.accent5, align: "center" });
  box(s, "Shop · cart · checkout · account\nprocedures + parameters", 2.8, 2.4, 3.2, 1.0, C.accent1, C.background1, { fontSize: 13 });
  box(s, "Staff portal\nstaff's own SQL login", 2.8, 3.55, 3.2, 1.0, C.accent3, C.text1, { fontSize: 13 });
  box(s, "Security lab\nstring concatenation · LAB ONLY", 2.8, 4.7, 3.2, 1.0, C.accent2, C.background1, { fontSize: 13 });
  arrow(s, 2.25, 3.7, 2.6, 3.7, C.accent5, 3);
  box(s, "shop_app\nEXECUTE schema app only", 6.65, 2.4, 2.5, 1.0, C.accent1, C.background1, { fontSize: 13 });
  box(s, "sales_addis, support_dawit…\nreal role permissions", 6.65, 3.55, 2.5, 1.0, C.accent3, C.text1, { fontSize: 12 });
  box(s, "legacy_app\nread + write every table", 6.65, 4.7, 2.5, 1.0, C.accent2, C.background1, { fontSize: 13 });
  arrow(s, 6.0, 2.9, 6.65, 2.9, C.accent1, 3); arrow(s, 6.0, 4.05, 6.65, 4.05, C.accent3, 3); arrow(s, 6.0, 5.2, 6.65, 5.2, C.accent2, 3);
  card(s, 9.55, 1.45, 3.15, 4.45, C.text2);
  text(s, "SQL Server 2022 · ShopDB", { x: 9.7, y: 1.57, w: 2.85, h: 0.45, fontSize: 15, bold: true, color: C.background1, align: "center" });
  [["app · procedures", C.accent1], ["dbo · tables", C.accent4], ["sec · RLS rules", C.accent6]].forEach(([t, f], i) =>
    box(s, t, 9.8, 2.15 + i * 0.75, 2.65, 0.6, f, C.background1, { fontSize: 14 }));
  box(s, "Disk: .mdf · .ldf · .bak\nencrypted by TDE", 9.8, 4.55, 2.65, 0.95, C.accent3, C.text1, { fontSize: 13 });
  arrow(s, 9.15, 2.9, 9.8, 2.45, C.accent1, 3); arrow(s, 9.15, 4.05, 9.8, 3.2, C.accent3, 3); arrow(s, 9.15, 5.2, 9.8, 3.25, C.accent2, 3);
  box(s, ".env: all passwords & keys (never committed)", 2.6, 6.15, 5.0, 0.55, C.background2, C.text2, { fontSize: 14 });
  box(s, "Phone: TOTP code (MFA)", 8.2, 6.15, 4.5, 0.55, C.background2, C.text2, { fontSize: 14 });

  s = newSlide("CONTENT", "Build order: one script per security layer",
    `I built the project in layers, one numbered script per layer, and each script can be run again safely.
Script 1 creates the database with all constraints and sample data. Script 2 adds the password policy. Script 3 adds role-based access control, and script 4 adds attribute-based control with row-level security and masking. Script 5 contains the hardened stored procedures against SQL injection. Script 6 adds encryption: TDE, column encryption and data classification, and 6b is a disaster drill for a lost certificate. Script 7 adds MFA.
A runner script reads the passwords from the .env file, so no password is written in any SQL file. Building everything from zero takes about 10 seconds.`, 1);
  const steps = [["01", "Schema", "tables · constraints · data", "FaDatabase"], ["02", "Passwords", "policy · history · lockout", "FaKey"],
    ["03", "RBAC", "roles · GRANT · DENY", "FaUserTag"], ["04", "ABAC", "RLS · attributes · masking", "FaSlidersH"],
    ["05", "Procedures", "parameters · validation", "FaCode"], ["06", "Encryption", "TDE · column · labels", "FaLock"],
    ["06b", "Drill", "lost certificate", "FaFirstAid"], ["07", "MFA", "TOTP procedures", "FaMobileAlt"]];
  for (let i = 0; i < 8; i++) {
    const x = 0.6 + (i % 4) * 3.1, y = 1.5 + Math.floor(i / 4) * 2.55;
    card(s, x, y, 2.85, 2.25, C.background2);
    await badge(s, steps[i][3], x + 0.25, y + 0.25, 0.8, i === 6 ? C.accent3 : C.accent1);
    text(s, steps[i][0], { x: x + 1.2, y: y + 0.25, w: 1.5, h: 0.45, fontSize: 22, bold: true, color: C.accent5 });
    text(s, steps[i][1], { x: x + 1.2, y: y + 0.68, w: 1.6, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
    text(s, steps[i][2], { x: x + 0.25, y: y + 1.35, w: 2.45, h: 0.7, fontSize: 14, color: C.text1 });
    if (i % 4 < 3) arrow(s, x + 2.88, y + 1.12, x + 3.08, y + 1.12, C.accent5, 2);
  }
  text(s, "Runner reads passwords from .env → sqlcmd variables · every script is re-runnable · full rebuild ≈ 10 s",
    { x: 0.6, y: 6.6, w: 12.1, h: 0.35, fontSize: 14, italic: true, color: C.accent4 });

  s = newSlide("CONTENT", "Data model: 8 tables protected by constraints",
    `This is the data model. Customers place Orders; each order has OrderItems that point to Products, and one Payment. Users are the website accounts; each one belongs either to a customer or to a staff member. The Staff table also stores the attributes I use for ABAC: department and region. Every important action is written to the AuditLog.
Constraints are the first security layer: the database itself refuses bad data, even if the application has a bug. Primary and foreign keys, UNIQUE for e-mails and usernames, CHECK for prices, phone format and allowed characters in usernames, DEFAULT values, and NOT NULL.
Passwords are stored as a random salt plus a hash repeated 5,000 times, and the card number column is encrypted later by script 6.`, 1.5);
  const T = (n, x, y, f = C.accent4) => box(s, n, x, y, 2.0, 0.65, f, C.background1, { fontSize: 15 });
  T("Staff", 0.6, 1.6, C.accent6); T("Users", 0.6, 3.2); T("Customers", 3.4, 3.2);
  T("Orders", 6.2, 3.2); T("OrderItems", 6.2, 4.9); T("Products", 9.0, 4.9); T("Payments", 9.0, 3.2); T("AuditLog", 3.4, 1.6, C.accent5);
  arrow(s, 1.6, 3.2, 1.6, 2.25, C.accent5, 2); arrow(s, 2.6, 3.52, 3.4, 3.52, C.accent5, 2);
  arrow(s, 6.2, 3.52, 5.4, 3.52, C.accent5, 2); arrow(s, 7.2, 4.9, 7.2, 3.85, C.accent5, 2);
  arrow(s, 8.2, 5.22, 9.0, 5.22, C.accent5, 2); arrow(s, 9.0, 3.52, 8.2, 3.52, C.accent5, 2);
  text(s, "arrow = FOREIGN KEY (references)", { x: 0.6, y: 5.7, w: 4.5, h: 0.35, fontSize: 13, italic: true, color: C.accent5 });
  box(s, "Password = salt + 5,000× SHA-512", 0.6, 4.3, 2.6, 0.9, C.accent3, C.text1, { fontSize: 13 });
  text(s, "CardNumber → encrypted AES-256 (script 06)", { x: 9.0, y: 3.95, w: 3.7, h: 0.4, fontSize: 14, bold: true, color: C.accent2 });
  text(s, "Staff attributes for ABAC: Department · Region · IsActive", { x: 1.8, y: 2.45, w: 4.4, h: 0.4, fontSize: 14, italic: true, color: C.accent6 });
  card(s, 9.0, 1.4, 3.7, 1.55, C.background2);
  text(s, "Constraints used", { x: 9.2, y: 1.5, w: 3.3, h: 0.4, fontSize: 16, bold: true, color: C.text2 });
  text(s, "PRIMARY KEY · FOREIGN KEY · UNIQUE · CHECK · DEFAULT · NOT NULL", { x: 9.2, y: 1.95, w: 3.3, h: 0.9, fontSize: 14, color: C.text1 });
  card(s, 0.6, 6.1, 12.1, 0.7, "E3F4F2");
  text(s, "Test: 4 bad inserts (negative price, duplicate e-mail, unknown customer, quote in username) → all 4 rejected by the database itself",
    { x: 0.8, y: 6.25, w: 11.7, h: 0.45, fontSize: 14, color: C.text1 });

  s = newSlide("CONTENT", "The hardened login, step by step",
    `This flowchart shows what happens when someone logs in through the hardened path.
First the input is validated: a username may only contain letters, digits, dot and underscore. Then the user is looked up with a parameter, never by building SQL text. If the account is locked, we stop. Then the password is hashed with the user's own salt and compared.
A wrong password increases the failed-attempts counter, and at five the account is locked for 15 minutes. The message is always the same, "invalid username or password", so an attacker cannot learn which usernames exist.
If the password is right and MFA is on, the user must also type the code from the phone. Only then the session starts, and the app stores the customer ID in SESSION_CONTEXT, which row-level security uses later. Every step is written to the audit log.`, 1.5);
  const fl = [["Validate input", "allow-list of characters", C.accent4], ["Find user", "parameter, not SQL text", C.accent4],
    ["Locked?", "yes → stop", C.accent3], ["Hash + compare", "salt + 5,000× SHA-512", C.accent4],
    ["MFA on?", "→ 6-digit TOTP code", C.accent6], ["Session", "SESSION_CONTEXT(CustomerID)", C.accent1]];
  for (let i = 0; i < 6; i++) {
    const x = 0.6 + i * 2.07;
    box(s, fl[i][0], x, 2.0, 1.8, 0.9, fl[i][2], i === 2 ? C.text1 : C.background1, { fontSize: 15 });
    text(s, fl[i][1], { x, y: 3.0, w: 1.8, h: 0.75, fontSize: 13, color: C.text1, align: "center" });
    if (i < 5) arrow(s, x + 1.82, 2.45, x + 2.05, 2.45, C.accent5, 3);
  }
  card(s, 0.6, 4.1, 7.3, 2.55, "FCE9E4");
  await badge(s, "FaTimesCircle", 0.85, 4.35, 0.75, C.accent2);
  text(s, "Wrong password", { x: 1.8, y: 4.42, w: 5.8, h: 0.45, fontSize: 19, bold: true, color: C.accent2 });
  s.addText(["FailedAttempts + 1 · at 5 → locked for 15 minutes", "Same message for every failure: \"Invalid username or password\"",
    "Unknown user is hashed too → same timing, no username discovery"].map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < 2 } })),
    { isTextBox: true, x: 0.9, y: 5.2, w: 6.8, h: 1.4, fontSize: 15, color: C.text1, margin: 0, paraSpaceAfter: 6, valign: "top" });
  card(s, 8.1, 4.1, 4.6, 2.55, C.text2);
  await badge(s, "FaClipboardCheck", 8.35, 4.35, 0.75, C.accent1);
  text(s, "Every step audited", { x: 9.3, y: 4.42, w: 3.3, h: 0.45, fontSize: 19, bold: true, color: C.background1 });
  text(s, "LOGIN_SUCCESS · LOGIN_FAILED · ACCOUNT_LOCKED · MFA_FAILED → AuditLog (append-only)", { x: 8.4, y: 5.1, w: 4.1, h: 1.3, fontSize: 15, color: C.background2 });

  s = newSlide("CONTENT", "Access design: roles pick tables, attributes pick rows",
    `On the left are my five roles and the website login. Each role gets only what the job needs. Admin manages the shop but is NOT a database owner: it cannot drop tables, cannot read password hashes, and cannot delete the audit log. The website login can only execute procedures.
On the right is the ABAC part. The same SELECT on the Orders table returns a different number of rows depending on the user's attributes. Admin, auditor and support, whose region is ALL, see all 10 orders. Abebe in sales, region Addis Ababa, sees 4. Hana in Hawassa sees 3. These are the real numbers from my test.
I also used dynamic data masking: support staff see e-mails like s-X-X-X at X-X-X-X dot com, while sales see the real address because they need to contact customers.`, 1.5);
  const roles = [["admin_role", "manage shop data", "drop tables · read hashes · delete audit"],
    ["sales_role", "read orders · update status", "change prices · see card numbers"],
    ["support_role", "read customers & orders", "payments · unmasked contacts"],
    ["auditor_role", "read everything + audit log", "any INSERT · UPDATE · DELETE"],
    ["customer_role (website)", "EXECUTE app.* procedures", "any direct table access"]];
  text(s, "CAN", { x: 3.15, y: 1.35, w: 2.6, h: 0.3, fontSize: 13, bold: true, color: C.accent1 });
  text(s, "CANNOT (DENY)", { x: 5.55, y: 1.35, w: 2.0, h: 0.3, fontSize: 13, bold: true, color: C.accent2 });
  for (let i = 0; i < 5; i++) {
    const y = 1.7 + i * 1.0;
    card(s, 0.6, y, 7.0, 0.88, i % 2 ? C.background1 : C.background2);
    text(s, roles[i][0], { x: 0.75, y: y + 0.12, w: 2.35, h: 0.65, fontSize: 15, bold: true, color: C.text2, valign: "middle" });
    text(s, roles[i][1], { x: 3.15, y: y + 0.12, w: 2.3, h: 0.65, fontSize: 14, color: C.text1, valign: "middle" });
    text(s, roles[i][2], { x: 5.55, y: y + 0.12, w: 2.0, h: 0.65, fontSize: 14, color: C.accent2, valign: "middle" });
  }
  s.addChart(pres.charts.BAR, [{ name: "Orders visible", labels: ["admin", "auditor", "support", "sales_addis", "sales_hawassa"], values: [10, 10, 10, 4, 3] }], {
    x: 7.9, y: 1.35, w: 4.8, h: 4.3, barDir: "bar", chartColors: [HEX.accent1],
    showTitle: true, title: "Same SELECT * FROM Orders: rows returned", titleFontSize: 14, titleColor: HEX.dk2, titleFontFace: "+mn-lt",
    showValue: true, dataLabelPosition: "outEnd", dataLabelFontSize: 13, dataLabelColor: HEX.dk1, dataLabelFontFace: "+mn-lt",
    catAxisLabelColor: HEX.dk1, catAxisLabelFontSize: 13, catAxisLabelFontFace: "+mn-lt", catAxisOrientation: "maxMin",
    valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" }, showLegend: false, valAxisMaxVal: 12,
  });
  card(s, 7.9, 5.8, 4.8, 0.85, "E3F4F2");
  text(s, "Rule: active Sales/Support staff see rows where row.Region = their Region (or ALL)", { x: 8.05, y: 5.88, w: 4.5, h: 0.7, fontSize: 13, color: C.text1, valign: "middle" });

  s = newSlide("CONTENT", "Encryption design: a chain of keys",
    `Encryption is only as safe as its keys, so I designed two key chains.
On the left is TDE. The service master key protects the master key of the server, which protects my certificate, which protects the database encryption key, which encrypts every page written to disk, including the backups.
On the right is column encryption for card numbers. Inside ShopDB, a certificate protects a symmetric AES-256 key, and only the admin role is allowed to use it. Sales can select the column but gets binary data or NULL.
The most important lesson: I backed up the TDE certificate and its private key to files with a password. Without them, an encrypted backup can never be restored, not even by me. My drill script proves this.`, 1.5);
  const tde = [["Service Master Key", "created by SQL Server setup"], ["Master key [master]", "password-protected"],
    ["Certificate TDE_ShopDB_Cert", "backed up to .cer + .pvk"], ["Database Encryption Key", "AES-256"], ["Data pages · logs · backups", "encrypted on disk"]];
  const col = [["Master key [ShopDB]", "inside the database"], ["Certificate CardDataCert", "CONTROL: admin_role only"],
    ["Symmetric key CardDataKey", "AES-256"], ["Payments.CardNumberEnc", "ciphertext + authenticator"]];
  text(s, "TDE: data at rest", { x: 0.6, y: 1.35, w: 5.5, h: 0.45, fontSize: 20, bold: true, color: C.accent4 });
  tde.forEach(([a, b], i) => {
    const y = 1.9 + i * 0.95;
    box(s, a, 0.6, y, 3.4, 0.7, i === 2 ? C.accent3 : C.accent4, i === 2 ? C.text1 : C.background1, { fontSize: 14 });
    text(s, b, { x: 4.15, y: y + 0.15, w: 2.2, h: 0.45, fontSize: 14, color: C.text1 });
    if (i < 4) arrow(s, 2.3, y + 0.72, 2.3, y + 0.93, C.accent5, 2);
  });
  text(s, "Column encryption: card numbers", { x: 6.75, y: 1.35, w: 5.9, h: 0.45, fontSize: 20, bold: true, color: C.accent1 });
  col.forEach(([a, b], i) => {
    const y = 1.9 + i * 0.95;
    box(s, a, 6.75, y, 3.4, 0.7, C.accent1, C.background1, { fontSize: 14 });
    text(s, b, { x: 10.3, y: y + 0.15, w: 2.4, h: 0.45, fontSize: 14, color: C.text1 });
    if (i < 3) arrow(s, 8.45, y + 0.72, 8.45, y + 0.93, C.accent5, 2);
  });
  card(s, 6.75, 5.75, 5.95, 0.95, "FCE9E4");
  text(s, "Lose the certificate + private key + password → the encrypted backup is lost forever",
    { x: 6.95, y: 5.82, w: 5.6, h: 0.8, fontSize: 15, bold: true, color: C.accent2, valign: "middle" });

  // ======================= PART 4: RESULTS ===============================
  section("4 · Results & demonstration");
  s = newSlide("SECTION", "Live demonstration",
    `Part four: the results. I will now switch to the live demonstration. If anything fails, the next slides show the same results as screenshots from my test runs.`, 0.5);
  s.addText("Part 4 · attack the red door, then the green door · then SSMS", { placeholder: "body" });
  await badge(s, "FaLaptopCode", 0.9, 2.75, 1.3, C.accent2);

  s = newSlide("CONTENT", "Demo plan (about 10 minutes)",
    `Here is the order of my demo, so you can follow along.
First, the security lab: I attack the vulnerable login and search with SQL injection, and then try exactly the same input on the hardened version. Second, the shop itself: I log in as a customer, fill the cart, check out, and show that "My orders" contains only my orders. Third, lockout and the MFA login. Fourth, the staff portal: I log in as Abebe from sales, then as Dawit from support, then as the admin, and you will see the same page show different rows, masked e-mails, card numbers or "permission denied". Last, SSMS: the TDE status and the audit log, which recorded everything I just did.`, 10);
  const demo = [["1", "Security lab: red vs green", "login bypass · dump hashes · 1-ETB price", "FaBug"],
    ["2", "Shop: cart → checkout → my orders", "procedures · SESSION_CONTEXT · RLS", "FaShoppingCart"],
    ["3", "Lockout & MFA", "5 wrong passwords · phone code", "FaMobileAlt"],
    ["4", "Staff portal: sales vs support vs admin", "RBAC · ABAC · masking · card decryption", "FaUsers"],
    ["5", "SSMS: TDE + audit trail", "encryption state · every attack recorded", "FaLock"]];
  for (let i = 0; i < 5; i++) {
    const y = 1.45 + i * 1.05;
    card(s, 0.6, y, 12.1, 0.9, i % 2 ? C.background1 : C.background2);
    await badge(s, demo[i][3], 0.8, y + 0.1, 0.7, i === 0 ? C.accent2 : (i === 3 ? C.accent3 : C.accent1));
    text(s, demo[i][0] + ". " + demo[i][1], { x: 1.75, y: y + 0.2, w: 6.0, h: 0.5, fontSize: 19, bold: true, color: C.text2 });
    text(s, demo[i][2], { x: 7.8, y: y + 0.22, w: 4.8, h: 0.5, fontSize: 16, color: C.text1 });
  }

  s = newSlide("CONTENT", "Result 1: the same input, two different outcomes",
    `Result one. On the left, I typed quote OR 1=1 dash dash into the vulnerable login. You can see the SQL that the app built: the WHERE clause became always true, and I am logged in as Selam without knowing her password.
On the right, exactly the same input in the hardened login: "Invalid username or password". The stored procedure received it as a parameter, so it was just a strange username. It was also rejected by input validation and written to the audit log.`, 0.75);
  await imgFit(s, SHOT("app/02_vulnerable_login_bypassed.png"), 0.6, 1.45, 5.95, 4.6, "Vulnerable login bypassed with OR 1=1");
  await imgFit(s, SHOT("app/03_hardened_login_rejected.png"), 6.75, 1.45, 5.95, 4.6, "Hardened login rejects the same payload");
  tag(s, "✗ VULNERABLE: logged in without password", 0.6, 5.7, C.accent2, 5.95);
  tag(s, "✓ HARDENED: Invalid username or password", 6.75, 5.7, C.accent1, 5.95);
  text(s, "Same input:  ' OR '1'='1' --   in the username box", { x: 0.6, y: 6.2, w: 12.1, h: 0.4, fontSize: 15, italic: true, color: C.accent4, align: "center" });

  const dump = await cropBox(SHOT("app/04_vulnerable_search_union_dump.png"), path.join(IMG, "union_dump_crop.png"), 160, 2540, 2240, 1200);
  const laptop = await cropBox(SHOT("app/07b_laptop_now_costs_1_ETB.png"), path.join(IMG, "laptop_crop.png"), 140, 620, 2280, 900);
  const blocked = await cropBox(SHOT("app/05_hardened_search_union_blocked.png"), path.join(IMG, "blocked_crop.png"), 140, 380, 2280, 900);
  s = newSlide("CONTENT", "Result 2: data theft and price fraud, blocked",
    `Result two: the search box. With a UNION injection the vulnerable search returns every username together with its password hash. Thanks to the salt and the 5,000 rounds these are hard to crack, but they should never leak.
A second payload, a stacked UPDATE, changed the laptop price to 1 birr. That is real fraud.
On the hardened side the same inputs return nothing, and the parameters are shown separately from the SQL text. The website login has no right to read tables anyway, so even a mistake in the code would fail.`, 0.75);
  await imgFit(s, dump, 0.6, 1.45, 7.0, 3.8, "UNION injection dumps usernames and password hashes");
  text(s, "✗ Red search + UNION payload → every username and password hash", { x: 0.6, y: 5.35, w: 7.0, h: 0.4, fontSize: 14, bold: true, color: C.accent2 });
  card(s, 0.6, 5.85, 7.0, 0.85, C.background2);
  text(s, "Red door: concatenation + over-privileged login + raw errors · Green door: parameters + allow-lists + EXECUTE-only login",
    { x: 0.8, y: 5.9, w: 6.6, h: 0.75, fontSize: 14, color: C.text1, valign: "middle" });
  await imgFit(s, laptop, 7.85, 1.45, 4.85, 2.25, "Laptop price changed to 1 ETB");
  text(s, "✗ Stacked UPDATE: laptop now costs 1.00 ETB", { x: 7.85, y: 3.8, w: 4.85, h: 0.4, fontSize: 14, bold: true, color: C.accent2 });
  await imgFit(s, blocked, 7.85, 4.3, 4.85, 2.25, "Hardened search returns nothing");
  text(s, "✓ Hardened search, same payload: 0 rows", { x: 7.85, y: 6.6, w: 4.85, h: 0.35, fontSize: 14, bold: true, color: C.accent1 });

  s = newSlide("CONTENT", "Result 3: a real shop, secured on every page",
    `Result three is the shop itself. On the left is the storefront: the search box, the category and the sort order all go to the stored procedure app.sp_SearchProducts as parameters.
In the middle is the cart. At checkout the whole cart is sent to app.sp_PlaceOrderCart as JSON data, which SQL Server converts into a typed table of numbers. Stock, order, order lines and payment are created in one transaction, and the customer number comes from the login session, never from the form, so nobody can order as someone else.
On the right, "My orders": the procedure has no WHERE clause, and Row-Level Security returns only Selam's own orders, including the one she just placed.`, 0.75);
  const sf = await cropBox(SHOT("app/01_storefront.png"), path.join(IMG, "storefront_crop.png"), 0, 0, 2560, 1500);
  const ct = await cropBox(SHOT("app/10a_cart.png"), path.join(IMG, "cart_crop.png"), 0, 0, 2560, 1250);
  const mo = await cropBox(SHOT("app/09_my_orders_rls.png"), path.join(IMG, "orders_crop.png"), 0, 0, 2560, 1250);
  await imgFit(s, sf, 0.6, 1.45, 3.9, 3.4, "Storefront");
  await imgFit(s, ct, 4.7, 1.45, 3.9, 3.4, "Cart and checkout");
  await imgFit(s, mo, 8.8, 1.45, 3.9, 3.4, "My orders (Row-Level Security)");
  const sh = [["Storefront", "search · category · sort → app.sp_SearchProducts (parameters, allow-list)"],
    ["Cart → checkout", "app.sp_PlaceOrderCart: typed JSON, one transaction, customer from the session"],
    ["My orders", "no WHERE clause; Row-Level Security shows only my rows"]];
  for (let i = 0; i < 3; i++) {
    const x = 0.6 + i * 4.1;
    card(s, x, 4.65, 3.9, 2.0, i === 1 ? "E3F4F2" : C.background2);
    text(s, sh[i][0], { x: x + 0.25, y: 4.8, w: 3.4, h: 0.45, fontSize: 18, bold: true, color: C.text2 });
    text(s, sh[i][1], { x: x + 0.25, y: 5.3, w: 3.4, h: 1.25, fontSize: 15, color: C.text1 });
  }

  s = newSlide("CONTENT", "Result 4: staff portal, same page, different people",
    `Result four is the staff portal, my favourite part. Staff log in with their own SQL Server login, and the page runs exactly the same queries for everyone. The web code does not decide anything: SQL Server does.
On the left is Abebe from sales in Addis Ababa. His attributes are shown at the top. SQL Server lets him read orders, but only the Addis ones, and lets him change an order status, but denies changing prices, reading password hashes or the audit log. Card numbers stay NULL because he has no key.
In the middle is Dawit from support: he sees orders from every region, but customer e-mails and phones are masked, and payments are denied completely.
On the right is the admin: she sees real card numbers because she holds the key permission, but even she may not read password hashes, delete the audit log or drop a table.`, 0.75);
  const p1 = await cropBox(SHOT("app/18_staff_sales_addis.png"), path.join(IMG, "staff_sales_crop.png"), 150, 160, 2260, 1080);
  const p2 = await cropBox(SHOT("app/18_staff_support_dawit.png"), path.join(IMG, "staff_support_crop.png"), 150, 160, 2260, 1080);
  const p3 = await cropBox(SHOT("app/18_staff_shop_admin.png"), path.join(IMG, "staff_admin_crop.png"), 150, 160, 2260, 1080);
  await imgFit(s, p1, 0.6, 1.4, 7.3, 3.6, "Staff portal as sales_addis");
  await imgFit(s, p2, 8.2, 1.4, 4.5, 2.2, "Staff portal as support_dawit");
  await imgFit(s, p3, 8.2, 3.75, 4.5, 2.2, "Staff portal as shop_admin");
  const sp = [["sales_addis (Sales · Addis): ", "Addis orders only · status ✓ · prices ✗ · cards NULL · audit ✗", C.accent3],
    ["support_dawit (Support · ALL): ", "all regions · e-mails masked · payments ✗", C.accent4],
    ["shop_admin (Admin): ", "prices ✓ · real card numbers · hashes ✗ · delete audit ✗", C.accent1]];
  for (let i = 0; i < 3; i++) {
    const x = 0.6 + i * 4.1;
    card(s, x, 6.05, 3.9, 0.85, C.background2);
    s.addText([{ text: sp[i][0], options: { bold: true, color: sp[i][2] } }, { text: sp[i][1] }],
      { isTextBox: true, x: x + 0.15, y: 6.08, w: 3.6, h: 0.8, fontSize: 13, color: C.text1, margin: 0, valign: "middle" });
  }

  s = newSlide("CONTENT", "Result 5: least privilege, proven for every role",
    `Result five is the permission matrix. My script logs in as each user with EXECUTE AS, tries ten actions, and records whether SQL Server allowed or denied it. Everything is inside a transaction that is rolled back, so nothing changes.
Look at the website_app column: it is denied on every table, and only allowed to execute the app procedures. Nobody can read password hashes or delete the audit log, not even admin. Only the deliberately bad legacy login on the right can do the dangerous things, and that is exactly why injection on the red door was so damaging.`, 0.75);
  await imgFit(s, SHOT("sql/sql_03_permission_matrix.png"), 0.6, 1.45, 12.1, 4.8, "Permission matrix", false);
  text(s, "DROP TABLE is denied even for admin: admin_role is not db_owner", { x: 0.6, y: 6.4, w: 12.1, h: 0.4, fontSize: 15, italic: true, color: C.accent4 });

  s = newSlide("CONTENT", "Result 6: same query, different rows and columns",
    `Result six is ABAC. This is real output: one SELECT on Orders, run as five users. Admin, auditor and support see all ten, Abebe in Addis sees four, Hana in Hawassa sees three.
Below, the same SELECT on Customers: Abebe sees only Addis customers with real e-mail and phone. Dawit from support sees all customers, but masked.
On the right you see why this is attribute-based and not role-based: when I moved Abebe to Hawassa I only changed his Region attribute, not his role, and he immediately saw the Hawassa orders. When I set IsActive to zero, he saw nothing.`, 0.75);
  await imgFit(s, SHOT("sql/sql_04_rls_masking.png"), 0.6, 1.45, 7.0, 5.3, "RLS and masking results", false);
  await imgFit(s, SHOT("sql/sql_04_attribute_change.png"), 7.85, 1.45, 4.85, 3.2, "Changing attributes changes access", false);
  card(s, 7.85, 3.55, 4.85, 1.8, "E3F4F2");
  text(s, "Change an ATTRIBUTE, not a role: moved to Hawassa → sees Hawassa orders; deactivated → sees 0 rows",
    { x: 8.05, y: 3.65, w: 4.5, h: 1.6, fontSize: 15, color: C.text1, valign: "middle" });

  s = newSlide("CONTENT", "Result 7: encrypted at rest, and the certificate really matters",
    `Result seven is TDE. The top-left shows the encryption state 3, which means encrypted, with AES-256 protected by my certificate. SQL Server also encrypts tempdb automatically.
Below it is the proof: I searched the backup files for a product code and a test card number. In the backup taken BEFORE TDE, both were found as readable text. In the backup taken AFTER TDE, nothing was found.
On the right is my disaster drill. Without the certificate, restoring the encrypted backup fails with error 33111, "cannot find server certificate". After restoring the certificate from my backup files, the restore works and all data is there.`, 0.75);
  await imgFit(s, SHOT("sql/sql_06_tde_status.png"), 0.6, 1.45, 5.6, 3.1, "TDE status and backup search", false);
  await imgFit(s, SHOT("sql/sql_06b_lost_cert_drill.png"), 6.45, 1.45, 6.25, 3.1, "Lost certificate drill", false);
  const tk = [["State 3 = ENCRYPTED", "AES-256, protected by TDE_ShopDB_Cert", C.accent1],
    ["Backup: 2 hits → 0 hits", "card number & SKU readable in the backup only before TDE", C.accent4],
    ["No certificate → Msg 33111", "restore certificate from .cer + .pvk → success", C.accent3]];
  for (let i = 0; i < 3; i++) {
    const x = 0.6 + i * 4.1;
    card(s, x, 4.75, 3.9, 1.9, C.background2);
    text(s, tk[i][0], { x: x + 0.25, y: 4.9, w: 3.4, h: 0.8, fontSize: 18, bold: true, color: tk[i][2] });
    text(s, tk[i][1], { x: x + 0.25, y: 5.75, w: 3.4, h: 0.8, fontSize: 14, color: C.text1 });
  }

  s = newSlide("CONTENT", "Result 8: card numbers and MFA",
    `Result eight. On the left, card numbers. The admin role holds the key permission and sees the real numbers; I used official test card numbers, not real cards. Sales can select the same column, but decryption returns NULL, and trying to open the key gives "cannot find the symmetric key".
On the right is MFA. The user scans the QR code with Google Authenticator. After that, the password alone is not enough: the app asks for the six-digit code. A wrong code is rejected and counts towards the lockout.`, 0.75);
  await imgFit(s, SHOT("sql/sql_06_column_encryption.png"), 0.6, 1.45, 6.6, 3.0, "Card numbers: authorized vs unauthorized", false);
  text(s, "Admin (key permission) → real numbers · Sales (no key) → NULL", { x: 0.6, y: 4.65, w: 6.6, h: 0.45, fontSize: 15, bold: true, color: C.accent1 });
  text(s, "Test card numbers only (e.g. 4111 1111 1111 1111)", { x: 0.6, y: 5.1, w: 6.6, h: 0.4, fontSize: 14, italic: true, color: C.accent5 });
  const qr = await cropBox(SHOT("app/12_mfa_setup_qr.png"), path.join(IMG, "mfa_qr_crop.png"), 160, 360, 1110, 820);
  const prompt = await cropBox(SHOT("app/14_mfa_second_factor_prompt.png"), path.join(IMG, "mfa_prompt_crop.png"), 160, 170, 1060, 600);
  await imgFit(s, qr, 7.45, 1.45, 2.5, 3.3, "MFA QR code setup");
  await imgFit(s, prompt, 10.2, 1.45, 2.5, 3.3, "MFA second factor prompt");
  card(s, 7.45, 5.0, 5.25, 1.7, C.text2);
  text(s, "Password ✓ → 6-digit code required · wrong code rejected · secret stored encrypted (Fernet) in Users.MfaSecretEnc",
    { x: 7.65, y: 5.1, w: 4.9, h: 1.5, fontSize: 15, color: C.background1, valign: "middle" });

  s = newSlide("CONTENT", "Verified, not assumed",
    `To be sure that everything really works, and not only on my screen, I wrote an automated smoke test. It uses the running website like a browser and checks 37 security behaviours: injection, the shop's cart and checkout, lockout, row-level security, CSRF protection, the password policy, MFA, and what every staff member may or may not do in the staff portal. All 37 pass.
All eight SQL scripts can be re-run safely and rebuild everything from zero in about ten seconds. All ten risks from my checklist are mapped to a control. And there is no password in any source file: everything is in the .env file, which is never committed.`, 1);
  const st2 = [["37/37", "end-to-end security checks pass (smoke_test.py)", C.accent1], ["8", "SQL scripts · re-runnable · full rebuild ≈ 10 s", C.accent4],
    ["10/10", "risks from the checklist mapped to a control", C.accent3], ["0", "passwords or keys in the source code", C.accent2]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + (i % 2) * 6.15, y = 1.5 + Math.floor(i / 2) * 2.6;
    card(s, x, y, 5.95, 2.3, C.background2);
    text(s, st2[i][0], { x: x + 0.35, y: y + 0.3, w: 5.3, h: 1.1, fontSize: 60, bold: true, color: st2[i][2] });
    text(s, st2[i][1], { x: x + 0.35, y: y + 1.45, w: 5.3, h: 0.6, fontSize: 17, color: C.text1 });
  }

  // ======================= PART 5: CONCLUSION ============================
  section("5 · Conclusion & feedback");
  s = newSlide("CONTENT", "Conclusion: no single control is enough, so I built layers",
    `My conclusion: database security is not one feature, it is layers. If one layer fails, the next one still protects the data.
The network layer: the app only listens on this computer and uses an encrypted connection. Authentication: strong passwords, lockout and MFA. Authorization: roles, row-level rules and masking. Query hardening: stored procedures and parameters. Data protection: TDE, column encryption and classification. And monitoring: the audit log records everything.
I also want to be honest about the limits. SQL Server has no feature called ABAC, so I built it from row-level security and attributes. SQL logins have no MFA, so MFA lives in the app. In production I would hash passwords with bcrypt or Argon2, and use Always Encrypted so that even the DBA cannot read card numbers.`, 2);
  const layers = [["Network", "127.0.0.1 only · TLS", C.accent5], ["Authentication", "policy · lockout · MFA", C.accent4],
    ["Authorization", "RBAC · RLS (ABAC) · masking", C.accent6], ["Query hardening", "procedures · parameters · validation", C.accent1],
    ["Data protection", "TDE · column encryption · labels", C.accent3], ["Monitoring", "append-only audit log", C.text2]];
  for (let i = 0; i < 6; i++) {
    const inset = i * 0.3;
    const y = 1.45 + i * 0.85;
    box(s, layers[i][0] + "  ·  " + layers[i][1], 0.6 + inset, y, 7.0 - 2 * inset, 0.72, layers[i][2],
      i === 4 ? C.text1 : C.background1, { fontSize: 15 });
  }
  card(s, 8.0, 1.45, 4.7, 5.2, C.background2);
  text(s, "Honest limits → next steps", { x: 8.25, y: 1.6, w: 4.3, h: 0.45, fontSize: 19, bold: true, color: C.text2 });
  s.addText(["No native ABAC → built with RLS + attributes", "No MFA for SQL logins → TOTP in the app",
    "T-SQL slow hash → bcrypt / Argon2 in production", "Cell encryption ≠ hidden from sysadmin → Always Encrypted",
    "Audit table → add SQL Server Audit + alerts (SIEM)"].map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < 4 } })),
    { isTextBox: true, x: 8.25, y: 2.2, w: 4.3, h: 4.3, fontSize: 15, color: C.text1, margin: 0, paraSpaceAfter: 10, valign: "top" });

  s = newSlide("CONTENT", "Peer feedback: help me improve",
    `Before the questions, I would like your feedback, because a security design gets better when other people try to break it.
Here are three questions for you. Which layer would you attack first, and how? Was any part of the demo unclear? And what would you add before this shop could go live?
Please also tell me one thing that worked well, so I know what to keep.`, 2);
  const fq = [["FaUserSecret", "Which layer would YOU attack first, and how?"], ["FaQuestionCircle", "Which part of the demo was unclear?"],
    ["FaRocket", "What must be added before ShopDB goes live?"], ["FaThumbsUp", "One thing that worked well"]];
  for (let i = 0; i < 4; i++) {
    const x = 0.6 + (i % 2) * 6.15, y = 1.6 + Math.floor(i / 2) * 2.5;
    card(s, x, y, 5.95, 2.2, i === 3 ? "E3F4F2" : C.background2);
    await badge(s, fq[i][0], x + 0.35, y + 0.6, 1.0, i === 3 ? C.accent1 : C.accent4);
    text(s, fq[i][1], { x: x + 1.65, y: y + 0.35, w: 4.05, h: 1.5, fontSize: 20, bold: true, color: C.text2, valign: "middle" });
  }

  // ======================= PART 6: Q&A ===================================
  section("6 · Q&A");
  s = newSlide("SECTION", "Questions?",
    `Thank you for listening. I am happy to answer your questions now. All the scripts, the app, the screenshots and the README are in my project folder if you want to try it yourself.`, 5);
  s.addText("Thank you · scripts, app, screenshots and README are in the project folder", { placeholder: "body" });
  await badge(s, "FaQuestionCircle", 0.9, 2.75, 1.3, C.accent3, HEX.dk2);

  // --------------------------------------------------------------------------
  const out = path.join(__dirname, "DB_Security_Ecommerce.pptx");
  await pres.writeFile({ fileName: out });
  // Writes THEME's colours into the file (pptxgenjs can't). Optional helper:
  // set PPTX_SKILL to the folder that contains scripts/apply_theme.js.
  if (process.env.PPTX_SKILL) {
    const { applyTheme } = require(process.env.PPTX_SKILL + "/scripts/apply_theme.js");
    await applyTheme(out, THEME);
  } else console.warn("PPTX_SKILL not set: theme colours not applied (Office default palette).");
  console.log("wrote", out, "slides:", NOTES.length);

  // ---- docs/speaker_notes.md (generated from the same notes) -------------
  const total = NOTES.reduce((a, n) => a + n.minutes, 0);
  let md = fs.readFileSync(path.join(__dirname, "speaker_notes_header.md"), "utf8")
    .replace("{{TOTAL}}", total.toFixed(1));
  let sec = "";
  for (const n of NOTES) {
    if (n.section !== sec) { sec = n.section; md += `\n## ${sec}\n`; }
    md += `\n### Slide ${n.n}: ${n.title}  _(≈ ${n.minutes} min)_\n\n${n.notes.split("\n").join("\n\n")}\n`;
  }
  fs.writeFileSync(path.join(ROOT, "docs", "speaker_notes.md"), md);
  console.log("wrote docs/speaker_notes.md, total minutes:", total);
})().catch((e) => { console.error(e); process.exit(1); });
