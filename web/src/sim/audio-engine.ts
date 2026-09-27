// Web Audio API procedural sound engine for physics sandbox events

class PhysicsAudioEngine {
  private ctx: AudioContext | null = null;
  public enabled: boolean = true;
  public volume: number = 0.4;
  private lastSoundTime: Map<string, number> = new Map();

  private initCtx() {
    if (!this.ctx && typeof window !== 'undefined') {
      // Safari still ships the prefixed constructor; the DOM lib has no typing for it.
      const w = window as Window & { webkitAudioContext?: typeof AudioContext };
      const AudioCtx = window.AudioContext || w.webkitAudioContext;
      if (AudioCtx) {
        this.ctx = new AudioCtx();
      }
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  private canPlay(soundId: string, minIntervalMs: number = 80): boolean {
    if (!this.enabled) return false;
    const now = performance.now();
    const last = this.lastSoundTime.get(soundId) || 0;
    if (now - last < minIntervalMs) return false;
    this.lastSoundTime.set(soundId, now);
    return true;
  }

  public playExplosion(intensity: number = 1.0) {
    if (!this.canPlay('explosion', 200)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const bufferSize = this.ctx.sampleRate * 0.5;
      const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
      const output = buffer.getChannelData(0);

      for (let i = 0; i < bufferSize; i++) {
        output[i] = Math.random() * 2 - 1;
      }

      const whiteNoise = this.ctx.createBufferSource();
      whiteNoise.buffer = buffer;

      const filter = this.ctx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.setValueAtTime(800 * intensity, now);
      filter.frequency.exponentialRampToValueAtTime(30, now + 0.4);

      const gain = this.ctx.createGain();
      gain.gain.setValueAtTime(this.volume * 0.8 * intensity, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.45);

      whiteNoise.connect(filter);
      filter.connect(gain);
      gain.connect(this.ctx.destination);

      whiteNoise.start(now);
      whiteNoise.stop(now + 0.45);
    } catch {
      // Audio fallback quiet catch
    }
  }

  public playAcidFizz() {
    if (!this.canPlay('acid', 120)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = 'triangle';
      osc.frequency.setValueAtTime(1200 + Math.random() * 600, now);
      osc.frequency.exponentialRampToValueAtTime(300, now + 0.08);

      gain.gain.setValueAtTime(this.volume * 0.15, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.08);

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      osc.start(now);
      osc.stop(now + 0.08);
    } catch { /* ignore */ }
  }

  public playFireCrackle() {
    if (!this.canPlay('fire', 150)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(150 + Math.random() * 200, now);

      gain.gain.setValueAtTime(this.volume * 0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      osc.start(now);
      osc.stop(now + 0.06);
    } catch { /* ignore */ }
  }

  public playFreeze() {
    if (!this.canPlay('freeze', 300)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(200, now);
      osc.frequency.exponentialRampToValueAtTime(1200, now + 0.3);

      gain.gain.setValueAtTime(this.volume * 0.3, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      osc.start(now);
      osc.stop(now + 0.35);
    } catch { /* ignore */ }
  }

  public playMeteor() {
    if (!this.canPlay('meteor', 500)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(800, now);
      osc.frequency.exponentialRampToValueAtTime(80, now + 0.5);

      gain.gain.setValueAtTime(this.volume * 0.5, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.55);

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      osc.start(now);
      osc.stop(now + 0.55);
    } catch { /* ignore */ }
  }

  public playCollisionChime() {
    if (!this.canPlay('collision', 100)) return;
    this.initCtx();
    if (!this.ctx) return;

    try {
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(500 + Math.random() * 800, now);

      gain.gain.setValueAtTime(this.volume * 0.12, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      osc.start(now);
      osc.stop(now + 0.05);
    } catch { /* ignore */ }
  }
}

export const soundEngine = new PhysicsAudioEngine();
