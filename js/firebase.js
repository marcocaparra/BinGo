console.log("firebase.js carregado!");

const firebaseConfig = {
  apiKey: "AIzaSyCo6X92QHPGB3cfc6Pnf7JAZ0HgCK8ITA0",
  authDomain: "projetobingo-2249a.firebaseapp.com",
  databaseURL: "https://projetobingo-2249a-default-rtdb.firebaseio.com",
  projectId: "projetobingo-2249a",
  storageBucket: "projetobingo-2249a.firebasestorage.app",
  messagingSenderId: "335697826207",
  appId: "1:335697826207:web:8eb2b664fdda934710adaa",
  measurementId: "G-CSH68HSPZ2"
};

firebase.initializeApp(firebaseConfig);
const database = firebase.database();

function criarConta() {
  const usuario = document.getElementById('usuario').value.trim().toLowerCase();
  const nome = document.getElementById('nome').value.trim();
  const email = document.getElementById('email').value.trim().toLowerCase();
  const senha = document.getElementById('senha').value.trim();

  if (!usuario || !nome || !email || !senha) {
    alert('Preencha todos os campos!');
    return;
  }

  const usuarioFormatado = usuario.replace(/\./g, '_');

  database.ref('usuarios').once('value', function(snapshot) {
    let emailExiste = false;
    let usuarioExiste = false;

    snapshot.forEach(function(childSnapshot) {
      const user = childSnapshot.val();
      if (user.email === email) emailExiste = true;
      if (user.usuario === usuario) usuarioExiste = true;
    });

    if (emailExiste) {
      alert('Este e-mail já está cadastrado!');
    } else if (usuarioExiste) {
      alert('Este nome de usuário já está em uso!');
    } else {
      database.ref('usuarios/' + usuarioFormatado).set({
        usuario,
        nome,
        email,
        senha,
        bins: 0,
        xp: 0,
        nivel: "Iniciante",
        sequencia: 0
      }).then(() => {
        alert('Conta criada com sucesso!');
        window.location.href = "login.html"; 
      }).catch((error) => {
        alert('Erro ao criar conta: ' + error.message);
      });
    }
  });
}
function fazerLogin() {
  const login = document.getElementById('login').value.trim().toLowerCase();
  const senha = document.getElementById('senha').value.trim();

  if (!login || !senha) {
    alert('Preencha todos os campos!');
    return;
  }

  database.ref('usuarios').once('value', function(snapshot) {
    let usuarioEncontrado = null;

    snapshot.forEach(function(childSnapshot) {
      const user = childSnapshot.val();
      if (user.email === login || user.usuario === login) {
        usuarioEncontrado = user;
      }
    });

    if (!usuarioEncontrado) {
      alert('Usuário ou e-mail não encontrado!');
      return;
    }

    if (usuarioEncontrado.senha !== senha) {
      alert('Senha incorreta!');
      return;
    }

    alert('Login bem-sucedido!');
    window.location.href = "dashboard.html";
  });
}
