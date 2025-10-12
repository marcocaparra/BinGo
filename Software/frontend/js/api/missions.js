import { apiFetch } from "./http.js";

// Util: pega Bins de forma compatível (reward_bins novo ou reward_points legado)
const binsOf = (obj) => {
  if (typeof obj?.reward_bins === "number") return obj.reward_bins;
  if (typeof obj?.reward_points === "number") return obj.reward_points;
  if (typeof obj?.points === "number") return obj.points;
  return 0;
};

// Normaliza status vindos do backend (novo e antigo)
function normalizeStatus(value) {
  const v = String(value || "").toUpperCase();
  if (v.includes("PROGRESSO") || v === "IN_PROGRESS") return "IN_PROGRESS";
  if (v === "COMPLETED" || v === "CONCLUÍDA" || v === "CONCLUIDA") return "COMPLETED";
  if (v === "PENDING" || v === "PENDENTE" || v === "PENDING_ACCEPT") return "PENDING";
  return "PENDING";
}

export async function fetchAvailableMissions() {
  const data = await apiFetch("/missions", { method: "GET" });
  return (data || []).map((m) => ({
    id: m.id,
    title: m.name,
    description: m.description,
    points: binsOf(m),               // << Bins
    target: m.target_quantity,
    status: "AVAILABLE",
  }));
}

export async function fetchMyMissions() {
  const data = await apiFetch("/users/me/missions", { method: "GET" });

  return (data || []).map((item) => ({
    id: item.mission.id,
    title: item.mission.name,
    description: item.mission.description,
    status: normalizeStatus(item.status),
    current: item.progress ?? 0,
    target: item.mission.target_quantity,
    points: binsOf(item.mission),    // << Bins
  }));
}

export async function acceptMission(missionId) {
  return apiFetch(`/users/me/missions/${missionId}/accept`, {
    method: "POST",
  });
}
