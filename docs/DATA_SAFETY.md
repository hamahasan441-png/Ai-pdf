# AI PDF — Google Play Data Safety Declaration

> This document maps to the Play Console "Data safety" form fields. Use it as a
> reference when filling out the declaration.

---

## Overall Declarations

| Question | Answer |
|----------|--------|
| Does your app collect or share any user data? | Yes |
| Is all collected data encrypted in transit? | Yes (HTTPS) |
| Do you provide a way for users to request data deletion? | Yes |
| Have you committed to follow the Play Families policy? | N/A (not a kids app) |

---

## Data Types Collected

### Personal info
| Sub-type | Collected? | Shared? | Purpose | Optional? |
|----------|-----------|---------|---------|-----------|
| Email address | Yes | No | Account management | Yes (app works without account) |
| Name | No | — | — | — |

### Financial info
| Sub-type | Collected? | Shared? | Purpose | Optional? |
|----------|-----------|---------|---------|-----------|
| Purchase history | Yes (token only) | No | App functionality (Pro verification) | Yes |

### App activity
| Sub-type | Collected? | Shared? | Purpose | Optional? |
|----------|-----------|---------|---------|-----------|
| In-app actions | Yes | No | Analytics, product improvement | Yes (opt-in) |

### App info and performance
| Sub-type | Collected? | Shared? | Purpose | Optional? |
|----------|-----------|---------|---------|-----------|
| Crash logs | Yes | No | Bug fixing | Yes (opt-in) |
| Diagnostics | Yes | No | Performance monitoring | Yes (opt-in) |

---

## Data NOT Collected

- Location (fine, coarse, or approximate)
- Contacts
- Photos/videos (we don't access the gallery; user picks files via system picker)
- Audio
- Files (documents are processed on-device; only text excerpts are sent to AI when user initiates)
- Calendar
- SMS/call log
- Health/fitness
- Messages
- Web browsing
- Device identifiers (advertising ID)

---

## Data Sharing

We do NOT share any collected data with third parties for advertising,
marketing, or analytics purposes.

When users opt into cloud AI features, text excerpts are sent to the AI provider
(OpenRouter) for processing only. The provider does not retain the data.

---

## Security Practices

- All data in transit: TLS 1.2+
- Passwords: bcrypt hashed (never stored in plaintext)
- User profile (on-device): AES-256 encrypted (Fernet)
- API keys: SHA-256 hashed (never stored in cleartext)
- Webhook secrets: shown once, stored hashed server-side
- Server: no document content persisted beyond request lifecycle
