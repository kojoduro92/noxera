set -euo pipefail

P="apps/web-superadmin/app/(sa)/churches/page.tsx"
mkdir -p "apps/web-superadmin/app/(sa)/churches"

cat > "$P" <<'TSX'
"use client";

import * as React from "react";
import Link from "next/link";
import {
  Search,
  Eye,
  Ban,
  PlayCircle,
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader
} from "@noxera/ui";
import { mockTenants, type TenantRow, type TenantStatus } from "@/lib/mock/tenants";

type StatusFilter = "All" | TenantStatus;

function formatRelative(iso: string) {
  const d = new Date(iso).getTime();
  const diff = Date.now() - d;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 48) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

function statusBadgeVariant(status: TenantStatus) {
  switch (status) {
    case "Active":
      return "success";
    case "Trial":
      return "default";
    case "Past Due":
      return "warning";
    case "Suspended":
    case "Cancelled":
      return "danger";
    default:
      return "outline";
  }
}

export default function ChurchesPage() {
  const [rows, setRows] = React.useState<TenantRow[]>(mockTenants);
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState<StatusFilter>("All");

  const filtered = React.useMemo(() => {
    const query = q.trim().toLowerCase();
    return rows.filter((r) => {
      const okQ =
        !query ||
        r.name.toLowerCase().includes(query) ||
        r.id.toLowerCase().includes(query);
      const okS = status === "All" || r.status === status;
      return okQ && okS;
    });
  }, [rows, q, status]);

  function toggleSuspend(id: string) {
    setRows((prev) =>
      prev.map((t) => {
        if (t.id !== id) return t;
        if (t.status === "Suspended") return { ...t, status: "Active" };
        return { ...t, status: "Suspended" };
      })
    );
  }

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Church Directory"
        subtitle="Search churches, view status/plan/usage, and suspend/resume access."
        right={
          <div className="flex items-center gap-2">
            <Button variant="outline">Export</Button>
            <Button>Create tenant</Button>
          </div>
        }
      />

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Filters</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <Label htmlFor="q">Search</Label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 opacity-60" />
                <Input
                  id="q"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Name or tenant ID…"
                  className="pl-9"
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="status">Status</Label>
              <select
                id="status"
                value={status}
                onChange={(e) => setStatus(e.target.value as StatusFilter)}
                className="h-10 w-full rounded-xl border border-border bg-background px-3 text-sm"
              >
                <option value="All">All</option>
                <option value="Trial">Trial</option>
                <option value="Active">Active</option>
                <option value="Past Due">Past Due</option>
                <option value="Suspended">Suspended</option>
                <option value="Cancelled">Cancelled</option>
              </select>
            </div>

            <div className="space-y-2">
              <Label>Results</Label>
              <div className="flex h-10 items-center rounded-xl border border-border bg-muted/30 px-3 text-sm">
                {filtered.length} church{filtered.length === 1 ? "" : "es"}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="overflow-hidden rounded-2xl border border-border">
        <div className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] bg-muted/40 px-4 py-3 text-xs font-semibold uppercase tracking-wide">
          <div>Church</div>
          <div>Plan</div>
          <div>Status</div>
          <div>Usage</div>
          <div className="text-right">Actions</div>
        </div>

        {filtered.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">
            No churches match your filters.
          </div>
        ) : (
          filtered.map((t) => (
            <div
              key={t.id}
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center border-t border-border px-4 py-4"
            >
              <div>
                <div className="font-medium">{t.name}</div>
                <div className="text-xs text-muted-foreground">
                  {t.id} • last activity {formatRelative(t.lastActivityISO)}
                </div>
              </div>

              <div className="text-sm">{t.plan}</div>

              <div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="text-sm">
                {t.seatsUsed}/{t.seatsLimit} seats
              </div>

              <div className="flex items-center justify-end gap-2">
                <Link href={`/churches/${t.id}`} className="inline-flex">
                  <Button variant="outline" size="sm">
                    <Eye className="h-4 w-4" />
                    View
                  </Button>
                </Link>

                {t.status === "Suspended" ? (
                  <Button variant="secondary" size="sm" onClick={() => toggleSuspend(t.id)}>
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button variant="destructive" size="sm" onClick={() => toggleSuspend(t.id)}>
                    <Ban className="h-4 w-4" />
                    Suspend
                  </Button>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
TSX

# Optional: keep ui.tsx if you want, but it's no longer needed
# rm -f "apps/web-superadmin/app/(sa)/churches/ui.tsx" || true

echo "✅ Fixed: removed ./ui import by inlining client page."
