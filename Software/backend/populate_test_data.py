# backend/populate_test_data.py (CORRIGIDO)
import os
import sys
from pathlib import Path

import secrets
import string
from datetime import datetime, timedelta, UTC
import json

# --- Configuração do sys.path para encontrar os módulos ---
# Adiciona o diretório 'backend' (onde este script está) ao sys.path.
# Isso permite importações como 'from base_class import Base' e 'import models'.
current_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(current_dir)) 
# --- FIM: Configuração do sys.path ---

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# >>> Importações de Base, DOCKER_SQLALCHEMY_DATABASE_URL e dos Modelos
# Importa Base do módulo base_class
from base_class import Base 
# Importa DOCKER_SQLALCHEMY_DATABASE_URL de database
from database import DOCKER_SQLALCHEMY_DATABASE_URL

# Importa todos os modelos explicitamente ou através do pacote 'models'.
# Ao importar 'models', o __init__.py será executado, registrando todos os modelos.
import models
from models.user_model import User
from models.material_type_model import MaterialType
from models.mission_model import Mission, UserMission 
from models.unique_code_model import UniqueCode
from models.discard_model import Discard

script_engine = create_engine(DOCKER_SQLALCHEMY_DATABASE_URL)
ScriptSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=script_engine)

print("Configurando mappers do SQLAlchemy e verificando tabelas (pode levar alguns segundos)...")

with script_engine.connect() as connection:
    print("Desativando verificações de chave estrangeira temporariamente...")
    connection.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
    connection.commit()

    print("Deletando todas as tabelas existentes (se houver)...")
    Base.metadata.drop_all(bind=script_engine)
    print("Tabelas existentes deletadas.")

    print("Recriando todas as tabelas a partir dos modelos...")
    Base.metadata.create_all(bind=script_engine)
    print("Mappers configurados e tabelas verificadas.\n")

    print("Reativando verificações de chave estrangeira...\n")
    connection.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
    connection.commit()

# Seu bloco de diagnóstico permanece válido
from sqlalchemy.inspection import inspect
try:
    mapper = inspect(Mission)
    if 'user_missions' in mapper.relationships:
        print("DIAGNÓSTICO: Propriedade 'user_missions' ENCONTRADA na classe Mission (como relacionamento). ✅")
    else:
        print("DIAGNÓSTICO: ERRO - Propriedade 'user_missions' NÃO ENCONTRADA na classe Mission (como relacionamento). ❌")
except Exception as e:
    print(f"DIAGNÓSTICO: Ocorreu um erro ao inspecionar a classe Mission: {e} ⚠️")
    print("Isso pode indicar que a classe Mission não foi registrada corretamente ou há um problema maior.")
print("-" * 50)


def get_db_session():
    db = ScriptSessionLocal()
    try:
        return db
    except Exception as e:
        print(f"Erro ao obter sessão de banco de dados: {e}")
        raise
    
