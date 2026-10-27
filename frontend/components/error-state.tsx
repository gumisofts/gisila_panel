import { Component, type ErrorInfo, type ReactNode } from "react";
import { ActionableNotification, Button } from "@carbon/react";
import RouterLink from "@/compat/link";
import { Page, PageHeader } from "@/components/page";

function messageOf(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  return "Something went wrong.";
}

/// A failed fetch, shown where the data would be. Without it a failed list
/// request looks exactly like an empty list.
export function ErrorState({
  error,
  onRetry,
  title = "Couldn't load this",
}: {
  error: unknown;
  onRetry?: () => void;
  title?: string;
}) {
  return (
    <ActionableNotification
      kind="error"
      inline
      lowContrast
      hideCloseButton
      title={title}
      subtitle={messageOf(error)}
      actionButtonLabel={onRetry ? "Try again" : ""}
      onActionButtonClick={onRetry}
    />
  );
}

/// Catches a render error in one page so the rest of the panel (header,
/// navigation) keeps working. Give it a `key` that changes on navigation so
/// moving to another page clears the error.
export class ErrorBoundary extends Component<
  { children: ReactNode },
  { error: unknown }
> {
  state = { error: null as unknown };

  static getDerivedStateFromError(error: unknown) {
    return { error };
  }

  componentDidCatch(error: unknown, info: ErrorInfo) {
    console.error("Page crashed", error, info.componentStack);
  }

  render() {
    if (this.state.error == null) return this.props.children;
    return (
      <Page>
        <PageHeader
          title="This page hit an error"
          description="The rest of the panel still works. Reload to try again."
        />
        <ErrorState error={this.state.error} title="Error" />
        <div>
          <Button kind="tertiary" onClick={() => window.location.reload()}>
            Reload
          </Button>
        </div>
      </Page>
    );
  }
}

export function NotFoundPage() {
  return (
    <Page>
      <PageHeader
        title="Page not found"
        description="There's nothing at this address. It may have moved, or the link is wrong."
      />
      <div>
        <Button as={RouterLink} href="/dashboard" kind="tertiary">
          Go to the dashboard
        </Button>
      </div>
    </Page>
  );
}
