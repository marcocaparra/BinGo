import { createTotemHandler } from "../_shared/totem-handler.ts";

Deno.serve(createTotemHandler("student-summary"));
