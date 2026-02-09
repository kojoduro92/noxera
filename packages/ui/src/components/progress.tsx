import * as React from "react";
import { cn } from "../lib/cn";

export function Progress({
  value,
  max = 100,
  className
}: {
  value: number;
  max?: number;
  className?: string;
}) {
  const pct = max <= 0 ? 0 : Math.max(0, Math.min(100, (value / max) * 100));
  return (
    <div className={cn("h-2 w-full rounded-full bg-muted/70 overflow-hidden", className)}>
      <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${pct}%` }} />
    </div>
  );
}
