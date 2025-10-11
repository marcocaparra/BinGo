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
  return (data || []).map(item => ({
    id: item.mission.id,
    title: item.mission.name,
    description: item.mission.description,
    status: item.status.toUpperCase().replace(" ", "_"),
    current: item.progress,
    target: item.mission.target_quantity,
    points: item.mission.reward_points
  }));
}

export async function acceptMission(missionId) {
  return apiFetch(`/users/me/missions/${missionId}/accept`, {
    method: "POST"
  });
}