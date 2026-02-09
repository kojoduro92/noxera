"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { errMsg } from "@/lib/errors";

const API = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:3000";

export default function LoginPage() {
  const router = useRouter();
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function loginDev() {
    setBusy(true);
    setError(null);
    try {
      const r = await fetch(`${API}/auth/session`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ dev: true }),
      });
      if (!r.ok) throw new Error(await r.text());
      router.push("/churches");
    } catch (e: unknown) {
      setError(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-md p-6 space-y-4">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">Super Admin Login</h1>
        <p className="text-sm text-muted-foreground">
          Dev mode creates a local session cookie for Sprint 0/1 testing.
        </p>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-300 bg-rose-500/10 p-3 text-sm">
          {error}
        </div>
      ) : null}

      <button
        disabled={busy}
        onClick={loginDev}
        className="w-full rounded-xl border px-4 py-2 text-sm font-semibold disabled:opacity-50"
      >
        {busy ? "Signing in..." : "Continue (Dev Session)"}
      </button>
    </div>
  );
}
