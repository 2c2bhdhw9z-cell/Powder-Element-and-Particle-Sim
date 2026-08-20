"use client";

import type { ReactNode } from "react";
import { GlassSheet } from "./glass-sheet";

export function Overlay({
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
  return (
    <GlassSheet open={open} onClose={onClose} title={title} wide={wide}>
      {children}
    </GlassSheet>
  );
}