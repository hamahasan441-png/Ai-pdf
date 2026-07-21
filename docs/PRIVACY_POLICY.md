# AI PDF — Privacy Policy

**Last updated:** July 2026

## Summary

AI PDF is a privacy-first mobile PDF editor. Your documents stay on your device
unless you explicitly choose to use the cloud AI features. We collect the
minimum data necessary to operate the service.

---

## 1. Data We Do NOT Collect

- **Document content** — your PDFs are processed entirely on-device. No document
  text, images, or metadata are sent to our servers unless you explicitly use a
  managed AI feature (chat, summarize, translate, etc.).
- **Location data** — we never request or store location.
- **Contacts, camera, microphone** — not accessed.
- **Advertising identifiers** — we do not use tracking SDKs.

## 2. Data We Collect

| Data | When | Purpose | Retention |
|------|------|---------|-----------|
| Email + hashed password | Account registration (optional) | Authentication | Until account deletion |
| AI request text | When you use cloud AI features | Process the AI request | Request lifecycle only (not stored) |
| Purchase token | In-app purchase verification | Validate Pro entitlement | Until subscription expires or account deletion |
| Crash reports | App crash (opt-in) | Fix bugs | 90 days |
| Anonymous usage events | App open, feature use (opt-in) | Improve the product | 12 months, aggregated |

## 3. On-Device Processing

The following features work **entirely offline** with zero network access:

- PDF viewing, editing, and annotation
- On-device OCR (ML Kit, on-device model)
- On-device document Q&A (BM25 retrieval)
- Form field detection and auto-fill from your local profile
- PDF conversion (Word, Excel, PowerPoint)
- Compression, split, merge, rotate

## 4. Cloud AI Features (Opt-in)

When you use managed AI features (chat with document, summarize, translate,
rewrite, extract data, suggest edits), the relevant text excerpt is sent to our
backend which forwards it to a third-party AI provider (OpenRouter). We:

- Do NOT store your document text after the request completes.
- Do NOT use your data to train AI models.
- Do NOT share your data with advertisers.

The AI provider's data handling is governed by their privacy policy. We select
providers that commit to not training on user data.

## 5. User Profile (Encrypted)

Your form auto-fill profile (name, address, etc.) is:
- Stored **locally on your device** encrypted with AES-256 (Fernet).
- Never transmitted to our servers.
- Used only to pre-fill form fields when you choose "Auto Fill".

## 6. Third-Party Services

| Service | Purpose | Data shared |
|---------|---------|-------------|
| Google Play Billing | In-app purchases | Purchase token (verified server-side) |
| Google ML Kit (on-device) | OCR text recognition | None (runs locally) |
| OpenRouter (AI provider) | Cloud AI features | Document text excerpts (per-request) |
| Sentry (optional) | Crash reporting | Stack traces, device info (no document content) |

## 7. Data Retention & Deletion

- **Account deletion:** email us or use the in-app "Delete Account" option.
  All server-side data (account, entitlements, chat history) is permanently
  deleted within 30 days.
- **Chat history:** stored server-side for conversation resumption. Automatically
  deleted after 90 days of inactivity, or immediately via the app.
- **Crash reports:** auto-deleted after 90 days.

## 8. Children's Privacy

AI PDF is not directed at children under 13. We do not knowingly collect data
from children.

## 9. Changes to This Policy

We will update this page when the policy changes. Material changes are
communicated via an in-app notice.

## 10. Contact

For privacy questions: privacy@aidocassistant.com
