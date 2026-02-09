import * as React from "react";
import { cn } from "../lib/cn";

export type BadgeVariant = "default" | "success" | "warning" | "danger" | "outline";

const variants: Record<BadgeVariant, string> = {
  default: "bg-muted text-foreground",
  success: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border border-emerald-500/20",
  warning: "bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/20",
  danger: "bg-rose-500/15 text-rose-800 dark:text-rose-300 border border-rose-500/20",
  outline: "border border-border/70 text-foreground bg-background/40"
};

export function Badge({
  className,
  variant = "default",
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { variant?: BadgeVariant }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold",
        variants[variant],
        className
      )}
      {...props}
    />
  );
}
