
# ♻️ Projeto BinGo: Descarte Inteligente, Gamificação e Educação Ambiental

![Logo BinGo](/Software/frontend/public/assets/images/logo-principal.png)

---

## 🎯 Sobre o Projeto

O BinGo é uma plataforma completa que une hardware (lixeiras inteligentes com visão computacional) e software (backend robusto, frontend interativo e gamificado) para transformar o descarte de lixo eletrônico em escolas em uma experiência educativa, divertida e recompensadora.

O sistema integra:
- **Lixeiras inteligentes** que reconhecem e validam descartes via IA.
- **Plataforma web** para alunos, professores, gestores e administradores acompanharem pontuação, missões, conquistas e recompensas.
- **Gamificação**: desafios, ranking, conquistas e recompensas físicas.
- **Relatórios e dashboards** para acompanhamento do impacto ambiental.

---

## 🗂 Estrutura do Projeto

```
Software/
├── backend/
│   ├── main.py                # Ponto de entrada FastAPI
│   ├── database.py            # Configuração SQLAlchemy
│   ├── auth.py                # Autenticação JWT
│   ├── base_class.py          # Base dos modelos ORM
│   ├── debug_models.py        # Utilitários de depuração
│   ├── populate_test_data.py  # Popular banco para testes
│   ├── Dockerfile*            # Imagem do backend
│   ├── docs/                  # Documentação técnica
│   ├── migrations/            # Migrações Alembic
│   ├── models/                # Modelos ORM (User, Mission, Discard, etc)
│   ├── routers/               # Endpoints da API (users, missions, discards, etc)
│   ├── schemas/               # Schemas Pydantic (validação/serialização)
│   ├── services/              # Lógicas de negócio (ex: conquistas)
│   └── public/assets/         # Badges e recursos públicos
├── frontend/
│   ├── index.html             # Página principal
│   ├── package.json           # Dependências JS
│   ├── css/                   # Estilos globais e de páginas
│   ├── js/                    # Scripts, APIs, páginas e componentes UI
│   ├── public/                # Páginas estáticas (dashboard, login, etc)
│   ├── assets/                # Imagens e badges
│   ├── landing/               # Landing page institucional
│   └── ...
└── .devcontainer/             # Ambiente de desenvolvimento remoto
```

---

## ✨ Funcionalidades Principais

- **Descarte Validado:** Lixeiras inteligentes com IA reconhecem e registram descartes de eletrônicos.
- **Sistema de Pontuação:** Pontos por descarte correto, com acúmulo para ranking e recompensas.
- **Gamificação Completa:** Missões, conquistas, badges, ranking, desafios individuais e coletivos.
- **Catálogo de Recompensas:** Resgate de prêmios físicos por pontos acumulados.
- **Perfis de Usuário:** Aluno, professor, gestor, administrador – cada um com funcionalidades específicas.
- **Relatórios e Dashboards:** Visualização do impacto ambiental por escola, turma e usuário.
- **Integração Hardware-Software:** Comunicação entre lixeira e backend via API REST.
- **Migrações e Evolução do Banco:** Alembic + SQLAlchemy para versionamento e atualização do banco de dados.
- **Autenticação Segura:** JWT, bcrypt para senhas, controle de acesso por perfil.
- **Frontend Modular:** Páginas separadas, componentes reutilizáveis, integração direta com backend.
- **Landing Page:** Apresentação institucional do projeto.

---

## 💻 Tecnologias Utilizadas

- **Backend:** Python, FastAPI, SQLAlchemy, Alembic, MySQL, JWT, bcrypt
- **Frontend:** HTML5, CSS3, JavaScript (Vanilla), organização para futura migração para React.js
- **Hardware:** ESP32/ESP8266, visão computacional embarcada

---

## 🚀 Como Executar

1. **Clone o repositório e acesse a pasta:**
    ```bash
    git clone https://github.com/SeuUsuario/bingo.git
    cd bingo/Software
    ```

2. **Backend:**
    - Crie e ative um ambiente virtual Python.
    - Instale dependências: `pip install -r backend/requirements.txt`
    - Configure o `.env` em `backend/` com as variáveis de conexão MySQL e JWT.
    - Execute as migrações: `alembic upgrade head`
    - Inicie o servidor: `uvicorn main:app --reload` (em `backend/`)

3. **Frontend:**
    - Basta abrir `frontend/index.html` ou as páginas em `frontend/public/` no navegador.
    - Para desenvolvimento, utilize um servidor local (ex: `npx serve frontend`).

4. **Hardware:**
    - Configure o firmware na lixeira inteligente conforme documentação em `docs/`.

---

## 🏆 Roadmap e Evolução

- Migração do frontend para React.js
- Notificações e eventos em tempo real
- Novos tipos de missões e conquistas
- Integração com redes sociais
- Expansão para outros tipos de resíduos

---

## 🤝 Contribuição

1. Faça fork do repositório.
2. Crie uma branch (`git checkout -b feature/sua-feature`).
3. Commit e push das alterações.
4. Abra um Pull Request detalhado.

---

## 📄 Licença

MIT. Veja o arquivo [LICENSE] para detalhes.

---

## 📞 Contato

- Email: nextidea.ni@gmail.com
- Instagram: [@bingo.eco](https://www.instagram.com/bingo.eco/)

---

## ✨ Agradecimentos

A todos os colaboradores, mentores e apoiadores do BinGo!
