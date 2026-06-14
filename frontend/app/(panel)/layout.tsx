"use client";

import { Navigate, Outlet } from "react-router-dom";
import { Sidebar } from "@/components/sidebar";
import { Topbar } from "@/components/topbar";
import { getToken } from "@/lib/api";

export default function PanelLayout() {
  // Guard synchronously during render so logged-out users are redirected before
  // the panel paints (no flash), and the protected API calls inside child pages
  // never fire without a token.
  if (!getToken()) return <Navigate to="/login" replace />;

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <div className="flex flex-1 flex-col">
        <Topbar />
        <main className="flex-1 overflow-x-hidden bg-background/30">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
