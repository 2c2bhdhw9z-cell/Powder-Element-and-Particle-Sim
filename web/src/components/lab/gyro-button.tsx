"use client";

import { useEffect, useState } from "react";
import { Smartphone } from "lucide-react";
import { gyro } from "@/sim/gyro";
import { cn } from "@/lib/utils";

export function GyroButton() {
  const [on, setOn] = useState(gyro.enabled);
  const [locked, setLocked] = useState(gyro.locked);
  const [status, setStatus] = useState(gyro.status);

  useEffect(() => {
    return gyro.subscribe(() => {
      setOn(gyro.enabled);
      setLocked(gyro.locked);
      setStatus(gyro.status);
    });
  }, []);

  return (
    <button
      type="button"
      onClick={() => {
        if (!gyro.enabled) void gyro.toggle();
        else if (!gyro.locked) gyro.lock();
        else gyro.stop();
      }}
      className={cn(
        "h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium",
        on ? "text-fg" : "text-muted hover:text-fg",
      )}
      aria-label="Tilt gravity"
      title={on ? (locked ? "Tilt locked — tap to off" : "Tilt on — tap to lock") : "Enable tilt gravity"}
    >
      <span className="inline-flex items-center gap-1.5">
        <Smartphone className={cn("size-3.5", on && !locked && "text-ok")} />
        {status === "denied" || status === "none" ? "No tilt" : locked ? "Locked" : on ? "Tilt" : "Tilt"}
      </span>
    </button>
  );
}
