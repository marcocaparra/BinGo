from fastapi import FastAPI
from backend.database import engine 
from backend.models import user_model, material_type_model, discard_model, unique_code_model 
from backend.routers import users
from backend.routers import material_types

user_model.Base.metadata.create_all(bind=engine)
material_type_model.Base.metadata.create_all(bind=engine)
discard_model.Base.metadata.create_all(bind=engine)
unique_code_model.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="BinGo API",
    description="API para o sistema de reciclagem BinGo",
    version="0.0.1"
)   

app.include_router(users.router)
app.include_router(material_types.router)

@app.get("/")
def read_root():
    return {"message": "Bem-vindo à API do BinGo!"}