"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { errMsg } from "@/lib/errors";

const API = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:3000";

type CreateTenantResponse = { id: string };

export default function NewChurchClient() {
  const router = useRouter();
  const [name, setName] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [err, setErr] = React.useState<string | null>(null);

  async function devToken(): Promise<string> {
    const r = await fetch(`${API}/auth/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ dev: true }),
    });
    if (!r.ok) throw new Error(await r.text());
    const j = (await r.json()) as { token: string };
    return j.token;
  }

  async function onCreate(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    setBusy(true);
    try {
      const token = await devToken();

      const r = await fetch(`${API}/admin/tenants`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        credentials: "include",
        body: JSON.stringify({ name }),
      });

      if (!r.ok) throw new Error(await r.text());

      const tenant = (await r.json()) as CreateTenantResponse;
      router.push(`/churches/${tenant.id}`);
    } catch (e: unknown) {
      setErr(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-xl p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Create Church</h1>
        <p className="text-sm text-muted-foreground">Creates a new tenant (church workspace).</p>
      </div>

      <form onSubmit={onCreate} className="space-y-4">
        <div className="space-y-2">
          <label className="text-sm font-medium">Church name</label>
          <input
            className="w-full rounded-xl border px-3 py-2 bg-transparent"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. New Hope Chapel"
          />
        </div>

        {err ? (
          <div className="rounded-xl border border-rose-300 bg-rose-500/10 p-3 text-sm">
            {err}
          </div>
        ) : null}

        <button
          disabled={busy || !name.trim()}
          className="rounded-xl border px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          {busy ? "Creating..." : "Create"}
        </button>
      </form>
    </div>
  );
}
