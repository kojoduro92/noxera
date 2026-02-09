import { errMsg } from "@/lib/errors";

function apiBase(): string {
  const env = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "");
  if (env) return env;

  // Keep host consistent so cookies/CORS behave:
  // - If the browser is on 127.0.0.1:3001, call 127.0.0.1:3000
  // - If the browser is on localhost:3001, call localhost:3000
  if (typeof window !== "undefined") {
    const host = window.location.hostname === "127.0.0.1" ? "127.0.0.1" : "localhost";
    const proto = window.location.protocol || "http:";
    return `${proto}//${host}:3000`;
  }

  return "http://localhost:3000";
}

export type TenantStatus = "TRIAL" | "ACTIVE" | "PAST_DUE" | "SUSPENDED" | "CANCELLED";

export type TenantListItem = {
  id: string;
  name: string;
  slug: string;
  status: TenantStatus;
  planTier: string;
  seatsLimit: number;
  seatsUsed: number;
  createdAt: string;
  updatedAt: string;
};

export type TenantListResponse = {
  page: number;
  pageSize: number;
  total: number;
  items: TenantListItem[];
};

export type TenantDetailResponse = TenantListItem & {
  features: {
    planFeatures: unknown;
    overrideFeatures: unknown;
    effectiveFeatures: unknown;
  };
};

export type AuditItem = {
  id: string;
  createdAt: string;
  tenant: { id: string; name: string; slug: string } | null;
  actorType: "USER" | "SYSTEM";
  actor: { id: string; email: string | null; displayName: string | null } | null;
  action: string;
  entityType: string;
  entityId: string | null;
  success: boolean;
  metadata: unknown;
};

export type AuditListResponse = {
  page: number;
  pageSize: number;
  total: number;
  items: AuditItem[];
};

let _didAutoDevSession = false;

async function ensureDevSessionOnce(base: string): Promise<void> {
  if (_didAutoDevSession) return;
  _didAutoDevSession = true;

  await fetch(`${base}/auth/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ dev: true }),
  });
}

async function apiFetch<T>(path: string, init?: RequestInit, retry = true): Promise<T> {
  const base = apiBase();

  const headers = new Headers(init?.headers);
  if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");

  const res = await fetch(`${base}${path}`, {
    ...init,
    headers,
    credentials: "include", // ✅ ALWAYS send cookies
  });

  // Auto dev-session on first 401, then retry once.
  if (res.status === 401 && retry) {
    await ensureDevSessionOnce(base);
    return apiFetch<T>(path, init, false);
  }

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`API ${res.status}: ${txt || res.statusText}`);
  }

  return (await res.json()) as T;
}

export async function listTenants(params: {
  q?: string;
  status?: string;
  page?: number;
  pageSize?: number;
}) {
  const sp = new URLSearchParams();
  if (params.q) sp.set("q", params.q);
  if (params.status) sp.set("status", params.status);
  sp.set("page", String(params.page ?? 1));
  sp.set("pageSize", String(params.pageSize ?? 20));
  const qs = sp.toString();
  return apiFetch<TenantListResponse>(`/admin/tenants${qs ? `?${qs}` : ""}`);
}

export async function getTenant(tenantId: string) {
  return apiFetch<TenantDetailResponse>(`/admin/tenants/${tenantId}`);
}

export async function setTenantStatus(tenantId: string, status: TenantStatus) {
  return apiFetch<{ ok: true; tenantId: string; status: TenantStatus }>(
    `/admin/tenants/${tenantId}/status`,
    {
      method: "PATCH",
      body: JSON.stringify({ status }),
    }
  );
}

export async function listAudit(params: {
  q?: string;
  tenantId?: string;
  action?: string;
  page?: number;
  pageSize?: number;
}) {
  const sp = new URLSearchParams();
  if (params.q) sp.set("q", params.q);
  if (params.tenantId) sp.set("tenantId", params.tenantId);
  if (params.action) sp.set("action", params.action);
  sp.set("page", String(params.page ?? 1));
  sp.set("pageSize", String(params.pageSize ?? 20));
  const qs = sp.toString();
  return apiFetch<AuditListResponse>(`/admin/audit${qs ? `?${qs}` : ""}`);
}

// optional helper if you ever want a safe error string in pages
export function apiErrorMessage(e: unknown): string {
  return errMsg(e);
}
