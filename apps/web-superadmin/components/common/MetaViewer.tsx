"use client";

import * as React from "react";

function pretty(v: unknown): string {
  if (typeof v === "string") return v;
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return String(v);
  }
}

export default function MetaViewer(props: { title?: string; value: unknown }) {
  const { title = "Metadata", value } = props;
  const [open, setOpen] = React.useState(false);

  return (
    <div className="rounded-2xl border border-border/70 bg-muted/20 p-3">
      <button
        type="button"
        onClick={() => setOpen((s) => !s)}
        className="flex w-full items-center justify-between gap-3 text-left"
      >
        <div className="text-xs font-semibold">{title}</div>
        <div className="text-xs text-muted-foreground">{open ? "Hide" : "Show"}</div>
      </button>

      {open ? (
        <pre className="mt-3 max-h-80 overflow-auto rounded-xl border border-border/70 bg-background/60 p-3 text-xs">
          {pretty(value)}
        </pre>
      ) : null}
    </div>
  );
}
