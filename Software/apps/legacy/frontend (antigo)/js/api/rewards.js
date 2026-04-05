import { apiFetch } from "./http.js";

export async function fetchRewards() {
  return apiFetch("/rewards");
}

export async function redeemReward(rewardId) {
  return apiFetch(`/rewards/${rewardId}/redeem`, { method: "POST" });
}
