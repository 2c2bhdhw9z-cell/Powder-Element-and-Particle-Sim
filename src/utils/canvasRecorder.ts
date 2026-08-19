// Canvas recording + screenshot utilities for both Powder & Particle engines

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
    console.error('Screenshot failed', e);
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
      const stream = (this.canvas as any).captureStream ? (this.canvas as any).captureStream(fps) : null;
      if (!stream) {
        alert('Canvas recording not supported in this browser. Try Chrome/Edge for WebM export.');
        return;
      }
      this.chunks = [];
      const mimeCandidates = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'];
      let mimeType = '';
      for (const c of mimeCandidates) {
        if (MediaRecorder.isTypeSupported(c)) { mimeType = c; break; }
      }
      this.recorder = new MediaRecorder(stream, mimeType ? { mimeType, videoBitsPerSecond: 2500000 } : undefined);
      this.recorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) this.chunks.push(e.data);
      };
      this.recorder.onstop = () => {
        const blob = new Blob(this.chunks, { type: mimeType || 'video/webm' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `powder-lab-${Date.now()}.webm`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(()=> URL.revokeObjectURL(url), 2000);
        this.isRecording = false;
        this.onStateChange?.(false);
      };
      this.recorder.start(100);
      this.isRecording = true;
      this.onStateChange?.(true);
    } catch (e) {
      console.error('Recorder start failed', e);
      alert('Recording failed to start.');
    }
  }

  public stop() {
    if (!this.isRecording || !this.recorder) return;
    try {
      this.recorder.stop();
      // stop all tracks
      const stream = (this.recorder as any).stream as MediaStream | undefined;
      if (stream) stream.getTracks().forEach(t=> t.stop());
    } catch (e) {
      console.error('Recorder stop failed', e);
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
