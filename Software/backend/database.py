import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from base_class import Base

import models 

DATABASE_PORT = os.getenv("DATABASE_PORT", "3306")
DATABASE_USER = os.getenv("MYSQL_USER", "bingo_user")
DATABASE_PASSWORD = os.getenv("MYSQL_PASSWORD", "Bingolino53787")
DATABASE_NAME = os.getenv("MYSQL_DATABASE", "bingo_db")

DOCKER_DATABASE_HOST = os.getenv("DOCKER_DATABASE_HOST", "db")
DOCKER_SQLALCHEMY_DATABASE_URL = (
    f"mysql+pymysql://{DATABASE_USER}:{DATABASE_PASSWORD}@"
    f"{DOCKER_DATABASE_HOST}:{DATABASE_PORT}/{DATABASE_NAME}"
)

HOST_DATABASE_HOST = os.getenv("HOST_DATABASE_HOST", "localhost")
HOST_SQLALCHEMY_DATABASE_URL = (
    f"mysql+pymysql://{DATABASE_USER}:{DATABASE_PASSWORD}@"
    f"{HOST_DATABASE_HOST}:{DATABASE_PORT}/{DATABASE_NAME}"
)

engine = create_engine(DOCKER_SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()