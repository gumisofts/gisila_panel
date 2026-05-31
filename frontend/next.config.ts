import type { NextConfig } from "next";

// In docker-compose dev the API is reachable in-network at `http://api:8000`
// but the browser still needs to call `http://localhost:8000`. We keep both:
//   - NEXT_PUBLIC_API_URL → baked into the client bundle.
//   - INTERNAL_API_URL    → used only by Next.js server (rewrites, SSR fetch).
const SSR_API =
  process.env.INTERNAL_API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://localhost:8000";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${SSR_API}/:path*`,
      },
    ];
  },
};

export default nextConfig;
