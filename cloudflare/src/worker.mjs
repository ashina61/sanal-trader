/**
 * SanalTrader: external 5-minute heartbeat for the existing paper-trading engine.
 * Does not send orders or maintain a second wallet.
 * GitHub access token lives ONLY in Cloudflare Workers secret storage.
 */
export const DISPATCH_URL =
  "https://api.github.com/repos/ashina61/sanal-trader/actions/workflows/paper-bot.yml/dispatches";

export async function dispatchPaperBot(env, http = fetch) {
  const token = env?.GITHUB_DISPATCH_TOKEN;
  if (typeof token !== "string" || !token.trim()) {
    throw new Error("Missing GITHUB_DISPATCH_TOKEN secret");
  }
  const response = await http(DISPATCH_URL, {
    method: "POST",
    headers: {
      "Accept": "application/vnd.github+json",
      "Authorization": "Bearer " + token,
      "Content-Type": "application/json",
      "User-Agent": "SanalTrader-Cloudflare-Scheduler",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: JSON.stringify({ ref: "main", inputs: { mode: "run" } }),
  });
  // The dispatch endpoint has no JSON response body on success.
  if (response.body?.cancel) await response.body.cancel();
  if (response.status !== 204) {
    // Deliberately omit response body, which can contain sensitive diagnostics.
    throw new Error("GitHub workflow_dispatch failed: HTTP " + response.status);
  }
  return { ok: true, status: response.status };
}

const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "X-Content-Type-Options": "nosniff",
  },
});

export default {
  async scheduled(_event, env, ctx) {
    // GitHub's own cron may run too. The existing bot-data wallet, concurrency
    // group and 150-second cycle deduplication avoid nearby double decisions.
    ctx.waitUntil(dispatchPaperBot(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
      return json({
        service: "sanaltrader-external-scheduler",
        mode: "paper-only",
        configured: Boolean(env.GITHUB_DISPATCH_TOKEN),
        note: "Cron runs remotely; this endpoint NEVER places trades or starts a workflow.",
      });
    }
    return json({ error: "Not found" }, 404);
  },
};
