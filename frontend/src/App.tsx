import { BrowserRouter, Navigate, Routes, Route, useParams } from "react-router-dom";
import { ThemeProvider } from "next-themes";
import { Toaster } from "@/lib/toast";

import LandingPage from "../app/page";
import AuthLayout from "../app/(auth)/layout";
import LoginPage from "../app/(auth)/login/page";
import RegisterPage from "../app/(auth)/register/page";
import PanelLayout from "../app/(panel)/layout";
import DashboardPage from "../app/(panel)/dashboard/page";
import ProjectsPage from "../app/(panel)/projects/page";
import AppsPage from "../app/(panel)/apps/page";
import NewAppPage from "../app/(panel)/apps/new/page";
import AppDetailPage from "../app/(panel)/apps/[id]/page";
import DomainsPage from "../app/(panel)/domains/page";
import ApplicationsPage from "../app/(panel)/applications/page";
import ApplicationDetailPage from "../app/(panel)/applications/[id]/page";
import ServicesPage from "../app/(panel)/services/page";
import ServiceDetailPage from "../app/(panel)/services/[id]/page";
import DatabasesPage from "../app/(panel)/databases/page";
import InstancePage from "../app/(panel)/databases/[id]/page";
import MongoInstancePage from "../app/(panel)/databases/mongo/[id]/page";
import StoragePage from "../app/(panel)/storage/page";
import MailPage from "../app/(panel)/mail/page";
import ActivityPage from "../app/(panel)/activity/page";
import TeamsPage from "../app/(panel)/teams/page";
import SettingsPage from "../app/(panel)/settings/page";
import TokensPage from "../app/(panel)/settings/tokens/page";
import SshKeysPage from "../app/(panel)/settings/ssh-keys/page";
import UsersPage from "../app/(panel)/settings/users/page";

function LegacyRuntimeRedirect() {
  const { id } = useParams<{ id: string }>();
  return <Navigate to={`/runtimes/${id}`} replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <ThemeProvider
        attribute="class"
        // Emit Carbon's theme-zone classes straight onto <html> instead of
        // next-themes' own light/dark names. Carbon scopes every --cds-* token
        // to these classes, so putting them at the root themes the document
        // background too, which a nested <Theme> wrapper would not reach.
        value={{ light: "cds--white", dark: "cds--g100" }}
        defaultTheme="system"
        enableSystem
        disableTransitionOnChange
      >
        <Routes>
          <Route path="/" element={<LandingPage />} />

          <Route element={<AuthLayout />}>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<RegisterPage />} />
          </Route>

          <Route element={<PanelLayout />}>
            <Route path="/dashboard" element={<DashboardPage />} />
            <Route path="/projects" element={<ProjectsPage />} />
            <Route path="/apps" element={<AppsPage />} />
            <Route path="/apps/new" element={<NewAppPage />} />
            <Route path="/apps/:id" element={<AppDetailPage />} />
            <Route path="/domains" element={<DomainsPage />} />
            <Route path="/runtimes" element={<ApplicationsPage />} />
            <Route path="/runtimes/:id" element={<ApplicationDetailPage />} />
            <Route
              path="/runtime"
              element={<Navigate to="/runtimes" replace />}
            />
            <Route
              path="/runtime/:id"
              element={<LegacyRuntimeRedirect />}
            />
            <Route
              path="/applications"
              element={<Navigate to="/runtimes" replace />}
            />
            <Route
              path="/applications/:id"
              element={<LegacyRuntimeRedirect />}
            />
            <Route path="/services" element={<ServicesPage />} />
            <Route path="/services/:id" element={<ServiceDetailPage />} />
            <Route path="/databases" element={<DatabasesPage />} />
            <Route path="/databases/:id" element={<InstancePage />} />
            {/* Not shadowed by /databases/:id above: that pattern is a single
                segment, and react-router ranks the static "mongo" segment
                over a param regardless of declaration order. */}
            <Route path="/databases/mongo/:id" element={<MongoInstancePage />} />
            <Route path="/storage" element={<StoragePage />} />
            <Route path="/mail" element={<MailPage />} />
            <Route path="/activity" element={<ActivityPage />} />
            <Route path="/teams" element={<TeamsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/settings/tokens" element={<TokensPage />} />
            <Route path="/settings/ssh-keys" element={<SshKeysPage />} />
            <Route path="/settings/users" element={<UsersPage />} />
          </Route>
        </Routes>
        <Toaster />
      </ThemeProvider>
    </BrowserRouter>
  );
}
