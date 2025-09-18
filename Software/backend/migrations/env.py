import os
import sys
from logging.config import fileConfig
from sqlalchemy import engine_from_config
from sqlalchemy import pool
from alembic import context

# --- Seu setup de sys.path existente ---
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parent.parent.parent))
# --- Fim do seu setup de sys.path ---

# --- Importar Base e HOST_SQLALCHEMY_DATABASE_URL do backend.database ---
# IMPORTANTE: A importação de 'backend.database' executa o arquivo database.py,
# o que, por sua vez, importa TODOS os modelos definidos no final de database.py.
# Isso garante que Base.metadata já estará populado com todos os seus modelos.
from backend.database import Base, HOST_SQLALCHEMY_DATABASE_URL

# this is the Alembic Config object, which provides
# access to values within the .ini file in use.
config = context.config

# --- Usar HOST_SQLALCHEMY_DATABASE_URL do seu database.py ---
config.set_main_option('sqlalchemy.url', HOST_SQLALCHEMY_DATABASE_URL)

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
# --- ALTERADO: REMOVEMOS AS IMPORTAÇÕES INDIVIDUAIS DOS MODELOS AQUI ---
# 'Base.metadata' já está populado graças à importação de 'backend.database'.
# Não precisamos importar os modelos individualmente novamente.

target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.
    ... (restante da função inalterado) ...
    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.
    ... (restante da função inalterado) ...
    """
    configuration = config.get_section(config.config_ini_section)
    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()