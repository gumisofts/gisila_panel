import { Suspense } from "react";
import { Navigate, Outlet, useLocation } from "react-router-dom";
import Link from "@/compat/link";
import {
  Content,
  Loading,
  Header,
  HeaderContainer,
  HeaderMenuButton,
  HeaderName,
  SkipToContent,
} from "@carbon/react";
import { ErrorBoundary } from "@/components/error-state";
import { PanelSideNav } from "@/components/sidebar";
import { PanelHeaderActions } from "@/components/topbar";
import { getToken } from "@/lib/api";

export default function PanelLayout() {
  const { pathname } = useLocation();
  // Guard synchronously during render so logged-out users are redirected before
  // the panel paints (no flash), and the protected API calls inside child pages
  // never fire without a token.
  if (!getToken()) return <Navigate to="/login" replace />;

  // HeaderContainer owns the side-nav expansion state, which the header's menu
  // button and the nav itself both need. Carbon nests SideNav inside Header so
  // the two share the shell's stacking and offset rules.
  return (
    <HeaderContainer
      render={({ isSideNavExpanded, onClickSideNavExpand }) => (
        <>
          <Header aria-label="Gisila Panel">
            <SkipToContent />
            <HeaderMenuButton
              aria-label={isSideNavExpanded ? "Close menu" : "Open menu"}
              onClick={onClickSideNavExpand}
              isActive={isSideNavExpanded}
            />
            <HeaderName as={Link} href="/dashboard" prefix="Gisila">
              Panel
            </HeaderName>
            <PanelHeaderActions />
            <PanelSideNav
              expanded={isSideNavExpanded}
              onOverlayClick={onClickSideNavExpand}
            />
          </Header>
          <Content>
            {/* Keyed by path: navigating away clears a crashed page. */}
            <ErrorBoundary key={pathname}>
              {/* Pages are code-split; a failed chunk load (e.g. after a
                  redeploy) lands in the boundary, which offers a reload. */}
              <Suspense fallback={<Loading withOverlay={false} small />}>
                <Outlet />
              </Suspense>
            </ErrorBoundary>
          </Content>
        </>
      )}
    />
  );
}
