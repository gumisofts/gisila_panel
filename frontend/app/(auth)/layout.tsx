import Link from "next/link";
import { Rocket } from "lucide-react";

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="grid min-h-screen lg:grid-cols-2">
      <div className="hidden flex-col justify-between bg-[radial-gradient(circle_at_30%_20%,_rgba(168,85,247,0.25),_transparent_60%)] p-12 lg:flex">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <Rocket className="h-5 w-5 text-primary" />
          gisila panel
        </Link>
        <blockquote className="max-w-md text-pretty text-lg font-medium leading-snug text-foreground/90">
          “We replaced a $40/mo Heroku bill with a $5 VPS running gisila. 28 apps,
          one box, zero containers, identical DX.”
          <footer className="mt-4 text-sm text-muted-foreground">
            — Self-hosters everywhere (hopefully)
          </footer>
        </blockquote>
      </div>
      <div className="flex min-h-screen items-center justify-center p-6">
        <div className="w-full max-w-sm">{children}</div>
      </div>
    </div>
  );
}
