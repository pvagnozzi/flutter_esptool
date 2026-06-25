# Security Policy

## Supported Versions

The following versions of `flutter_esptool` currently receive security updates:

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | ✅ Yes             |
| < 0.1.0 | ❌ No              |

We track the latest stable release on the `main` branch.  Only the most recent
minor release series receives security patches.  Older releases may be
patched on a case-by-case basis for critical vulnerabilities.

---

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, use **GitHub Security Advisories** to report a vulnerability
privately:

1. Go to the repository on GitHub:
   <https://github.com/pvagnozzi/flutter_esptool>
2. Click the **Security** tab.
3. Click **Report a vulnerability** (under *Advisories*).
4. Fill in the advisory form with:
   - A description of the vulnerability and its potential impact.
   - Steps to reproduce or a proof-of-concept.
   - The affected version(s).
   - Any suggested mitigations (optional).

### What to expect

| Timeline | Action |
|----------|--------|
| Within **3 business days** | Acknowledgement of the report |
| Within **14 days** | Initial assessment and severity classification |
| Within **90 days** | Patch release (or coordinated disclosure if a fix is not yet available) |

We follow the principle of **coordinated disclosure**: we will work with you
to understand the impact, develop a fix, and agree on a disclosure timeline
before any public announcement.

### Scope

This package implements the Espressif ROM/stub serial bootloader protocol.
Security-relevant areas include:

- Parsing of untrusted binary data (flash images, partition tables, SLIP frames).
- Serial transport (authentication is outside the scope of this library).
- Dependency vulnerabilities in `platform_serial` or transitive packages.

### Out of scope

- Vulnerabilities in the Espressif ROM bootloader firmware itself.
- Physical access attacks on the target device.
- Issues already publicly known via the issue tracker.

---

## Security Contact

If the GitHub Security Advisories form is unavailable, you may contact the
maintainer directly via the e-mail address listed in the `pubspec.yaml`
`homepage` field.
