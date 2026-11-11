// Cloudflare Pages: the whole site sits behind a password until launch.
// The browser shows its own login box (HTTP Basic auth); any username works.
// The password is never in the code: set SITE_PASSWORD in the Pages project
// (Settings › Variables and Secrets, as a Secret). Remove this file to open the site.
export async function onRequest({ request, env, next }) {
  const expected = env.SITE_PASSWORD;
  if (!expected) return new Response('Site locked: SITE_PASSWORD is not set.', { status: 503 });

  const auth = request.headers.get('Authorization') ?? '';
  const [scheme, encoded] = auth.split(' ');
  if (scheme === 'Basic' && encoded) {
    let given = '';
    try {
      given = atob(encoded).split(':').slice(1).join(':'); // "user:password"
    } catch {}
    const a = new TextEncoder().encode(given), b = new TextEncoder().encode(expected);
    // Same length first: timingSafeEqual needs it, and a length check leaks nothing useful here.
    if (a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b)) {
      const response = await next();
      const headers = new Headers(response.headers);
      headers.set('X-Robots-Tag', 'noindex'); // keep it out of search engines meanwhile
      return new Response(response.body, { status: response.status, headers });
    }
  }
  return new Response('Password required.', {
    status: 401,
    headers: { 'WWW-Authenticate': 'Basic realm="KliqPlayer preview", charset="UTF-8"', 'X-Robots-Tag': 'noindex' },
  });
}
