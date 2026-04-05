import { apiFetch } from "./http.js";

export async function fetchRanking(){
  return apiFetch("/users/ranking");
}
