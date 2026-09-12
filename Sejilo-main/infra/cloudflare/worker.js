// SejiloChat edge Worker (STEP 29).
// Bound to api.sejilo.chat/*. Reverse-proxies to the origin (Cloudflare Tunnel
// public hostname or origin IP) and hardens responses. The origin already
// sends Helmet headers; these are edge-level belt-and-suspenders.

const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
};

export default {
  async fetch(request, env) {
    const origin = env.ORIGIN_HOST;
    if (!origin) {
      return new Response("ORIGIN_HOST not configured", { status: 500 });
    }

    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api") && !url.pathname.startsWith("/v1")) {
      return new Response("Not found", { status: 404 });
    }

    // Forward to origin, preserving method/headers/body.
    const upstream = new URL(url.pathname + url.search, origin);
    const init = {
      method: request.method,
      headers: request.headers,
      body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
      redirect: "follow",
    };

    const response = await fetch(upstream.toString(), init);
    const newHeaders = new Headers(response.headers);
    for (const [k, v] of Object.entries(SECURITY_HEADERS)) {
      newHeaders.set(k, v);
    }
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders,
    });
  },
};
