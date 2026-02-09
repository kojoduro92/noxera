"use client";

import * as React from "react";
import Link from "next/link";
import {
  Search,
  Eye,
  Ban,
  PlayCircle,
  Sparkles,
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader,
  Progress
} from "@noxera/ui";
import { errMsg } from "@/lib/errors";
import { listTenants, setTenantStatus, type TenantListItem, type TenantStatus } from "@/lib/api";

type StatusFilter = "ALL" | TenantStatus;

function statusBadgeVariant(status: TenantStatus) {
  switch (status) {
    case "ACTIVE":
      return "success";
    case "TRIAL":
      return "default";
    case "PAST_DUE":
      return "warning";
    case "SUSPENDED":
    case "CANCELLED":
      return "danger";
    default:
      return "outline";
  }
}

function StatCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="overflow-hidden">
      <div className="h-1 w-full bg-gradient-to-r from-[hsl(var(--primary))] via-[hsl(200_95%_55%)] to-[hsl(140_70%_45%)]" />
      <CardContent className="pt-4">
        <div className="text-xs font-semibold text-muted-foreground">{label}</div>
        <div className="mt-1 text-2xl font-extrabold tracking-tight">{value}</div>
        {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
      </CardContent>
    </Card>
  );
}

function SkeletonRow() {
  return (
    <div className="animate-pulse border-t border-border/70 px-4 py-4">
      <div className="h-4 w-56 rounded bg-muted" />
      <div className="mt-2 h-3 w-72 rounded bg-muted/70" />
    </div>
  );
}

