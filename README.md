# ♻️ Projeto BinGo: Transformando o Descarte Consciente em Uma Aventura Recompensadora!

![Imagem da aplicação](/Software/frontend/assets/images/logo-principal.png)

---

## 🎯 Sobre o Projeto BinGo

O **Projeto BinGo** é uma iniciativa inovadora que une **tecnologia, educação e sustentabilidade** para revolucionar a forma como lidamos com o **lixo eletrônico** em ambientes escolares. Nossa missão é gamificar o processo de descarte consciente, incentivando alunos do Ensino Fundamental e Médio a participarem ativamente da reciclagem, transformando um hábito muitas vezes ignorado em uma **experiência divertida, educativa e recompensadora**.

Através da integração de **lixeiras inteligentes com visão computacional** e uma **plataforma digital gamificada**, o BinGo cria um ecossistema onde cada descarte correto gera pontos, desbloqueia desafios e permite o resgate de recompensas físicas, promovendo um impacto ambiental positivo e a formação de cidadãos mais conscientes.

### O Problema que Resolvemos

A crescente quantidade de lixo eletrônico (e-waste) representa um desafio ambiental global. Muitas vezes, esses materiais são descartados incorretamente, contaminando o meio ambiente e desperdiçando recursos valiosos. Em escolas, a conscientização e a infraestrutura para o descarte adequado ainda são limitadas.

### Nossa Solução Inovadora

O BinGo oferece uma solução completa:

1.  **Lixeiras Inteligentes:** Equipadas com **visão computacional**, nossas lixeiras identificam e registram o descarte de lixo eletrônico, garantindo a validação e o engajamento em tempo real.
2.  **Plataforma Gamificada:** Um sistema online onde os alunos podem acompanhar seus pontos, seu progresso, participar de desafios interturmas/interescolas e resgatar suas recompensas.
3.  **Engajamento e Recompensa:** Pontos convertidos em benefícios tangíveis, incentivando a participação contínua e a competição saudável.
4.  **Educação e Conscientização:** Ferramenta prática para educadores ensinarem sobre a importância da reciclagem e o impacto do lixo eletrônico.
5.  **Múltiplos Perfis de Usuário:** Uma interface adaptada para alunos, professores, coordenadores/diretores e administradores, oferecendo funcionalidades específicas para cada papel.

---

## ✨ Principais Funcionalidades

*   **Validação de Descarte:** Lixeiras inteligentes com visão computacional para reconhecer lixo eletrônico.
*   **Sistema de Pontuação:** Alunos ganham pontos a cada descarte correto.
*   **Gamificação:** Desafios individuais e em equipe, placares de líderes e metas de reciclagem.
*   **Catálogo de Recompensas:** Alunos podem trocar seus pontos por prêmios físicos.
*   **Perfis de Usuário Robustos:**
    *   **Alunos:** Acompanham pontuação, desafios e histórico de descarte.
    *   **Professores:** Gerenciam turmas, visualizam o engajamento dos alunos e lançam desafios.
    *   **Coordenadores/Diretores:** Acompanham o desempenho da escola, gerenciam professores e turmas.
    *   **Administradores:** Visão macro da plataforma, gerenciamento de escolas, usuários e relatórios gerais.
*   **Relatórios e Dashboards:** Visualização clara do impacto da reciclagem por escola, turma e individualmente.
*   **Código Único de Descarte:** Geração e validação de códigos para cada descarte, garantindo a integridade do sistema.

---

## 💻 Tecnologias Utilizadas

Este projeto é dividido em módulos de software e hardware para garantir uma solução robusta e escalável.

### Backend
*   **Linguagem:** Python
*   **Framework:** FastAPI (para APIs rápidas e documentadas)
*   **Banco de Dados:** MySQL
*   **ORM (Object-Relational Mapper):** SQLAlchemy
*   **Migrações de Banco de Dados:** Alembic
*   **Autenticação:** JWT (JSON Web Tokens) com bcrypt para hashing de senhas.

