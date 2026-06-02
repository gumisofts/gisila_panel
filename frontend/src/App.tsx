import { BrowserRouter, Routes, Route } from "react-router-dom";
import { ThemeProvider } from "next-themes";
import { Toaster } from "sonner";

import LandingPage from "../app/page";
import AuthLayout from "../app/(auth)/layout";
import LoginPage from "../app/(auth)/login/page";
import PanelLayout from "../app/(panel)/layout";
import DashboardPage from "../app/(panel)/dashboard/page";
import ProjectsPage from "../app/(panel)/projects/page";
import AppsPage from "../app/(panel)/apps/page";
import NewAppPage from "../app/(panel)/apps/new/page";
import AppDetailPage from "../app/(panel)/apps/[id]/page";
import DomainsPage from "../app/(panel)/domains/page";
import ServicesPage from "../app/(panel)/services/page";
import ServiceDetailPage from "../app/(panel)/services/[id]/page";
import DatabasesPage from "../app/(panel)/databases/page";
import InstancePage from "../app/(panel)/databases/[id]/page";
import MailPage from "../app/(panel)/mail/page";
import ActivityPage from "../app/(panel)/activity/page";
import TeamsPage from "../app/(panel)/teams/page";
import SettingsPage from "../app/(panel)/settings/page";
import TokensPage from "../app/(panel)/settings/tokens/page";
import SshKeysPage from "../app/(panel)/settings/ssh-keys/page";
import UsersPage from "../app/(panel)/settings/users/page";

export default function App() {
  return (
    <BrowserRouter>
      <ThemeProvider
        attribute="class"
        defaultTheme="system"
        enableSystem
        disableTransitionOnChange
      >
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
            <Route path="/services" element={<ServicesPage />} />
            <Route path="/services/:id" element={<ServiceDetailPage />} />
            <Route path="/databases" element={<DatabasesPage />} />
            <Route path="/databases/:id" element={<InstancePage />} />
            <Route path="/mail" element={<MailPage />} />
            <Route path="/activity" element={<ActivityPage />} />
            <Route path="/teams" element={<TeamsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/settings/tokens" element={<TokensPage />} />
            <Route path="/settings/ssh-keys" element={<SshKeysPage />} />
            <Route path="/settings/users" element={<UsersPage />} />
          </Route>
        </Routes>
        <Toaster position="bottom-right" richColors />
      </ThemeProvider>
    </BrowserRouter>
  );
}
