set -euo pipefail

APP_ROOT="apps/web-superadmin"

# Decide which app dir Next should use: prefer src/app if it exists (recommended)
if [ -d "$APP_ROOT/src/app" ]; then
  TARGET="$APP_ROOT/src/app"
  OTHER="$APP_ROOT/app"
else
  TARGET="$APP_ROOT/app"
  OTHER="$APP_ROOT/src/app"
fi

echo "✅ Using TARGET app dir: $TARGET"

# If both exist, move the non-target aside (backup) to avoid Next ambiguity
if [ -d "$OTHER" ]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  mv "$OTHER" "${OTHER}_backup_${TS}"
  echo "✅ Moved ambiguous app dir aside: $OTHER -> ${OTHER}_backup_${TS}"
fi

# Ensure Super Admin group routes exist in TARGET
mkdir -p "$TARGET/(sa)/churches/[tenantId]"

cat > "$TARGET/(sa)/page.tsx" <<'TSX'
import { redirect } from "next/navigation";

export default function SuperAdminHome() {
  redirect("/churches");
}
TSX

cat > "$TARGET/(sa)/churches/page.tsx" <<'TSX'
import ChurchDirectoryClient from "./ui";

export default function ChurchesPage() {
  return <ChurchDirectoryClient />;
}
TSX

# If ui.tsx is missing, create a minimal one (prevents 404/compile issues)
if [ ! -f "$TARGET/(sa)/churches/ui.tsx" ]; then
  cat > "$TARGET/(sa)/churches/ui.tsx" <<'TSX'
"use client";

import * as React from "react";
import { SectionHeader, Card, CardContent } from "@noxera/ui";

export default function ChurchDirectoryClient() {
  return (
    <div className="space-y-5">
      <SectionHeader title="Church Directory" subtitle="(UI file was missing, now restored.)" />
      <Card><CardContent className="text-sm text-muted-foreground">
        Next step: restore the full directory UI from our patch.
      </CardContent></Card>
    </div>
  );
}
TSX
  echo "✅ Restored missing ui.tsx"
fi

cat > "$TARGET/(sa)/churches/[tenantId]/page.tsx" <<'TSX'
import Link from "next/link";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@noxera/ui";

export default async function TenantView({ params }: { params: Promise<{ tenantId: string }> }) {
  const { tenantId } = await params;

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-4">
        <div>
          <div className="text-sm text-muted-foreground">Tenant</div>
          <h1 className="text-xl font-semibold tracking-tight">{tenantId}</h1>
        </div>
        <Link href="/churches">
          <Button variant="outline">Back to directory</Button>
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Tenant Overview</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Sprint 0 placeholder (API wiring comes next).
        </CardContent>
      </Card>
    </div>
  );
}
TSX

echo "🎉 Super Admin routes ensured in: $TARGET"
