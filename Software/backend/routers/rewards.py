from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import random
import string

from database import get_db
from models.reward_model import Reward
from models.user_model import User
from schemas.reward_schema import RewardResponse, RedeemResponse
from auth import get_current_user

router = APIRouter(prefix="/rewards", tags=["Rewards"])

# --- CORREÇÃO APLICADA AQUI ---
# Trocamos @router.get("/") por @router.get("")
# Isso faz com que a rota responda diretamente em /rewards
@router.get("", response_model=List[RewardResponse])
def get_all_rewards(db: Session = Depends(get_db)):
    """ Retorna uma lista de todas as recompensas disponíveis. """
    return db.query(Reward).all()

@router.post("/{reward_id}/redeem", response_model=RedeemResponse)
def redeem_reward(
    reward_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # ... (o resto da função continua igual)
    reward = db.query(Reward).filter(Reward.id == reward_id).first()
    if not reward:
        raise HTTPException(status_code=404, detail="Recompensa não encontrada.")

    if current_user.total_points < reward.cost:
        raise HTTPException(status_code=400, detail="Pontos insuficientes para resgatar esta recompensa.")

    current_user.total_points -= reward.cost
    
    redemption_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
    
    db.commit()
    db.refresh(current_user)

    return RedeemResponse(
        message="Recompensa resgatada com sucesso!",
        new_total_points=current_user.total_points,
        redemption_code=redemption_code
    )