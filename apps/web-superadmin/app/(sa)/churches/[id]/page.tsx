"use client";

import * as React from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Progress,
  SectionHeader,
  ChevronLeft,
  Ban,
  PlayCircle
} from "@noxera/ui";
import { errMsg } from "@/lib/errors";
import { getTenant, setTenantStatus, listAudit, type TenantDetailResponse, type AuditListResponse, type TenantStatus } from "@/lib/api";

function badgeVariant(s: TenantStatus) {
  switch (s) {
    case "ACTIVE": return "success";
    case "TRIAL": return "default";
    case "PAST_DUE": return "warning";
    case "SUSPENDED":
    case "CANCELLED": return "danger";
    default: return "outline";
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function flatten(obj: unknown, prefix = ""): Array<{ key: string; value: unknown }> {
  if (!isRecord(obj)) return [{ key: prefix || "value", value: obj }];

  const out: Array<{ key: string; value: unknown }> = [];
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    const key = prefix ? `${prefix}.${k}` : k;
    if (isRecord(v)) out.push(...flatten(v, key));
    else out.push({ key, value: v });
  }
  return out;
}

export default function TenantDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string;
  const router = useRouter();

  const [loading, setLoading] = React.useState(true);
  const [saving, setSaving] = React.useState(false);
  const [err, setErr] = React.useState<string | null>(null);
  const [tenant, setTenant] = React.useState<TenantDetailResponse | null>(null);
  const [audit, setAudit] = React.useState<AuditListResponse | null>(null);

  const load = React.useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      const t = await getTenant(id);
      setTenant(t);

      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: unknown) {
      setErr(errMsg(e));
    } finally {
      setLoading(false);
    }
  }, [id]);

  React.useEffect(() => {
    void load();
  }, [load]);

  async function changeStatus(next: TenantStatus) {
    if (!tenant) return;
    setSaving(true);
    const prev = tenant.status;
    setTenant({ ...tenant, status: next });
    try {
      await setTenantStatus(id, next);
      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: unknown) {
      setTenant({ ...tenant, status: prev });
      alert(errMsg(e));
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <div className="text-sm text-muted-foreground">Loading…</div>;

  if (err) {
    return (
      <div className="space-y-3">
        <div className="text-sm font-semibold">Couldn’t load tenant</div>
        <div className="text-sm text-muted-foreground">{err}</div>
        <div className="flex gap-2">
          <Button onClick={() => void load()}>Retry</Button>
          <Button variant="outline" onClick={() => router.push("/churches")}>Back</Button>
        </div>
      </div>
    );
  }

  if (!tenant) return null;

  const features = flatten(tenant.features?.effectiveFeatures ?? {});
  const seatsUsed = tenant.seatsUsed ?? 0;
  const seatsLimit = tenant.seatsLimit ?? 0;

  return (
    <div className="space-y-5">
      <SectionHeader
        title={tenant.name}
        subtitle={`${tenant.id} • ${tenant.slug}`}
        right={
          <div className="flex items-center gap-2">
            <Link href="/churches">
              <Button variant="outline">
                <ChevronLeft className="h-4 w-4" />
                Back
              </Button>
            </Link>
            <Badge variant={badgeVariant(tenant.status)}>{tenant.status}</Badge>
          </div>
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Plan</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            <div className="text-sm font-semibold">{tenant.planTier}</div>
            <div className="text-xs text-muted-foreground">Seats</div>
            <div className="text-sm">{seatsUsed}/{seatsLimit}</div>
            <Progress value={seatsUsed} max={seatsLimit} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Status</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="text-sm">Current: <span className="font-semibold">{tenant.status}</span></div>
            <div className="flex flex-wrap gap-2">
              {tenant.status === "SUSPENDED" ? (
                <Button disabled={saving} variant="secondary" onClick={() => void changeStatus("ACTIVE")}>
                  <PlayCircle className="h-4 w-4" />
                  Resume
                </Button>
              ) : (
                <Button disabled={saving} variant="destructive" onClick={() => void changeStatus("SUSPENDED")}>
                  <Ban className="h-4 w-4" />
                  Suspend
                </Button>
              )}
              <Button disabled={saving} variant="outline" onClick={() => void changeStatus("PAST_DUE")}>Mark Past Due</Button>
              <Button disabled={saving} variant="outline" onClick={() => void changeStatus("CANCELLED")}>Cancel</Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Feature Gates</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            <div className="text-xs text-muted-foreground">Effective (Plan + Overrides)</div>
            <div className="grid gap-2">
              {features.slice(0, 10).map((f) => (
                <div
                  key={f.key}
                  className="flex items-center justify-between gap-3 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs"
                >
                  <div className="font-semibold">{f.key}</div>
                  <div className="text-muted-foreground">{String(f.value)}</div>
                </div>
              ))}
              {features.length > 10 ? (
                <div className="text-xs text-muted-foreground">+ {features.length - 10} more… (we’ll expand in Sprint 1)</div>
              ) : null}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent Audit Logs</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {audit?.items?.length ? (
            audit.items.map((a) => (
              <div
                key={a.id}
                className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs"
              >
                <div className="font-semibold">{a.action}</div>
                <div className="text-muted-foreground">{new Date(a.createdAt).toLocaleString()}</div>
              </div>
            ))
          ) : (
            <div className="text-sm text-muted-foreground">No audit entries yet.</div>
          )}
          <div className="pt-2">
            <Link href={`/audit-logs?tenantId=${encodeURIComponent(id)}`}>
              <Button variant="outline">View all audit logs</Button>
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
