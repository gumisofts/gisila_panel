"use client";

import { useEffect } from "react";
import { Outlet } from "react-router-dom";
import { useRouter } from "@/compat/navigation";
import { Sidebar } from "@/components/sidebar";
import { Topbar } from "@/components/topbar";
import { getToken } from "@/lib/api";

export default function PanelLayout() {
  const router = useRouter();
  useEffect(() => {
    if (!getToken()) router.replace("/login");
  }, [router]);

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
