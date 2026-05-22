/**
 * tagging-demo-worker
 *
 * Minimal Worker used by the tagging demo.
 * Returns its name and a health hint — no API tokens required.
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/") {
      return jsonResponse({
        worker: env.WORKER_NAME ?? "tagging-demo-worker",
        status: "ok",
        note: "This Worker is part of the tagging demo. Use the shell scripts to query its tags via the Resource Tagging API.",
      });
    }

    return jsonResponse(
      { error: "Not found. Try GET /" },
      404
    );
  },
};

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
