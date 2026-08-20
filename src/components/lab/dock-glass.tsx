"use client";

import { useRef, type ReactNode } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { cn } from "@/lib/utils";

export function DockGlass({
  title,
  subtitle,
  open,
  onOpenChange,
  children,
  trailing,
}: {
  title: string;
  subtitle?: string;
  open: boolean;
  onOpenChange: (v: boolean) => void;
  children: ReactNode;
  trailing?: ReactNode;
}) {
  const startY = useRef(0);
  const dragging = useRef(false);

  return (
    <div
      className="relative z-20 shrink-0 border-t border-white/15 bg-black/45 shadow-[0_-18px_50px_rgba(0,0,0,0.55)] backdrop-blur-3xl pb-[env(safe-area-inset-bottom)]"
      onPointerDown={(e) => {
        if (!(e.target as HTMLElement).closest("[data-dock-drag]")) return;
        dragging.current = true;
        startY.current = e.clientY;
        (e.currentTarget as HTMLDivElement).setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => {
        if (!dragging.current) return;
        const dy = e.clientY - startY.current;
        if (open && dy > 56) {
          dragging.current = false;
          onOpenChange(false);
        } else if (!open && dy < -40) {
          dragging.current = false;
          onOpenChange(true);
        }
      }}
      onPointerUp={() => {
        dragging.current = false;
      }}
    >
      <button
        type="button"
        data-dock-drag
        onClick={() => onOpenChange(!open)}
        className="flex w-full touch-none flex-col items-center pt-1.5"
        aria-label={open ? "Close menu" : "Open menu"}
      >
        <span className="h-1.5 w-12 rounded-full bg-white/45" />
      </button>
      <div className="flex items-center gap-2 px-4 pb-2 pt-1">
        <button type="button" className="min-w-0 flex-1 text-left" onClick={() => onOpenChange(!open)}>
          <p className="truncate font-display text-sm font-semibold tracking-tight">{title}</p>
          {subtitle ? <p className="truncate text-[11px] text-muted">{subtitle}</p> : null}
        </button>
        <button
          type="button"
          onClick={() => onOpenChange(!open)}
          className="grid size-11 place-items-center rounded-full bg-white/8 text-muted"
          aria-label={open ? "Close" : "Open"}
        >
          {open ? <ChevronDown className="size-4" /> : <ChevronUp className="size-4" />}
        </button>
        {trailing}
      </div>
      <div className={cn(open ? "block" : "hidden")}>{children}</div>
    </div>
  );
}
