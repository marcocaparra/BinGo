import { apiFetch } from "./http.js";

export async function registerDiscard(uniqueCode) {
  return apiFetch("/discards/", {
    method: "POST",
    body: JSON.stringify({ unique_code: uniqueCode })
  });
}
