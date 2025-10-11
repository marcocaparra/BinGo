from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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

origins = [
    "http://localhost:5173",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"], 
)

# --- Inclusão dos Routers ---
app.include_router(users.router)
app.include_router(material_types.router)
app.include_router(unique_codes.router)
app.include_router(device_integration.router)
app.include_router(discards.router)
app.include_router(mission.router, tags=["Missions"])
app.include_router(achievements.router)

@app.get("/")
def read_root():
    return {"message": "Bem-vindo à API do BinGo!"}