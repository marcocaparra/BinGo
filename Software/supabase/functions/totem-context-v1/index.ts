import { createTotemHandler } from "../_shared/totem-handler.ts";

Deno.serve(createTotemHandler("context"));
