from fastapi import APIRouter

from app.api.routes import admin, auth, deposits, machines, me, redemptions, rewards

router = APIRouter()
router.include_router(auth.router, prefix="/auth", tags=["auth"])
router.include_router(me.router, prefix="/me", tags=["me"])
router.include_router(rewards.router, prefix="/rewards", tags=["rewards"])
router.include_router(redemptions.router, prefix="/redemptions", tags=["redemptions"])
router.include_router(deposits.router, prefix="/deposits", tags=["deposits"])
router.include_router(machines.router, prefix="/machines", tags=["machines"])
router.include_router(admin.router, prefix="/admin", tags=["admin"])

