from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from ..database import get_db
from ..models.material_type_model import MaterialType
from ..schemas.material_type_schema import MaterialTypeCreate, MaterialTypeResponse

router = APIRouter(prefix="/material_types", tags=["Tipos de Materiais"])

@router.post("/", response_model=MaterialTypeResponse, status_code=status.HTTP_201_CREATED)
def create_material_type(
    material_type: MaterialTypeCreate,
    db: Session = Depends(get_db)
):

    db_material_type = db.query(MaterialType).filter(MaterialType.name == material_type.name).first()
    if db_material_type:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tipo de material com este nome já existe."
        )
    
    db_material_type = MaterialType(
        name=material_type.name,
        points_per_unit=material_type.points_per_unit
    )
    
    db.add(db_material_type)
    db.commit()
    db.refresh(db_material_type)
    return db_material_type

@router.get("/", response_model=List[MaterialTypeResponse])
def get_material_types(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):

    material_types = db.query(MaterialType).offset(skip).limit(limit).all()
    return material_types

@router.get("/{material_type_id}", response_model=MaterialTypeResponse)
def get_material_type(
    material_type_id: int,
    db: Session = Depends(get_db)
):

    material_type = db.query(MaterialType).filter(MaterialType.id == material_type_id).first()
    if material_type is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tipo de material não encontrado."
        )
    return material_type