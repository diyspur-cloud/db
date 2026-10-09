export const cors = (res?: Response) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, idempotency-key, x-scheduled-reminders-secret",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  };
  if (!res) return new Response("ok", { headers });
  const newRes = new Response(res.body, res);
  Object.entries(headers).forEach(([k, v]) => newRes.headers.set(k, v));
  return newRes;
};
