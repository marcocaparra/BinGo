from fastapi import FastAPI
from backend.routers import users
from backend.database import Base, engine

from backend.models import user_model, material_type_model, discard_model

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title='BinGo Backend',
    description='API para a plataforma de reciclagem gamificada',
    version='0.0.1',
)

app.include_router(users.router)

@app.get('/')
def read_root():
    return {"message": "Bem-vindo ao Backend do Projeto BinGo! Acesse /docs para a documentação da API."}