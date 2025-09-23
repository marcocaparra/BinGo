import os
import sys
from pathlib import Path

import secrets
import string
from datetime import datetime, timedelta, UTC
import json

current_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(current_dir)) 

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from base_class import Base 
from database import DOCKER_SQLALCHEMY_DATABASE_URL

import models
from models.user_model import User
from models.material_type_model import MaterialType
from models.mission_model import Mission, UserMission 
from models.unique_code_model import UniqueCode
from models.discard_model import Discard
from models.achievement_model import Achievement, UserAchievement

from auth import get_password_hash
from services.achievement_service import AchievementConditionType

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
        
        plaintext_password = "testpassword123"
        hashed_pw = get_password_hash(plaintext_password)

        if not test_user:
            test_user = User(
                email="testuser@example.com",
                username="testuser",
                hashed_password=hashed_pw, 
                total_points=0.0, 
                level=1, 
                name="Test User",
                cpf="11122233344",
                phone_number="(11)98765-4321",
                discard_count=0,
                mission_completed_count=0
            )
            db.add(test_user)
            db.commit()
            db.refresh(test_user)
            print(f"Usuário de Teste criado: {test_user.email} (ID: {test_user.id})")
        else:
            test_user.total_points = 0.0 
            test_user.level = 1 
            test_user.hashed_password = hashed_pw
            test_user.discard_count = 0
            test_user.mission_completed_count = 0
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
            
        # --- Criação de Conquistas de Teste ---
        print("\nCriando conquistas de teste...")

        # Conquista: Primeiro Descarte
        achievement_first_discard = db.query(Achievement).filter(Achievement.name == "Primeiro Descarte").first()
        if not achievement_first_discard:
            achievement_first_discard = Achievement(
                name="Primeiro Descarte",
                description="Realize seu primeiro descarte e comece sua jornada sustentável.",
                criteria_json={"type": AchievementConditionType.FIRST_DISCARD},
                points_reward=10,
                badge_image_url="https://example.com/badges/first_discard.png",
                is_active=True
            )
            db.add(achievement_first_discard)
            db.commit()
            db.refresh(achievement_first_discard)
            print(f"Conquista criada: '{achievement_first_discard.name}' (ID: {achievement_first_discard.id})")

        # Conquista: Eco-Novato (100 pontos)
        achievement_eco_novato = db.query(Achievement).filter(Achievement.name == "Eco-Novato").first()
        if not achievement_eco_novato:
            achievement_eco_novato = Achievement(
                name="Eco-Novato",
                description="Alcance 100 pontos totais e se torne um Eco-Novato!",
                criteria_json={"type": AchievementConditionType.TOTAL_POINTS_REACHED, "target": 100},
                points_reward=20,
                badge_image_url="https://example.com/badges/eco_novato.png",
                is_active=True
            )
            db.add(achievement_eco_novato)
            db.commit()
            db.refresh(achievement_eco_novato)
            print(f"Conquista criada: '{achievement_eco_novato.name}' (ID: {achievement_eco_novato.id})")
        
        # Conquista: Descarte Eletrônico (1 item eletrônico)
        achievement_e_waste_novice = db.query(Achievement).filter(Achievement.name == "Descarte Eletrônico").first()
        if not achievement_e_waste_novice:
            achievement_e_waste_novice = Achievement(
                name="Descarte Eletrônico",
                description="Descarte seu primeiro item eletrônico. Um passo importante!",
                criteria_json={"type": AchievementConditionType.SPECIFIC_MATERIAL_DISCARD_COUNT, "material_type_id": material_electronic.id, "target": 1},
                points_reward=15,
                badge_image_url="https://example.com/badges/e_waste_novice.png",
                is_active=True
            )
            db.add(achievement_e_waste_novice)
            db.commit()
            db.refresh(achievement_e_waste_novice)
            print(f"Conquista criada: '{achievement_e_waste_novice.name}' (ID: {achievement_e_waste_novice.id})")

        # Conquista: Mestre do Descarte (5 descartes totais)
        achievement_discard_master = db.query(Achievement).filter(Achievement.name == "Mestre do Descarte").first()
        if not achievement_discard_master:
            achievement_discard_master = Achievement(
                name="Mestre do Descarte",
                description="Realize 5 descartes de qualquer tipo.",
                criteria_json={"type": AchievementConditionType.TOTAL_DISCARDS_COUNT, "target": 5},
                points_reward=25,
                badge_image_url="https://example.com/badges/discard_master.png",
                is_active=True
            )
            db.add(achievement_discard_master)
            db.commit()
            db.refresh(achievement_discard_master)
            print(f"Conquista criada: '{achievement_discard_master.name}' (ID: {achievement_discard_master.id})")

        print("Conquistas de teste criadas/atualizadas.\n")

        # --- Lógica de Missões (existente) ---
        mission_total = db.query(Mission).filter(Mission.name == "Descarte Total (3 itens)").first()
        if not mission_total:
            mission_total = Mission(
                name="Descarte Total (3 itens)",
                description="Descarte 3 itens de qualquer tipo para ganhar pontos extras.",
                objective=json.dumps({"action_type": "discard"}),
                reward_points=100,
                type="discard_count",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30),
                target_quantity=3
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
                objective=json.dumps({"action_type": "discard", "material_type_id": material_electronic.id}),
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
                objective=json.dumps({"action_type": "discard", "material_type_id": material_plastic.id}),
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

        db.query(UserAchievement).filter(UserAchievement.user_id == test_user.id).delete()
        db.commit()
        print(f"Conquistas do usuário de teste '{test_user.email}' limpas.\n")

    except Exception as e:
        db.rollback()
        print(f"\nOCORREU UM ERRO DURANTE A CRIAÇÃO DOS DADOS DE TESTE: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    create_test_data()