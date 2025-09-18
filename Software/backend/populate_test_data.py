# backend/populate_test_data.py

import os
import sys
from pathlib import Path

# --- Adicione estas importações para geração de códigos aleatórios ---
import secrets # Para geração segura de números aleatórios
import string  # Para ter acesso a caracteres alfanuméricos
# --- Fim das novas importações ---

# --- INÍCIO: Configuração do sys.path para encontrar os módulos ---
# Esta parte é mais para execução local, mas não interfere no Docker
current_dir = Path(__file__).resolve().parent
project_root = current_dir.parent
sys.path.insert(0, str(project_root))
# --- FIM: Configuração do sys.path ---

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
# Mudança aqui: importando UTC diretamente é ok para Python 3.11+
from datetime import datetime, timedelta, UTC

import json

# IMPORTAÇÃO CORRIGIDA: Usando DOCKER_SQLALCHEMY_DATABASE_URL
from database import Base, DOCKER_SQLALCHEMY_DATABASE_URL

try:
    User = Base.registry._class_registry["User"]
    MaterialType = Base.registry._class_registry["MaterialType"]
    Mission = Base.registry._class_registry["Mission"]
    UserMission = Base.registry._class_registry["UserMission"]
    UniqueCode = Base.registry._class_registry["UniqueCode"]
    Discard = Base.registry._class_registry["Discard"]
except KeyError as e:
    print(f"ERRO CRÍTICO: Modelo '{e}' não encontrado no registro da Base.")
    print("Isso pode indicar que 'backend/database.py' não está importando todos os modelos corretamente ou que o nome da classe está errado.")
    sys.exit(1)

# CRIAÇÃO DO ENGINE CORRIGIDA: Usando DOCKER_SQLALCHEMY_DATABASE_URL
script_engine = create_engine(DOCKER_SQLALCHEMY_DATABASE_URL)
ScriptSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=script_engine)

# ... (código anterior) ...

# script_engine = create_engine(DOCKER_SQLALCHEMY_DATABASE_URL)
# ScriptSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=script_engine)

print("Configurando mappers do SQLAlchemy e verificando tabelas (pode levar alguns segundos)...")

# --- INÍCIO: Adição para lidar com FK_CHECKS ---
with script_engine.connect() as connection:
    print("Desativando verificações de chave estrangeira temporariamente...")
    connection.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
    connection.commit() # Commit para garantir que o comando seja aplicado

    print("Deletando todas as tabelas existentes (se houver)...")
    Base.metadata.drop_all(bind=script_engine)
    print("Tabelas existentes deletadas.")

    print("Recriando todas as tabelas a partir dos modelos...")
    Base.metadata.create_all(bind=script_engine)
    print("Mappers configurados e tabelas verificadas.\n")

    print("Reativando verificações de chave estrangeira...")
    connection.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
    connection.commit() # Commit para garantir que o comando seja aplicado
# --- FIM: Adição para lidar com FK_CHECKS ---

# ... (restante do código) ...