export default function ChurchesPage() {
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState<StatusFilter>("ALL");
  const [page, setPage] = React.useState(1);
  const pageSize = 20;

  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [data, setData] = React.useState<{ total: number; items: TenantListItem[] }>({ total: 0, items: [] });

  const fetchTenants = React.useCallback(
    async (nextPage: number) => {
      setLoading(true);
      setError(null);
      try {
        const res = await listTenants({
          q: q.trim() || undefined,
          status: status === "ALL" ? undefined : status,
          page: nextPage,
          pageSize,
        });
        setData({ total: res.total, items: res.items });
      } catch (e: unknown) {
        setError(errMsg(e));
      } finally {
        setLoading(false);
      }
    },
    [q, status, pageSize]
  );

  React.useEffect(() => {
    fetchTenants(page);
  }, [page, fetchTenants]);

  const stats = React.useMemo(() => {
    const items = data.items;
    const total = data.total;
    const active = items.filter((r) => r.status === "ACTIVE").length;
    const pastDue = items.filter((r) => r.status === "PAST_DUE").length;
    const suspended = items.filter((r) => r.status === "SUSPENDED").length;
    return { total, active, pastDue, suspended };
  }, [data]);

  async function onApplyFilters() {
    setPage(1);
    await fetchTenants(1);
  }

  async function toggleSuspend(t: TenantListItem) {
    const next: TenantStatus = t.status === "SUSPENDED" ? "ACTIVE" : "SUSPENDED";
    try {
      // optimistic
      setData((prev) => ({
        ...prev,
        items: prev.items.map((x) => (x.id === t.id ? { ...x, status: next } : x)),
      }));
      await setTenantStatus(t.id, next);
    } catch (e: unknown) {
      // revert
      setData((prev) => ({
        ...prev,
        items: prev.items.map((x) => (x.id === t.id ? { ...x, status: t.status } : x)),
      }));
      alert(errMsg(e));
    }
  }

  const totalPages = Math.max(1, Math.ceil(data.total / pageSize));

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Church Directory"
        subtitle="Real-time tenants list (API). Suspend/resume access with audit logging."
        right={
          <div className="flex items-center gap-2">
            <Button variant="outline">Export</Button>
            <Link href="/churches/new">
              <Button>
                <Sparkles className="h-4 w-4" />
                Create tenant
              </Button>
            </Link>
          </div>
        }
      />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total churches" value={`${stats.total}`} />
        <StatCard label="Active (this page)" value={`${stats.active}`} />
        <StatCard label="Past Due (this page)" value={`${stats.pastDue}`} />
        <StatCard label="Suspended (this page)" value={`${stats.suspended}`} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Filters</CardTitle>
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
                  placeholder="Name, slug, or tenant ID…"
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
                className="h-10 w-full rounded-xl border border-border/70 bg-background/60 px-3 text-sm backdrop-blur"
              >
                <option value="ALL">All</option>
                <option value="TRIAL">Trial</option>
                <option value="ACTIVE">Active</option>
                <option value="PAST_DUE">Past Due</option>
                <option value="SUSPENDED">Suspended</option>
                <option value="CANCELLED">Cancelled</option>
              </select>
            </div>

            <div className="space-y-2">
              <Label>Actions</Label>
              <div className="flex gap-2">
                <Button variant="outline" className="flex-1" onClick={onApplyFilters}>
                  Apply
                </Button>
                <Button
                  variant="secondary"
                  className="flex-1"
                  onClick={() => {
                    setQ("");
                    setStatus("ALL");
                    setPage(1);
                    setTimeout(() => void fetchTenants(1), 0);
                  }}
                >
                  Reset
                </Button>
              </div>
            </div>
          </div>

          {error ? (
            <div className="mt-4 rounded-xl border border-border/70 bg-rose-500/10 p-3 text-sm">
              <div className="font-semibold">Couldn’t load tenants</div>
              <div className="mt-1 text-muted-foreground">{error}</div>
              <div className="mt-3">
                <Button onClick={() => void fetchTenants(page)}>Retry</Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      {/* Desktop table */}
      <div className="hidden md:block overflow-hidden rounded-2xl border border-border/70 bg-card/70 backdrop-blur">
        <div className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] bg-muted/30 px-4 py-3 text-xs font-extrabold uppercase tracking-wide">
          <div>Church</div>
          <div>Plan</div>
          <div>Status</div>
          <div>Usage</div>
          <div className="text-right">Actions</div>
        </div>

        {loading ? (
          <>
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
          </>
        ) : data.items.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">No churches match your filters.</div>
        ) : (
          data.items.map((t) => (
            <div
              key={t.id}
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center border-t border-border/70 px-4 py-4 transition hover:bg-accent/40"
            >
              <div>
                <div className="font-bold">{t.name}</div>
                <div className="text-xs text-muted-foreground">
                  {t.id} • {t.slug}
                </div>
              </div>

              <div className="text-sm font-semibold">{t.planTier}</div>

              <div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="space-y-1">
                <div className="text-sm">
                  {t.seatsUsed}/{t.seatsLimit} seats
                </div>
                <Progress value={t.seatsUsed} max={t.seatsLimit} />
              </div>

              <div className="flex items-center justify-end gap-2">
                <Link href={`/churches/${t.id}`} className="inline-flex">
                  <Button variant="outline" size="sm">
                    <Eye className="h-4 w-4" />
                    View
                  </Button>
                </Link>

                {t.status === "SUSPENDED" ? (
                  <Button variant="secondary" size="sm" onClick={() => void toggleSuspend(t)}>
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button variant="destructive" size="sm" onClick={() => void toggleSuspend(t)}>
                    <Ban className="h-4 w-4" />
                    Suspend
                  </Button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-3">
        {loading ? (
          <>
            <Card><CardContent className="pt-4"><div className="h-4 w-40 rounded bg-muted animate-pulse" /></CardContent></Card>
            <Card><CardContent className="pt-4"><div className="h-4 w-52 rounded bg-muted animate-pulse" /></CardContent></Card>
          </>
        ) : data.items.length === 0 ? (
          <Card>
            <CardContent className="pt-4 text-sm text-muted-foreground">
              No churches match your filters.
            </CardContent>
          </Card>
        ) : (
          data.items.map((t) => (
            <Card key={t.id} className="overflow-hidden">
              <CardContent className="pt-4 space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-base font-extrabold">{t.name}</div>
                    <div className="text-xs text-muted-foreground">{t.id} • {t.slug}</div>
                  </div>
                  <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
                </div>

                <div className="flex items-center justify-between text-sm">
                  <div className="font-semibold">{t.planTier}</div>
                  <div>{t.seatsUsed}/{t.seatsLimit} seats</div>
                </div>

                <Progress value={t.seatsUsed} max={t.seatsLimit} />

                <div className="flex gap-2">
                  <Link href={`/churches/${t.id}`} className="flex-1">
                    <Button variant="outline" className="w-full">
                      <Eye className="h-4 w-4" />
                      View
                    </Button>
                  </Link>

                  {t.status === "SUSPENDED" ? (
                    <Button variant="secondary" className="flex-1" onClick={() => void toggleSuspend(t)}>
                      <PlayCircle className="h-4 w-4" />
                      Resume
                    </Button>
                  ) : (
                    <Button variant="destructive" className="flex-1" onClick={() => void toggleSuspend(t)}>
                      <Ban className="h-4 w-4" />
                      Suspend
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground">
          Page {page} of {totalPages} • Total {data.total}
        </div>
        <div className="flex gap-2">
          <Button variant="outline" disabled={page <= 1 || loading} onClick={() => setPage((p) => Math.max(1, p - 1))}>
            Prev
          </Button>
          <Button variant="outline" disabled={page >= totalPages || loading} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}
