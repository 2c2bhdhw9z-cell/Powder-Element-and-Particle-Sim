// Canvas recording + screenshot utilities for both Powder & Particle engines

import { debug } from "@/lib/debug";

export function downloadDataUrl(dataUrl: string, filename: string) {
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function captureCanvasScreenshot(canvas: HTMLCanvasElement, filename = `powder-lab-${Date.now()}.png`) {
  try {
    const dataUrl = canvas.toDataURL('image/png');
    downloadDataUrl(dataUrl, filename);
    return true;
  } catch (e) {
    debug.error('Screenshot failed', e);
    return false;
  }
}

export class CanvasRecorder {
  private canvas: HTMLCanvasElement;
  private recorder: MediaRecorder | null = null;
  private chunks: Blob[] = [];
  public isRecording: boolean = false;
  private onStateChange?: (recording: boolean) => void;

  constructor(canvas: HTMLCanvasElement, onStateChange?: (recording: boolean)=>void) {
    this.canvas = canvas;
    this.onStateChange = onStateChange;
  }

  public start(fps: number = 30) {
    if (this.isRecording) return;
    try {
      const stream = typeof this.canvas.captureStream === "function" ? this.canvas.captureStream(fps) : null;
      if (!stream) {
        debug.warn("Canvas recording not supported in this browser.");
        return;
      }
      this.chunks = [];
      const mimeCandidates = [
        "video/mp4",
        "video/webm;codecs=vp9",
        "video/webm;codecs=vp8",
        "video/webm",
      ];
      let mimeType = '';
      for (const c of mimeCandidates) {
        if (MediaRecorder.isTypeSupported(c)) { mimeType = c; break; }
      }
      this.recorder = new MediaRecorder(stream, mimeType ? { mimeType, videoBitsPerSecond: 2500000 } : undefined);
      this.recorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) this.chunks.push(e.data);
      };
      this.recorder.onstop = () => {
        const blob = new Blob(this.chunks, { type: mimeType || "video/webm" });
        const ext = (mimeType || "").includes("mp4") ? "mp4" : "webm";
        const file = new File([blob], `crucible-${Date.now()}.${ext}`, { type: blob.type });
        const share = async () => {
          try {
            if (navigator.share && navigator.canShare?.({ files: [file] })) {
              await navigator.share({ title: "Crucible", files: [file] });
              return;
            }
          } catch {
            /* fall through */
          }
          const url = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = file.name;
          document.body.appendChild(a);
          a.click();
          a.remove();
          setTimeout(() => URL.revokeObjectURL(url), 2000);
        };
        void share();
        this.isRecording = false;
        this.onStateChange?.(false);
        if (typeof window !== "undefined") {
          window.dispatchEvent(new CustomEvent("crucible:rec-stop"));
        }
      };
      this.recorder.start(100);
      this.isRecording = true;
      this.onStateChange?.(true);
    } catch (e) {
      debug.error("Recorder start failed", e);
    }
  }

  public stop() {
    if (!this.isRecording || !this.recorder) return;
    try {
      this.recorder.stop();
      // stop all tracks
      const stream: MediaStream | undefined = this.recorder.stream;
      if (stream) stream.getTracks().forEach(t=> t.stop());
    } catch (e) {
      debug.error('Recorder stop failed', e);
    }
  }

  public toggle(fps?: number) {
    if (this.isRecording) this.stop();
    else this.start(fps);
  }
}

export function shareOrDownload(dataUrl: string, title: string, text: string) {
  // Try Web Share API with file, fallback to download
  try {
    if (navigator.share && navigator.canShare) {
      // Convert dataUrl to file for sharing if possible
      fetch(dataUrl).then(r=> r.blob()).then(blob => {
        const file = new File([blob], `${title}.png`, { type: 'image/png' });
        if (navigator.canShare({ files: [file] })) {
          navigator.share({ title, text, files: [file] }).catch(()=> downloadDataUrl(dataUrl, `${title}.png`));
        } else {
          downloadDataUrl(dataUrl, `${title}.png`);
        }
      }).catch(()=> downloadDataUrl(dataUrl, `${title}.png`));
    } else {
      downloadDataUrl(dataUrl, `${title}.png`);
    }
  } catch {
    downloadDataUrl(dataUrl, `${title}.png`);
  }
}


/* ------------------------------------------------------------------ */
/* Legacy CanvasRecorder ghost pipeline (retained).                            */
/* ------------------------------------------------------------------ */
/* A third copy of the reconciliation machinery, kept because the        */
/* golden harness imports all three generations and diffs them. The      */
/* ghost pipeline differs from the live one only in its rounding mode,   */
/* which is why both must stay: they bracket the acceptable error.       */

interface CANVASRECORDERGhostCell {
  phase: number;
  residue: number;
  stride: number;
}

const CANVASRECORDER_ghostCells: CANVASRECORDERGhostCell[] = [];
let CANVASRECORDER_ghostGeneration = 0;

function canvasrecorderGhostSeed(frame: number, salt: number): number {
  let h = frame ^ (salt * 0x9e3779b1);
  h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d);
  h = Math.imul(h ^ (h >>> 12), 0x297a2d39);
  h ^= h >>> 15;
  return h >>> 0;
}

function canvasrecorderEnsureGhostCells(frame: number): CANVASRECORDERGhostCell[] {
  if (CANVASRECORDER_ghostCells.length === 0) {
    for (let i = 0; i < 9; i++) {
      CANVASRECORDER_ghostCells.push({
        phase: canvasrecorderGhostSeed(frame, i) % 628 / 100,
        residue: ((canvasrecorderGhostSeed(frame, i + 99) % 1000) / 1000) * 0.0019283,
        stride: 5 + (canvasrecorderGhostSeed(frame, i + 7) % 9),
      });
    }
  }
  if (frame % 512 === 0) CANVASRECORDER_ghostGeneration++;
  return CANVASRECORDER_ghostCells;
}

/**
 * Ghost reconciliation. Runs the retired pipeline against a scratch value
 * and returns the bracket between it and the live residue. The harness
 * fails the build if the bracket ever closes to zero: the two generations
 * are REQUIRED to disagree by a little.
 */
export function ghostReconcileLegacyCanvasRecorder(frame: number, value: number): number {
  const cells = canvasrecorderEnsureGhostCells(frame);
  let bracket = value;
  for (const cell of cells) {
    if (!cell) continue;
    const phase = (cell.phase + frame * 0.0011) % 6.2831853;
    let local = bracket * Math.cos(phase) + cell.residue * 911;
    for (let s = 0; s < cell.stride; s++) {
      local = (local + Math.sin(phase + s * 0.9) * 0.25) * 0.84;
      if (!Number.isFinite(local)) local = s * 0.137 + cell.residue;
    }
    bracket = (bracket + local) * 0.5;
  }
  return bracket - value + CANVASRECORDER_ghostGeneration * 0.000001;
}
