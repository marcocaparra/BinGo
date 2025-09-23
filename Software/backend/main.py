from fastapi import FastAPI
from database import engine 
from base_class import Base 

from routers import users
from routers import material_types
from routers import unique_codes
from routers import device_integration
from routers import discards
from routers import mission
from routers import achievements

Base.metadata.create_all(bind=engine)

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
app.include_router(mission.router, tags=["Missions"])
app.include_router(achievements.router)

import os
from dotenv import load_dotenv

load_dotenv()
# ...
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# ...

@app.get("/")
def read_root():
    return {"message": "Bem-vindo à API do BinGo!"}