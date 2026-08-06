"use client";

import { Navigate } from "react-router-dom";
import { getToken } from "@/lib/api";

/** Root sends visitors to the dashboard when signed in, otherwise to login. */
export default function RootPage() {
  if (getToken()) return <Navigate to="/dashboard" replace />;
  return <Navigate to="/login" replace />;
}
