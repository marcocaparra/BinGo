import { requireAuth, getMe } from "../api/auth.js";
import { fetchRanking } from "../api/ranking.js";

requireAuth();

const els = {
  rankingList: document.getElementById("ranking-list"),
  myRankTag: document.getElementById("my-rank-tag"),
  myRankPosition: document.getElementById("my-rank-position"),
  userName: document.getElementById("userName"),
  userBins: document.getElementById("userBins"),
  rankingScroll: document.getElementById("rankingScroll"),
};

function firstName(full){
  if(!full || typeof full !== "string") return "Usuário";
  const parts = full.trim().split(/\s+/);
  return parts[0] || "Usuário";
}

function setupCutlineOnScroll(container){
  if(!container) return;

  const toggle = () => {
    if(container.scrollTop > 2){
      container.classList.add("show-cutline");
    } else {
      container.classList.remove("show-cutline");
    }
  };

  toggle();
  container.addEventListener("scroll", toggle, { passive: true });
}

async function init(){
  try{
    const [rankingData, currentUser] = await Promise.all([
      fetchRanking(),
      getMe()
    ]);

    els.userName.textContent = firstName(currentUser.name);
    els.userBins.textContent = currentUser.total_points ?? 0;

    els.rankingList.innerHTML = "";

    if(!rankingData || rankingData.length === 0){
      els.rankingList.innerHTML = `<li class="empty-state">O ranking ainda está vazio. Seja o primeiro a pontuar!</li>`;
      els.myRankTag.textContent = "Você ainda não está no ranking.";
      setupCutlineOnScroll(els.rankingScroll);
      return;
    }

    let currentUserRank = null;

    rankingData.forEach((user, index) => {
      const rank = index + 1;
      const isMe = user.id === currentUser.id;
      if(isMe) currentUserRank = rank;
      els.rankingList.appendChild(createRankItem(user, rank, isMe));
    });

    if(currentUserRank){
      els.myRankPosition.textContent = currentUserRank;
    }else{
      els.myRankTag.textContent = "Você ainda não está no ranking.";
    }

    setupCutlineOnScroll(els.rankingScroll);

  }catch(err){
    console.error("❌ Falha ao carregar o ranking:", err);
    els.rankingList.innerHTML = `<li class="empty-state">Não foi possível carregar o ranking.</li>`;
    setupCutlineOnScroll(els.rankingScroll);
  }
}

function createRankItem(user, rank, isMe){
  const li = document.createElement("li");
  li.className = "rank-item";
  if(isMe) li.classList.add("is-me");

  li.innerHTML = `
    <span class="rank-position">${rank}º</span>
    <span class="rank-username">${user.username}</span>
    <span class="rank-points">${user.total_points} pts</span>
  `;
  return li;
}

init();
