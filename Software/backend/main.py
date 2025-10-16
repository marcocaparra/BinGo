from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from database import engine
from base_class import Base

from routers import users
from routers import material_types
from routers import unique_codes
from routers import device_integration
from routers import discards
from routers import mission
from routers import achievements
from routers import rewards
from routers import activity

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="BinGo API",
    description="API para o sistema de reciclagem BinGo",
    version="0.0.1"
)

origins = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "https://*.github.dev",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_DIR = os.path.join(BASE_DIR, "public")
ASSETS_DIR = os.path.join(PUBLIC_DIR, "assets")
BADGES_DIR = os.path.join(ASSETS_DIR, "badges")

os.makedirs(BADGES_DIR, exist_ok=True)

app.mount("/assets", StaticFiles(directory=ASSETS_DIR), name="assets")

app.include_router(users.router)
app.include_router(material_types.router)
app.include_router(unique_codes.router)
app.include_router(device_integration.router)
app.include_router(discards.router)
app.include_router(mission.router, tags=["Missions"])
app.include_router(achievements.router)
app.include_router(rewards.router)
app.include_router(activity.router)

@app.get("/")
def read_root():
    return {"message": "Bem-vindo à API do BinGo!"}
