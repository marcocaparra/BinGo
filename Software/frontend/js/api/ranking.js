import { apiFetch } from "./http.js";

/** Busca a lista do ranking de usuários */
export async function fetchRanking(){
  return apiFetch("/users/ranking");
}
