"use client";

import * as React from "react";
import {
  Search,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader,
  Badge
} from "@noxera/ui";
import { useSearchParams } from "next/navigation";
import { errMsg } from "@/lib/errors";
import MetaViewer from "@/components/common/MetaViewer";
import { listAudit, type AuditItem } from "@/lib/api";

export default function AuditLogsPage() {
  const sp = useSearchParams();

  const [q, setQ] = React.useState("");
  const [tenantId, setTenantId] = React.useState(sp.get("tenantId") || "");
  const [action, setAction] = React.useState("");

  const [page, setPage] = React.useState(1);
  const pageSize = 20;

  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [items, setItems] = React.useState<AuditItem[]>([]);
  const [total, setTotal] = React.useState(0);

  const load = React.useCallback(async (nextPage: number) => {
    setLoading(true);
    setError(null);
    try {
      const res = await listAudit({
        q: q.trim() || undefined,
        tenantId: tenantId.trim() || undefined,
        action: action.trim() || undefined,
        page: nextPage,
        pageSize,
      });
      setItems(res.items);
      setTotal(res.total);
    } catch (e: unknown) {
      setError(errMsg(e));
    } finally {
      setLoading(false);
    }
  }, [q, tenantId, action]);

  React.useEffect(() => {
    void load(page);
  }, [page, load]);

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  async function onApply() {
    setPage(1);
    await load(1);
  }

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Audit Logs"
        subtitle="Track admin actions (status changes, access control, etc.)."
        right={<Badge variant="outline">Sprint 0</Badge>}
      />

      <Card>
        <CardHeader>
          <CardTitle>Filters</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <Label>Search</Label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 opacity-60" />
                <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Action, entity, actor…" className="pl-9" />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Tenant ID</Label>
              <Input value={tenantId} onChange={(e) => setTenantId(e.target.value)} placeholder="e.g. tnt_001" />
            </div>

            <div className="space-y-2">
              <Label>Action</Label>
              <Input value={action} onChange={(e) => setAction(e.target.value)} placeholder='e.g. "TENANT_STATUS_CHANGED"' />
            </div>
          </div>

          <div className="mt-4 flex gap-2">
            <Button variant="outline" onClick={() => void onApply()}>Apply</Button>
            <Button
              variant="secondary"
              onClick={() => {
                setQ("");
                setTenantId("");
                setAction("");
                setPage(1);
                setTimeout(() => void load(1), 0);
              }}
            >
              Reset
            </Button>
          </div>

          {error ? (
            <div className="mt-4 rounded-xl border border-border/70 bg-rose-500/10 p-3 text-sm">
              <div className="font-semibold">Couldn’t load audit logs</div>
              <div className="mt-1 text-muted-foreground">{error}</div>
              <div className="mt-3">
                <Button onClick={() => void load(page)}>Retry</Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <div className="space-y-3">
        {loading ? (
          <Card><CardContent className="pt-4 text-sm text-muted-foreground">Loading…</CardContent></Card>
        ) : items.length === 0 ? (
          <Card><CardContent className="pt-4 text-sm text-muted-foreground">No audit entries match filters.</CardContent></Card>
        ) : (
          items.map((a) => (
            <Card key={a.id} className="overflow-hidden">
              <CardContent className="pt-4 space-y-2">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="text-sm font-extrabold">{a.action}</div>
                  <div className="text-xs text-muted-foreground">{new Date(a.createdAt).toLocaleString()}</div>
                </div>

                <div className="text-xs text-muted-foreground">
                  Tenant: {a.tenant ? `${a.tenant.name} (${a.tenant.id})` : "—"} • Actor: {a.actor?.email || a.actorType}
                </div>

                <div className="flex flex-wrap gap-2 text-xs">
                  <Badge variant="outline">{a.entityType}</Badge>
                  {a.entityId ? <Badge variant="outline">{a.entityId}</Badge> : null}
                  <Badge variant={a.success ? "success" : "danger"}>{a.success ? "Success" : "Failed"}</Badge>
                </div>

                {a.metadata ? <MetaViewer title="Metadata" value={a.metadata} /> : null}
              </CardContent>
            </Card>
          ))
        )}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground">
          Page {page} of {totalPages} • Total {total}
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
