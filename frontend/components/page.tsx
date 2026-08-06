import type { ReactNode } from "react";

/// Shared page frame. Carbon ships a grid but no opinion on page chrome, and
/// with two dozen routes it is worth having one place that decides width,
/// padding and heading rhythm rather than repeating spacing tokens per page.
export function Page({ children }: { children: ReactNode }) {
  return <div className="gisila-page">{children}</div>;
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="gisila-page__header">
      <div className="gisila-page__heading">
        <h1 className="gisila-page__title">{title}</h1>
        {description && <p className="gisila-page__description">{description}</p>}
      </div>
      {actions && <div className="gisila-page__actions">{actions}</div>}
    </header>
  );
}

/// Vertical rhythm between the major blocks of a page.
export function PageSection({
  title,
  description,
  actions,
  children,
}: {
  title?: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="gisila-section">
      {(title || actions) && (
        <div className="gisila-section__header">
          <div>
            {title && <h2 className="gisila-section__title">{title}</h2>}
            {description && (
              <p className="gisila-section__description">{description}</p>
            )}
          </div>
          {actions && <div className="gisila-section__actions">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}
