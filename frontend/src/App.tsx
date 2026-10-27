import { lazy } from "react";
import { BrowserRouter, Navigate, Routes, Route, useParams } from "react-router-dom";
import { ThemeProvider } from "next-themes";
import { Toaster } from "@/lib/toast";
import { CarbonTheme } from "@/components/carbon-theme";
import { ConfirmDialogHost } from "@/components/confirm-dialog";
import { NotFoundPage } from "@/components/error-state";

import LandingPage from "../app/page";
import AuthLayout from "../app/(auth)/layout";
import LoginPage from "../app/(auth)/login/page";
import PanelLayout from "../app/(panel)/layout";

// Pages load on first visit; the shell and sign-in stay in the main bundle.
const DashboardPage = lazy(() => import("../app/(panel)/dashboard/page"));
const ProjectsPage = lazy(() => import("../app/(panel)/projects/page"));
const AppsPage = lazy(() => import("../app/(panel)/apps/page"));
const NewAppPage = lazy(() => import("../app/(panel)/apps/new/page"));
const AppDetailPage = lazy(() => import("../app/(panel)/apps/[id]/page"));
const DomainsPage = lazy(() => import("../app/(panel)/domains/page"));
const ApplicationsPage = lazy(() => import("../app/(panel)/applications/page"));
const ApplicationDetailPage = lazy(() => import("../app/(panel)/applications/[id]/page"));
const ServicesPage = lazy(() => import("../app/(panel)/services/page"));
const ServiceDetailPage = lazy(() => import("../app/(panel)/services/[id]/page"));
const DatabasesPage = lazy(() => import("../app/(panel)/databases/page"));
const InstancePage = lazy(() => import("../app/(panel)/databases/[id]/page"));
const MongoInstancePage = lazy(() => import("../app/(panel)/databases/mongo/[id]/page"));
const StoragePage = lazy(() => import("../app/(panel)/storage/page"));
const MailPage = lazy(() => import("../app/(panel)/mail/page"));
const ActivityPage = lazy(() => import("../app/(panel)/activity/page"));
const NotificationsPage = lazy(() => import("../app/(panel)/notifications/page"));
const TeamsPage = lazy(() => import("../app/(panel)/teams/page"));
const SettingsPage = lazy(() => import("../app/(panel)/settings/page"));
const TokensPage = lazy(() => import("../app/(panel)/settings/tokens/page"));
const SshKeysPage = lazy(() => import("../app/(panel)/settings/ssh-keys/page"));
const UsersPage = lazy(() => import("../app/(panel)/settings/users/page"));
const NotificationSettingsPage = lazy(() => import("../app/(panel)/settings/notifications/page"));

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
        storageKey="gisila-theme"
      >
        <CarbonTheme>
        <Routes>
          <Route path="/" element={<LandingPage />} />

          <Route element={<AuthLayout />}>
            <Route path="/login" element={<LoginPage />} />
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
            <Route path="/notifications" element={<NotificationsPage />} />
            <Route path="/teams" element={<TeamsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/settings/tokens" element={<TokensPage />} />
            <Route path="/settings/ssh-keys" element={<SshKeysPage />} />
            <Route path="/settings/users" element={<UsersPage />} />
            <Route path="/settings/notifications" element={<NotificationSettingsPage />} />
            <Route path="*" element={<NotFoundPage />} />
          </Route>
        </Routes>
        <Toaster />
        <ConfirmDialogHost />
        </CarbonTheme>
      </ThemeProvider>
    </BrowserRouter>
  );
}
