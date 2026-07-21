"""API v1 router combining all endpoint routers."""

from fastapi import APIRouter

from app.api.v1.ai import router as ai_router
from app.api.v1.auth import router as auth_router
from app.api.v1.billing import router as billing_router
from app.api.v1.convert import router as convert_router
from app.api.v1.document_ai import router as document_ai_router
from app.api.v1.documents import router as documents_router
from app.api.v1.forms import router as forms_router
from app.api.v1.profile import router as profile_router

api_router = APIRouter()

api_router.include_router(auth_router, prefix="/auth", tags=["Authentication"])
api_router.include_router(profile_router, prefix="/profile", tags=["Profile"])
api_router.include_router(documents_router, prefix="/documents", tags=["Documents"])
api_router.include_router(ai_router, prefix="/ai", tags=["Managed AI"])
api_router.include_router(document_ai_router, tags=["Document AI"])
api_router.include_router(forms_router, tags=["Forms"])
api_router.include_router(billing_router, prefix="/billing", tags=["Billing"])
api_router.include_router(convert_router, prefix="/convert", tags=["Convert"])
