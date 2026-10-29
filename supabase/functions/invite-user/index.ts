import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in required" }, 401);

  const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: userError } = await callerClient.auth.getUser();
  if (userError || !user) return json({ error: "Invalid session" }, 401);
  const { data: profile } = await callerClient.from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (profile?.role !== "admin") return json({ error: "Only admins can invite users" }, 403);

  const body = await req.json().catch(() => null);
  const email = String(body?.email || "").trim().toLowerCase();
  const name = String(body?.name || "").trim();
  const allowedRoles = ["staff", "housekeeping", "finance", "view_only", "admin"];
  const role = String(body?.role || "staff");
  const region = String(body?.region || "").trim() || null;
  if (!email || !name || !allowedRoles.includes(role)) return json({ error: "Name, email, or role is invalid" }, 400);

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name: name, role, region },
  });
  if (error) return json({ error: error.message }, 400);
  const { error: profileError } = await admin.from("profiles").upsert({ id: data.user.id, full_name: name, email, role, region }, { onConflict: "id" });
  if (profileError) return json({ error: profileError.message }, 500);
  return json({ invited: true, userId: data.user.id });
});
