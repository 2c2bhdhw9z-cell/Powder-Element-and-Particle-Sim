"use client";

import { Camera, Redo2, Undo2, Video, VideoOff } from "lucide-react";
import { cn } from "@/lib/utils";

export function CanvasTools({
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  onShot,
  recording,
  onRecord,
  speed,
  onSpeed,
}: {
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
  onShot: () => void;
  recording: boolean;
  onRecord: () => void;
  speed: number;
  onSpeed: (n: number) => void;
}) {
  return (
    <div className="pointer-events-none absolute left-2 top-2 z-10 flex flex-wrap items-center gap-1">
      <div className="pointer-events-auto flex items-center rounded-full border border-white/15 bg-black/45 backdrop-blur-xl">
        <button
          type="button"
          disabled={!canUndo}
          onClick={onUndo}
          className="grid size-10 place-items-center text-muted disabled:opacity-30 hover:text-fg"
          aria-label="Undo"
        >
          <Undo2 className="size-3.5" />
        </button>
        <button
          type="button"
          disabled={!canRedo}
          onClick={onRedo}
          className="grid size-10 place-items-center text-muted disabled:opacity-30 hover:text-fg"
          aria-label="Redo"
        >
          <Redo2 className="size-3.5" />
        </button>
        <button
          type="button"
          onClick={onShot}
          className="grid size-10 place-items-center text-muted hover:text-fg"
          aria-label="Screenshot"
        >
          <Camera className="size-3.5" />
        </button>
        <button
          type="button"
          onClick={onRecord}
          className={cn(
            "grid size-10 place-items-center",
            recording ? "text-danger" : "text-muted hover:text-fg",
          )}
          aria-label={recording ? "Stop recording" : "Record"}
        >
          {recording ? <VideoOff className="size-3.5" /> : <Video className="size-3.5" />}
        </button>
        {recording ? (
          <span className="pr-2 text-[10px] font-medium text-danger">REC</span>
        ) : null}
      </div>
      <div className="pointer-events-auto flex rounded-full border border-white/15 bg-black/45 backdrop-blur-xl">
        {[0.25, 0.5, 1, 2, 4].map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => onSpeed(s)}
            className={cn(
              "h-10 min-w-9 px-2 text-[11px] font-medium tabular-nums",
              speed === s ? "text-fg" : "text-muted hover:text-fg",
            )}
          >
            {s}×
          </button>
        ))}
      </div>
    </div>
  );
}
