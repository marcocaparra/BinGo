import { apiFetch } from "./http.js";

export async function fetchAvailableMissions() {
  const data = await apiFetch("/missions", { method: "GET" });
  return (data || []).map(m => ({
    id: m.id,
    title: m.name,
    description: m.description,
    points: m.reward_points,
    target: m.target_quantity,
    status: "AVAILABLE"
  }));
}

export async function fetchMyMissions() {
  const data = await apiFetch("/users/me/missions", { method: "GET" });

  return (data || []).map(item => {
    let normalizedStatus = "PENDING";
    const backendStatus = String(item.status || "").toUpperCase();

    if (backendStatus.includes("PROGRESSO") || backendStatus === "IN_PROGRESS") {
      normalizedStatus = "IN_PROGRESS";
    } else if (backendStatus === "CONCLUÍDA" || backendStatus === "COMPLETED") {
      normalizedStatus = "COMPLETED";
    }

    return {
      id: item.mission.id,
      title: item.mission.name,
      description: item.mission.description,
      status: normalizedStatus,
      current: item.progress,
      target: item.mission.target_quantity,
      points: item.mission.reward_points
    };
  });
}

export async function acceptMission(missionId) {
  return apiFetch(`/users/me/missions/${missionId}/accept`, {
    method: "POST"
  });
}
