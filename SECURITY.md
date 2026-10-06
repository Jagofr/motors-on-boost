# Security Policy

## Supported Versions

Because **M.O.B. (Motors on Boost)** is an actively developed prototype, security patches and stability updates are applied exclusively to the latest build on the primary branch.

| Version / Branch | Supported | Notes |
|---|---|---|
| `main` / `master` | :white_check_mark: | Latest WebGL & PWA build |
| Previous Tags / Releases | :x: | Archived milestones (unsupported) |

---

## Web Security & Sandboxing

**M.O.B.** runs natively in the browser client sandbox. Key architectural considerations:

1. **Service Worker (`sw.js`)**: All offline caching is constrained to the application's origin scope (`./`).
2. **Local Storage (`SaveSystem.hx`)**: Settings and race checkpoints are serialized directly into browser `LocalStorage`. No sensitive user credentials or personally identifiable information (PII) are ever gathered or transmitted.
3. **Web Audio & Gamepad APIs**: The engine polls standard W3C browser APIs and does not run native native binaries, WebAssembly escape vectors, or third-party tracking analytics.

---

## Reporting a Vulnerability

If you discover a security vulnerability, cross-site scripting (XSS) vulnerability in the web wrapper, service worker cache poisoning issue, or malicious injection flaw:

1. **Do NOT open a public GitHub issue.**
2. Send an email to the lead developer and security contact:
   * **Contact:** `jamiefrancis.rvl@gmail.com` (or via official RvL // ROGUE channels)
   * **Subject Line:** `[SECURITY] M.O.B. Vulnerability Report`
3. Please include:
   * Detailed steps to reproduce the vulnerability.
   * Target browser, version, and operating system.
   * Proof of concept (PoC) code or script if applicable.

We will acknowledge receipt within 48 hours and work on remediation prior to public disclosure.