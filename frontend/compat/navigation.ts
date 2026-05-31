/**
 * Drop-in replacements for `next/navigation` hooks using react-router-dom.
 * Only an import-path change is needed in existing pages.
 */
import {
  useNavigate,
  useLocation,
  useParams as useRRParams,
} from "react-router-dom";

export function useRouter() {
  const navigate = useNavigate();
  return {
    push: (path: string) => navigate(path),
    replace: (path: string) => navigate(path, { replace: true }),
    back: () => navigate(-1),
  };
}

export function usePathname(): string {
  return useLocation().pathname;
}

export { useRRParams as useParams };
export { useSearchParams } from "react-router-dom";