# --- BLOCO DE DIAGNÓSTICO ---
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
# --- FIM DO BLOCO DE DIAGNÓSTICO ---


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

        # --- 1. Criar/Resetar Usuário de Teste ---
        test_user = db.query(User).filter(User.email == "testuser@example.com").first()
        if not test_user:
            test_user = User(
                email="testuser@example.com",
                username="testuser",
                hashed_password="somehashedpassword",
                total_points=0,
                name="Test User",
                cpf="11122233344",
                phone_number="(11)98765-4321",
            )
            db.add(test_user)
            db.commit()
            db.refresh(test_user)
            print(f"Usuário de Teste criado: {test_user.email} (ID: {test_user.id})")
        else:
            test_user.total_points = 0
            db.add(test_user)
            db.commit()
            db.refresh(test_user)
            print(f"Usuário de Teste existente resetado: {test_user.email} (ID: {test_user.id})")

        # --- 2. Criar/Resetar Tipos de Materiais ---
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
            
        # --- 3. Criar/Resetar Missões ---
        mission_total = db.query(Mission).filter(Mission.name == "Descarte Total (3 itens)").first()
        if not mission_total:
            mission_total = Mission(
                name="Descarte Total (3 itens)",
                description="Descarte 3 itens de qualquer tipo para ganhar pontos extras.",
                objective={"count": 3},
                reward_points=100,
                type="discard_total",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30)
            )
            db.add(mission_total)
            db.commit()
            db.refresh(mission_total)
            print(f"Missão criada: '{mission_total.name}' (ID: {mission_total.id})")

        mission_electronic = db.query(Mission).filter(Mission.name == "Eletrônico Mestre (2x)").first()
        if not mission_electronic:
            mission_electronic = Mission(
                name="Eletrônico Mestre (2x)",
                description="Descarte 2 itens eletrônicos para provar seu domínio.",
                objective={"count": 2},
                reward_points=150,
                type="discard_electronic",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30)
            )
            db.add(mission_electronic)
            db.commit()
            db.refresh(mission_electronic)
            print(f"Missão criada: '{mission_electronic.name}' (ID: {mission_electronic.id})")

        mission_plastic = db.query(Mission).filter(Mission.name == "Plástico Consciente (2x)").first()
        if not mission_plastic:
            mission_plastic = Mission(
                name="Plástico Consciente (2x)",
                description="Descarte 2 itens plásticos para um futuro mais verde.",
                objective={"count": 2, "material_type_name": "plástico"},
                reward_points=75,
                type="discard_material_type",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30)
            )
            db.add(mission_plastic)
            db.commit()
            db.refresh(mission_plastic)
            print(f"Missão criada: '{mission_plastic.name}' (ID: {mission_plastic.id})")

        mission_points = db.query(Mission).filter(Mission.name == "Acumulador de Pontos (50)").first()
        if not mission_points:
            mission_points = Mission(
                name="Acumulador de Pontos (50)",
                description="Acumule 50 pontos de descarte para uma grande recompensa.",
                objective={"points": 50},
                reward_points=200,
                type="accumulate_points",
                is_active=True,
                start_date=datetime.now(UTC),
                end_date=datetime.now(UTC) + timedelta(days=30)
            )
            db.add(mission_points)
            db.commit()
            db.refresh(mission_points)
            print(f"Missão criada: '{mission_points.name}' (ID: {mission_points.id})")


        # --- 4. Atribuir Missões ao Usuário de Teste (UserMissions) ---
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

        # --- 5. Gerar Códigos Únicos para Teste ---
        # Excluir códigos únicos não utilizados para evitar duplicatas e ter um ambiente limpo
        db.query(UniqueCode).filter(UniqueCode.is_used == False).delete()
        db.commit()
        print("\nCódigos Únicos não utilizados limpos.")

        codes = {
            "electronic": [],
            "plastic": [],
            "any_material": []
        }

        # FUNÇÃO ALTERADA para gerar códigos alfanuméricos aleatórios de 6 caracteres
        def generate_random_code(length=6):
            characters = string.ascii_uppercase + string.digits # Letras maiúsculas e números
            
            # Loop para garantir que o código gerado seja único
            while True:
                code_str = ''.join(secrets.choice(characters) for _ in range(length))
                # Verifica se o código já existe no banco de dados
                existing_code = db.query(UniqueCode).filter(UniqueCode.code == code_str).first()
                if not existing_code:
                    break # Encontrou um código único, sai do loop
            
            unique_code_obj = UniqueCode(code=code_str, is_used=False)
            db.add(unique_code_obj)
            db.commit()
            db.refresh(unique_code_obj)
            return code_str

        for _ in range(5):
            # As chamadas agora usam a nova função, sem prefixo no código gerado
            codes["electronic"].append(generate_random_code()) 
            codes["plastic"].append(generate_random_code())    
            codes["any_material"].append(generate_random_code())
            codes["any_material"].append(generate_random_code()) # Para gerar 10 códigos no total para 'any_material'

        print("\nCódigos Únicos de Teste Gerados:")
        for key, value in codes.items():
            print(f"- {key}: {value}")
        
        print("\nCriação de dados de teste finalizada com sucesso!")

    except Exception as e:
        db.rollback()
        print(f"\nOCORREU UM ERRO DURANTE A CRIAÇÃO DOS DADOS DE TESTE: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    create_test_data()