### Frontend
*   **Linguagens:** HTML5, CSS3, JavaScript (Vanilla JS)
*   **Futura Evolução:** Planejamos migrar para **React.js** para uma experiência mais dinâmica e escalável.

### Hardware (Lixeira Inteligente)
*   **Microcontrolador:** ESP32/ESP8266
*   **Visão Computacional:** Câmera integrada para detecção de materiais.

---

## ❕ Como Começar (Para Desenvolvedores)

Para configurar e executar o Projeto BinGo em seu ambiente local, siga os passos abaixo:

### Pré-requisitos

*   Python 3.8+
*   `pip` (gerenciador de pacotes Python)
*   MySQL Server
*   `git`

### Instalação

1.  **Clone o repositório:**
    ```bash
    git clone https://github.com/SeuUsuario/bingo.git
    cd bingo
    ```
2.  **Crie e ative um ambiente virtual (recomendado):**
    ```bash
    python -m venv venv
    # No Windows
    .\venv\Scripts\activate
    # No macOS/Linux
    source venv/bin/activate
    ```
3.  **Instale as dependências do backend:**
    ```bash
    cd backend
    pip install -r requirements.txt
    ```
4.  **Configure as variáveis de ambiente:**
    Crie um arquivo `.env` na pasta `backend` com as seguintes variáveis:
    ```
    DATABASE_URL="mysql+pymysql://user:password@host:port/dbname"
    SECRET_KEY="sua_chave_secreta_jwt" # Gerar uma chave segura e aleatória
    ALGORITHM="HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES=30
    ```
    *Substitua `user`, `password`, `host`, `port` e `dbname` pelas suas credenciais MySQL.*
5.  **Execute as migrações do banco de dados:**
    Certifique-se de que o seu MySQL esteja em execução e as variáveis de ambiente configuradas.
    ```bash
    alembic upgrade head
    ```
    *Se encontrar erros de `ModuleNotFoundError` com Alembic, verifique se seu ambiente virtual está ativado e se o `PYTHONPATH` ou o `sys.path.append` nos arquivos de migração (`env.py`) apontam corretamente para o diretório `backend`.*

### Executando a Aplicação

1.  **Inicie o servidor FastAPI (Backend):**
    Na pasta `backend`:
    ```bash
    uvicorn main:app --reload
    ```
    O backend estará disponível em `http://127.0.0.1:8000`. Você pode acessar a documentação interativa da API em `http://127.0.0.1:8000/docs` (Swagger UI) ou `http://127.0.0.1:8000/redoc`.

---

## 🔭 Roadmap Futuro

Estamos constantemente aprimorando o Projeto BinGo. Alguns dos nossos próximos passos incluem:

*   **Migração do Frontend para React.js:** Para uma experiência de usuário mais rica e reativa.
*   **Integração Completa com Hardware:** Conexão robusta entre as lixeiras inteligentes e a plataforma.
*   **Módulo de Desafios Avançados:** Criação de desafios customizáveis para escolas e professores.
*   **Funcionalidades de Rede Social:** Integração com Instagram e outras plataformas para amplificar a conscientização.
*   **Preparação para Feiras:** Aprimoramento das funcionalidades e protótipos para a FECEG, FEMIC e FEBRAT 2025.

---

## 🤝 Contribuindo

Adoramos contribuições! Se você deseja contribuir para o Projeto BinGo, siga estas diretrizes:

1.  Faça um fork do repositório.
2.  Crie uma nova branch (`git checkout -b feature/sua-feature`).
3.  Faça suas alterações e commit (`git commit -m 'feat: Adiciona nova funcionalidade'`).
4.  Envie para a branch (`git push origin feature/sua-feature`).
5.  Abra um Pull Request detalhado.

---

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE] para detalhes.

---

## 📞 Contato

Para dúvidas, sugestões ou parcerias, entre em contato através de:

*   **Email:** nextidea.ni@gmail.com
*   **Instagram:** [@bingo.eco]https://www.instagram.com/bingo.eco/)

---

## ✨ Agradecimentos

Gostaríamos de agradecer a todos os contribuidores, mentores e entusiastas que tornam o Projeto BinGo possível!
