import { Outlet } from "react-router-dom";
import RouterLink from "@/compat/link";
import { Rocket } from "@carbon/icons-react";
import "../(panel)/_batch-a.scss";

export default function AuthLayout() {
  return (
    <div className="gisila-auth">
      <aside className="gisila-auth__aside">
        <RouterLink href="/login" className="gisila-brand">
          <Rocket size={20} />
          <span>gisila panel</span>
        </RouterLink>
        <blockquote className="gisila-auth__quote">
          "We replaced a $40/mo Heroku bill with a $5 VPS running gisila. 28 apps,
          one box, zero containers, identical DX."
          <footer className="gisila-auth__quote-source">
            — Self-hosters everywhere (hopefully)
          </footer>
        </blockquote>
      </aside>
      <div className="gisila-auth__main">
        <div className="gisila-auth__panel">
          <Outlet />
        </div>
      </div>
    </div>
  );
}
