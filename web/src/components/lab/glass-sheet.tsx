"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

export function GlassSheet({
  open,
  onClose,
  title,
  children,
  wide,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  wide?: boolean;
}) {
  const startY = useRef(0);
  const dragging = useRef(false);
  const sheet = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  const reset = () => {
    dragging.current = false;
    startY.current = 0;
    if (sheet.current) sheet.current.style.transform = "";
  };

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-[200] flex items-end justify-center md:items-center">
      <button type="button" aria-label="Close" className="absolute inset-0 bg-black/55" onClick={onClose} />
      <div
        ref={sheet}
        className={cn(
          "relative z-10 flex max-h-[min(70dvh,calc(100svh-6rem))] w-full flex-col overflow-hidden rounded-t-[1.75rem] border border-white/16 bg-black/70 shadow-2xl backdrop-blur-3xl md:max-h-[86dvh] md:max-w-lg md:rounded-3xl",
          wide ? "md:max-w-lg" : "md:max-w-md",
        )}
        style={{
          transition: "transform 180ms ease-out",
          paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))",
        }}
        onPointerDown={(e) => {
          if (!(e.target as HTMLElement).closest("[data-drag]")) return;
          dragging.current = true;
          startY.current = e.clientY;
          (e.currentTarget as HTMLDivElement).style.transition = "none";
          (e.currentTarget as HTMLDivElement).setPointerCapture(e.pointerId);
        }}
        onPointerMove={(e) => {
          if (!dragging.current || !sheet.current) return;
          const dy = Math.max(0, e.clientY - startY.current);
          sheet.current.style.transform = `translateY(${dy}px)`;
        }}
        onPointerUp={(e) => {
          if (!dragging.current) return;
          const dy = e.clientY - startY.current;
          dragging.current = false;
          if (sheet.current) sheet.current.style.transition = "transform 180ms ease-out";
          if (dy > 88) onClose();
          else reset();
        }}
      >
        <button
          type="button"
          data-drag
          className="flex w-full touch-none flex-col items-center pt-2 pb-1"
          onClick={() => {
            if (dragging.current) return;
            onClose();
          }}
          aria-label="Drag or tap to close"
        >
          <span className="h-1.5 w-12 rounded-full bg-white/40" />
        </button>
        <div className="flex items-center justify-between gap-3 px-5 pb-2">
          <h2 className="font-display text-base font-semibold tracking-tight">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            className="grid size-11 place-items-center rounded-full bg-white/8 text-muted hover:text-fg"
          >
            <X className="size-4" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-3">{children}</div>
      </div>
    </div>,
    document.body,
  );
}
