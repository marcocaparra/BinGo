from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from datetime import timedelta
from typing import Annotated
from fastapi.security import OAuth2PasswordRequestForm
from typing import List, Optional

from database import get_db
from models.user_model import User
from schemas.user_schema import UserCreate, UserResponse, UserLogin, Token
from schemas.ranking_schema import UserRanking
from auth import verify_password, create_access_token, get_password_hash, ACCESS_TOKEN_EXPIRE_MINUTES, get_current_user

router = APIRouter(
    prefix='/users',
    tags=['Users'],
    responses={404: {'description': 'Not found'}},
)

@router.post('/', response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(User).filter((User.username == user.username) | (User.email == user.email)).first()
    if db_user:
        if db_user.username == user.username:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Username already registered')
        elif db_user.email == user.email:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Email already registered')
    
    hashed_password = get_password_hash(user.password)

    db_user = User(
        username=user.username,
        email=user.email,
        hashed_password=hashed_password,
        name=user.name,
        cpf=user.cpf,
        phone_number=user.phone_number,
        total_points=user.total_points
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@router.post("/token", response_model=Token)
async def login_for_access_token(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.username == form_data.username).first()

    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Nome de usuário ou senha incorretos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.get('/me/', response_model=UserResponse)
async def read_users_me(current_user: Annotated[User, Depends(get_current_user)]):
    return current_user

@router.get(
    "/ranking",
    response_model=List[UserRanking],
    summary="Obter o ranking global de usuários por pontos",
    description="Retorna uma lista de usuários ordenada pelos pontos totais (total_points) em ordem decrescente."
)
def get_user_ranking(
    db: Session = Depends(get_db),
    limit: int = Query(100, ge=1, le=500, description="Número máximo de usuários a retornar no ranking."),
):
    """
    Retrieves a global ranking of users based on their total_points.
    The list is ordered in descending order of points.
    """
    ranking = db.query(User).order_by(User.total_points.desc()).limit(limit).all()

    return ranking
