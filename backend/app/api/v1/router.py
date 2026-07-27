"""API v1 router combining all endpoint routers."""

from fastapi import APIRouter

from app.api.v1.admin import router as admin_router
from app.api.v1.ai import router as ai_router
from app.api.v1.api_keys import router as api_keys_router
from app.api.v1.auth import router as auth_router
from app.api.v1.billing import router as billing_router
from app.api.v1.chat_history import router as chat_history_router
from app.api.v1.health_dashboard import router as health_dashboard_router
from app.api.v1.convert import router as convert_router
from app.api.v1.plugins import router as plugins_router
from app.api.v1.teams import router as teams_router
from app.api.v1.document_ai import router as document_ai_router
from app.api.v1.document_compare import router as document_compare_router
from app.api.v1.document_outline import router as document_outline_router
from app.api.v1.documents import router as documents_router
from app.api.v1.extract_actions import router as extract_actions_router
from app.api.v1.extract_dates import router as extract_dates_router
from app.api.v1.form_validate import router as form_validate_router
from app.api.v1.forms import router as forms_router
from app.api.v1.multi_doc_chat import router as multi_doc_router
from app.api.v1.profile import router as profile_router
from app.api.v1.suggest_edits import router as suggest_edits_router
from app.api.v1.suggest_questions import router as suggest_questions_router
from app.api.v1.text_layer import router as text_layer_router
from app.api.v1.webhooks import router as webhooks_router

from app.api.v1.sso import router as sso_router
from app.api.v1.sync import router as sync_router
from app.api.v1.collab import router as collab_router
from app.api.v1.redact import router as redact_router
from app.api.v1.vision_forms import router as vision_forms_router
from app.api.v1.paywall_analytics import router as paywall_analytics_router

api_router = APIRouter()

api_router.include_router(auth_router, prefix="/auth", tags=["Authentication"])
api_router.include_router(sso_router, tags=["SSO"])
api_router.include_router(sync_router, tags=["Sync"])
api_router.include_router(collab_router, tags=["Collaboration"])
api_router.include_router(redact_router, tags=["Document AI"])
api_router.include_router(vision_forms_router, tags=["Forms"])
api_router.include_router(paywall_analytics_router, tags=["Billing"])
api_router.include_router(profile_router, prefix="/profile", tags=["Profile"])
api_router.include_router(documents_router, prefix="/documents", tags=["Documents"])
api_router.include_router(ai_router, prefix="/ai", tags=["Managed AI"])
api_router.include_router(document_ai_router, tags=["Document AI"])
api_router.include_router(document_compare_router, tags=["Document AI"])
api_router.include_router(forms_router, tags=["Forms"])
api_router.include_router(form_validate_router, tags=["Forms"])
api_router.include_router(document_outline_router, tags=["Document AI"])
api_router.include_router(suggest_questions_router, tags=["Document AI"])
api_router.include_router(suggest_edits_router, tags=["Document AI"])
api_router.include_router(multi_doc_router, tags=["Document AI"])
api_router.include_router(extract_dates_router, tags=["Document AI"])
api_router.include_router(extract_actions_router, tags=["Document AI"])
api_router.include_router(text_layer_router, tags=["Document AI"])
api_router.include_router(billing_router, prefix="/billing", tags=["Billing"])
api_router.include_router(convert_router, prefix="/convert", tags=["Convert"])
api_router.include_router(health_dashboard_router, tags=["System"])
api_router.include_router(plugins_router, tags=["Plugins"])
api_router.include_router(teams_router, prefix="/teams", tags=["Teams"])
api_router.include_router(admin_router, tags=["Admin"])
api_router.include_router(api_keys_router, tags=["API Keys"])
api_router.include_router(webhooks_router, tags=["Webhooks"])
api_router.include_router(chat_history_router, tags=["Chat History"])
