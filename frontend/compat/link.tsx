/**
 * Drop-in replacement for `next/link` that uses react-router-dom's Link.
 * Accepts `href` instead of `to` so existing pages need only an import change.
 */
import { Link as RouterLink, type LinkProps as RouterLinkProps } from "react-router-dom";
import type { ReactNode } from "react";

type CompatLinkProps = Omit<RouterLinkProps, "to"> & {
  href: string;
  children?: ReactNode;
};

const Link = ({ href, ...props }: CompatLinkProps) => (
  <RouterLink to={href} {...props} />
);

export default Link;
