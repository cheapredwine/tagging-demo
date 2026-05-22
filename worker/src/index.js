/**
 * tagging-demo-worker
 *
 * Minimal Worker that returns its own tags when queried.
 * Used by the demo script to show real tagged resources in action.
 */

const API_BASE = "https://api.cloudflare.com/client/v4";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === "/") {
      return jsonResponse({
        worker: env.WORKER_NAME ?? "tagging-demo-worker",
        status: "ok",
        hint: "GET /tags to see this Worker's metadata tags",
      });
    }

    // Read this Worker's tags via the Tagging API
    if (url.pathname === "/tags") {
      return handleGetTags(env);
    }

    return jsonResponse(
      { error: "Not found. Try GET / or GET /tags" },
      404
    );
  },
};

async function handleGetTags(env) {
  const accountId = env.ACCOUNT_ID;
  const token = env.API_TOKEN;
  const workerName = env.WORKER_NAME ?? "tagging-demo-worker";

  if (!accountId || !token) {
    return jsonResponse(
      {
        error: "Missing ACCOUNT_ID or API_TOKEN secrets",
        note: "This Worker needs an Account Owned Token (AOT) with Tag:Read to fetch its own tags.",
      },
      500
    );
  }

  const resp = await fetch(
    `${API_BASE}/accounts/${accountId}/tags?resource_type=worker&resource_id=${encodeURIComponent(workerName)}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
    }
  );

  const data = await resp.json();
  if (!data.success) {
    return jsonResponse({ error: data.errors }, resp.status);
  }

  return jsonResponse({
    resource_type: "worker",
    resource_id: workerName,
    tags: data.result?.tags ?? {},
  });
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
