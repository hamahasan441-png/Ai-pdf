"""Audit Logging - Tracks all important user actions.

Engineering Decision:
  Audit logging is critical for:
  1. Security (detecting unauthorized access)
  2. Debugging (tracing user issues)
  3. Analytics (understanding usage patterns)
  4. Compliance (GDPR, data access records)

  We log: who, what, when, where, result.
  Sensitive data (passwords, tokens) is NEVER logged.

  Future: Stream to external service (Elasticsearch, CloudWatch).
"""

import logging
import time
from typing import Any, Optional

logger = logging.getLogger("audit")


class AuditLogger:
    """Structured audit logging for security and analytics."""

    def log(
        self,
        action: str,
        user_id: Optional[str] = None,
        resource: Optional[str] = None,
        resource_id: Optional[str] = None,
        details: Optional[dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        success: bool = True,
    ) -> None:
        """Log an auditable action.

        Args:
            action: What happened (login, upload, analyze, export, delete)
            user_id: Who did it
            resource: What type (document, profile, auth)
            resource_id: Which specific resource
            details: Additional context (never sensitive data)
            ip_address: Where from
            success: Did it succeed
        """
        entry = {
            "timestamp": time.time(),
            "action": action,
            "user_id": user_id,
            "resource": resource,
            "resource_id": resource_id,
            "ip": ip_address,
            "success": success,
        }
        if details:
            # Never log sensitive fields
            safe_details = {
                k: v for k, v in details.items()
                if k not in ("password", "token", "api_key", "secret", "ssn")
            }
            entry["details"] = safe_details

        if success:
            logger.info(f"AUDIT: {action} | user={user_id} | {resource}:{resource_id}")
        else:
            logger.warning(f"AUDIT FAIL: {action} | user={user_id} | {resource}:{resource_id}")

    def log_login(self, user_id: str, ip: str, success: bool) -> None:
        self.log("login", user_id=user_id, resource="auth", ip_address=ip, success=success)

    def log_upload(self, user_id: str, doc_id: str, filename: str) -> None:
        self.log("upload", user_id=user_id, resource="document", resource_id=doc_id, details={"filename": filename})

    def log_analyze(self, user_id: str, doc_id: str, stages: int, time_ms: int) -> None:
        self.log("analyze", user_id=user_id, resource="document", resource_id=doc_id, details={"stages": stages, "time_ms": time_ms})

    def log_export(self, user_id: str, doc_id: str, format: str) -> None:
        self.log("export", user_id=user_id, resource="document", resource_id=doc_id, details={"format": format})

    def log_delete(self, user_id: str, doc_id: str) -> None:
        self.log("delete", user_id=user_id, resource="document", resource_id=doc_id)

    def log_profile_access(self, user_id: str, action: str) -> None:
        self.log(f"profile_{action}", user_id=user_id, resource="profile")


# Singleton
audit = AuditLogger()
