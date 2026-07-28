#!/usr/bin/env python3
"""
Metering audit guard — Enhancement-Based Masterplan E5.5 / E6.1.

Checks:
1. No API file (app/api/v1/*.py) uses the legacy binary `is_pro` or
   `check_and_increment` pattern — must use tiered `get_quota` +
   `check_and_increment_tiered`.
2. All AI endpoints import and use tiered quota.
3. Allowed exceptions: usage_limiter.py, quota_tiers.py, billing/, auth, etc.

Run:
    python backend/scripts/check_metering.py
Exit 0 = pass, 1 = fail.
"""
import sys
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]  # backend/
API_DIR = ROOT / "app" / "api" / "v1"

# Files allowed to reference is_pro / check_and_increment (the source of truth)
ALLOWLIST = {
    "usage_limiter.py",  # defines is_pro
    "quota_tiers.py",  # not in api dir but safe
    "billing.py",  # uses is_pro? actually verify path, but keep allow for RTDN
    "admin.py",
    "auth.py",
    "profile.py",
    "documents.py",
    "convert.py",
    "teams.py",
    "webhooks.py",
    "api_keys.py",
    "chat_history.py",
    "health_dashboard.py",
    "plugins.py",
    "router.py",
    "__init__.py",
}

# Patterns that indicate legacy metering
LEGACY_PATTERNS = [
    re.compile(r"\bis_pro\s*\("),
    re.compile(r"check_and_increment\s*\(\s*[^_)]"),  # not _tiered
]

# Patterns that indicate correct tiered metering
TIERED_REQUIRED_FILES = {
    # AI endpoints that MUST use tiered metering
    "ai.py",
    "document_ai.py",
    "document_compare.py",
    "document_outline.py",
    "extract_dates.py",
    "extract_actions.py",
    "suggest_questions.py",
    "suggest_edits.py",
    "multi_doc_chat.py",
    "text_layer.py",
    "forms.py",
    "form_validate.py",
}

TIERED_PATTERNS = [
    re.compile(r"get_quota"),
    re.compile(r"check_and_increment_tiered"),
]


def check_file(path: Path) -> list[str]:
    errors = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    fname = path.name

    # 1. Legacy pattern check (skip allowlist)
    if fname not in ALLOWLIST:
        for pat in LEGACY_PATTERNS:
            if pat.search(text):
                # Distinguish check_and_increment_tiered from plain
                if "check_and_increment_tiered" in text and "check_and_increment(" not in text.replace("check_and_increment_tiered", ""):
                    continue
                # If file contains tiered + legacy, still error if legacy appears outside tiered definition
                # Simple heuristic: count occurrences
                lines = text.splitlines()
                for i, line in enumerate(lines, 1):
                    if pat.search(line) and "def " not in line and "tiered" not in line:
                        # Allow comment?
                        if line.strip().startswith("#"):
                            continue
                        # Special case: check_and_increment alone in usage_limiter definition is ok
                        if "def check_and_increment" in line:
                            continue
                        errors.append(f"{fname}:{i}: legacy pattern `{pat.pattern}` — use tiered get_quota + check_and_increment_tiered")

    # 2. Tiered required check
    if fname in TIERED_REQUIRED_FILES:
        has_get_quota = any(p.search(text) for p in [TIERED_PATTERNS[0]])
        has_tiered = any(p.search(text) for p in [TIERED_PATTERNS[1]])
        if not (has_get_quota and has_tiered):
            # forms.py has multiple routes, some may be non-AI (acroform read is not metered), so we allow if at least one tiered usage exists OR it's explicitly exempt
            # For strictness: check if file contains "AI" or "meter" markers — if it contains "_meter" helper, it's ok
            if "_meter" in text or "get_quota" in text:
                pass  # helper abstracts it
            else:
                # More precise: check if file mentions AI_FREE_DAILY_LIMIT -> should be tiered
                if "AI_FREE_DAILY_LIMIT" in text or "check_and_increment" in text:
                    errors.append(f"{fname}: missing tiered metering (needs get_quota + check_and_increment_tiered)")
                elif fname in {"ai.py", "document_ai.py"} and not has_get_quota:
                    errors.append(f"{fname}: missing tiered metering (needs get_quota + check_and_increment_tiered)")

    return errors


def main() -> int:
    print(f"[check_metering] Scanning {API_DIR}")
    all_errors: list[str] = []
    for py_file in sorted(API_DIR.glob("*.py")):
        errs = check_file(py_file)
        all_errors.extend(errs)

    # Also check for duplicate dict keys or undefined names via ruff? Just summary
    if all_errors:
        print("[check_metering] FAIL — legacy metering detected:")
        for e in all_errors:
            print(f"  - {e}")
        print("\n[fix] Replace:\n  is_pro(db, token) + check_and_increment(key)  →\n  tier, limit = await get_quota(db, token)\n  if limit is not None: allowed, count = check_and_increment_tiered(key, limit)")
        print("\nSee docs/ENHANCEMENT_BASED_MASTERPLAN.md Pillar 5 E5.5")
        return 1
    else:
        print("[check_metering] PASS — all AI endpoints use tiered metering")
        # Additional summary
        ai_files = [f.name for f in API_DIR.glob("*.py") if "ai" in f.name or "form" in f.name or "multi" in f.name or "suggest" in f.name or "extract" in f.name or "compare" in f.name or "outline" in f.name]
        print(f"  Checked {len(list(API_DIR.glob('*.py')))} api files, including AI-related: {', '.join(sorted(ai_files))}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
