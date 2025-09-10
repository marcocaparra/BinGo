from fastapi import FastAPI
from database import engine 
from models import user_model, material_type_model, discard_model, unique_code_model 
from routers import users
from routers import material_types
from routers import unique_codes
from routers import device_integration
from routers import discards

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
app.include_router(unique_codes.router)
app.include_router(device_integration.router)
app.include_router(discards.router)

@app.get("/")
def read_root():
    return {"message": "Bem-vindo à API do BinGo!"}