def create_test_data():
    db = get_db_session()

    try:
        print("Iniciando a criação/reset dos dados de teste...\n")

        test_user = db.query(User).filter(User.email == "testuser@example.com").first()
        if not test_user:
            test_user = User(
                email="testuser@example.com",
                username="testuser",
                hashed_password="somehashedpassword",
                total_points=0.0, # Ajustado para Float
                level=1, # Adicionado
                name="Test User",
                cpf="11122233344",
                phone_number="(11)98765-4321",
            )
            db.add(test_user)
            db.commit()
            db.refresh(test_user)
            print(f"Usuário de Teste criado: {test_user.email} (ID: {test_user.id})")
        else:
            test_user.total_points = 0.0 # Ajustado para Float
            test_user.level = 1 # Reset de nível
            db.add(test_user)
            db.commit()
            db.refresh(test_user)
            print(f"Usuário de Teste existente resetado: {test_user.email} (ID: {test_user.id})")

        material_electronic = db.query(MaterialType).filter(MaterialType.name == "Eletrônico").first()
        if not material_electronic:
            material_electronic = MaterialType(name="Eletrônico", points_per_unit=25.0)
            db.add(material_electronic)
            db.commit()
            db.refresh(material_electronic)
            print(f"Tipo de Material criado: Eletrônico (ID: {material_electronic.id})")
        else:
            material_electronic.points_per_unit = 25.0
            db.add(material_electronic)
            db.commit()
            db.refresh(material_electronic)
            print(f"Tipo de Material 'Eletrônico' existente (ID: {material_electronic.id})")

        material_plastic = db.query(MaterialType).filter(MaterialType.name == "Plástico").first()
        if not material_plastic:
            material_plastic = MaterialType(name="Plástico", points_per_unit=5.0)
            db.add(material_plastic)
            db.commit()
            db.refresh(material_plastic)
            print(f"Tipo de Material criado: Plástico (ID: {material_plastic.id})")
        else:
            material_plastic.points_per_unit = 5.0
            db.add(material_plastic)
            db.commit()
            db.refresh(material_plastic)
            print(f"Tipo de Material 'Plástico' existente (ID: {material_plastic.id})")
            
        mission_total = db.query(Mission).filter(Mission.name == "Descarte Total (3 itens)").first()
        if not mission_total:
            mission_total = Mission(
                name="Descarte Total (3 itens)",
                description="Descarte 3 itens de qualquer tipo para ganhar pontos extras.",
                objective=json.dumps({"action_type": "discard"}), # Ajustado para compatibilidade com lógica de router
                reward_points=100,
                type="discard_count",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30),
                target_quantity=3 # ADICIONADO: Campo para meta da missão
            )
            db.add(mission_total)
            db.commit()
            db.refresh(mission_total)
            print(f"Missão criada: '{mission_total.name}' (ID: {mission_total.id})\n")

        mission_electronic = db.query(Mission).filter(Mission.name == "Eletrônico Mestre (2x)").first()
        if not mission_electronic:
            mission_electronic = Mission(
                name="Eletrônico Mestre (2x)",
                description="Descarte 2 itens eletrônicos para provar seu domínio.",
                objective=json.dumps({"action_type": "discard", "material_type_id": material_electronic.id}), # Ajustado
                reward_points=150,
                type="discard_specific_material",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30),
                target_quantity=2
            )
            db.add(mission_electronic)
            db.commit()
            db.refresh(mission_electronic)
            print(f"Missão criada: '{mission_electronic.name}' (ID: {mission_electronic.id})\n")

        mission_plastic = db.query(Mission).filter(Mission.name == "Plástico Consciente (2x)").first()
        if not mission_plastic:
            mission_plastic = Mission(
                name="Plástico Consciente (2x)",
                description="Descarte 2 itens plásticos para um futuro mais verde.",
                objective=json.dumps({"action_type": "discard", "material_type_id": material_plastic.id}), # Ajustado
                reward_points=75,
                type="discard_specific_material",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30),
                target_quantity=2
            )
            db.add(mission_plastic)
            db.commit()
            db.refresh(mission_plastic)
            print(f"Missão criada: '{mission_plastic.name}' (ID: {mission_plastic.id})\n")

        mission_points = db.query(Mission).filter(Mission.name == "Acumulador de Pontos (50)").first()
        if not mission_points:
            mission_points = Mission(
                name="Acumulador de Pontos (50)",
                description="Acumule 50 pontos de descarte para uma grande recompensa.",
                objective=json.dumps({"action_type": "accumulate_points", "points_target": 50}),
                reward_points=200,
                type="accumulate_points",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30),
                target_quantity=50
            )
            db.add(mission_points)
            db.commit()
            db.refresh(mission_points)
            print(f"Missão criada: '{mission_points.name}' (ID: {mission_points.id})\n")

        user_missions_to_assign = [mission_total, mission_electronic, mission_plastic, mission_points]
        for mission_item in user_missions_to_assign:
            user_mission_entry = db.query(UserMission).filter(
                UserMission.user_id == test_user.id,
                UserMission.mission_id == mission_item.id
            ).first()
            if not user_mission_entry:
                new_user_mission = UserMission(
                    user_id=test_user.id,
                    mission_id=mission_item.id,
                    status="Em Progresso",
                    progress=0
                )
                db.add(new_user_mission)
                db.commit()
                db.refresh(new_user_mission)
                print(f"Missão '{mission_item.name}' atribuída ao usuário de teste.")
            else:
                user_mission_entry.status = "Em Progresso"
                user_mission_entry.progress = 0
                user_mission_entry.completed_at = None
                db.add(user_mission_entry)
                db.commit()
                db.refresh(user_mission_entry)
                print(f"Missão de Usuário '{mission_item.name}' resetada para o usuário de teste.")

        db.query(UniqueCode).filter(UniqueCode.is_used == False).delete()
        db.commit()
        print("\nCódigos Únicos não utilizados limpos.\n")

        codes = {
            "electronic": [],
            "plastic": [],
            "any_material": []
        }

        def generate_random_code_and_add(db_session, length=6, material_type_id=None):
            characters = string.ascii_uppercase + string.digits
            
            while True:
                code_str = ''.join(secrets.choice(characters) for _ in range(length))
                existing_code = db_session.query(UniqueCode).filter(UniqueCode.code == code_str).first()
                if not existing_code:
                    break
            
            unique_code_obj = UniqueCode(code=code_str, is_used=False, material_type_id=material_type_id)
            db_session.add(unique_code_obj)
            db_session.commit()
            db_session.refresh(unique_code_obj)
            return code_str

        for _ in range(5):
            codes["electronic"].append(generate_random_code_and_add(db, material_type_id=material_electronic.id)) 
            codes["plastic"].append(generate_random_code_and_add(db, material_type_id=material_plastic.id))    
            codes["any_material"].append(generate_random_code_and_add(db, material_type_id=material_electronic.id))
            codes["any_material"].append(generate_random_code_and_add(db, material_type_id=material_plastic.id)) 

        print("\nCódigos Únicos de Teste Gerados:")
        for key, value in codes.items():
            print(f"- {key}: {value}")
        
        print("\nCriação de dados de teste finalizada com sucesso!\n")

    except Exception as e:
        db.rollback()
        print(f"\nOCORREU UM ERRO DURANTE A CRIAÇÃO DOS DADOS DE TESTE: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    create_test_data()