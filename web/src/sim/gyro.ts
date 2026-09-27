type GyroStatus = "off" | "on" | "need" | "denied" | "none";

type Listener = () => void;

class Gyro {
  enabled = false;
  locked = false;
  status: GyroStatus = "off";
  /** Powder gravity, -1..1 */
  gx = 0;
  gy = 1;
  /** Particle gravity */
  pgx = 0;
  pgy = 0.28;
  shake = 0;

  private listeners = new Set<Listener>();
  private bound = false;

  subscribe(fn: Listener) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }

  private emit() {
    for (const fn of this.listeners) fn();
  }

  async toggle(): Promise<GyroStatus> {
    if (this.enabled) {
      this.stop();
      return this.status;
    }
    return this.start();
  }

  async start(): Promise<GyroStatus> {
    if (typeof window === "undefined" || typeof DeviceOrientationEvent === "undefined") {
      this.status = "none";
      this.emit();
      return this.status;
    }
    const DOE = DeviceOrientationEvent as typeof DeviceOrientationEvent & {
      requestPermission?: () => Promise<string>;
    };
    try {
      if (typeof DOE.requestPermission === "function") {
        const perm = await DOE.requestPermission();
        if (perm !== "granted") {
          this.status = "denied";
          this.emit();
          return this.status;
        }
      }
    } catch {
      this.status = "denied";
      this.emit();
      return this.status;
    }
    this.enabled = true;
    this.locked = false;
    this.status = "on";
    this.bind();
    this.emit();
    return this.status;
  }

  stop() {
    this.enabled = false;
    this.locked = false;
    this.status = "off";
    this.unbind();
    this.emit();
  }

  lock() {
    this.locked = !this.locked;
    this.emit();
  }

  private bind() {
    if (this.bound) return;
    this.bound = true;
    window.addEventListener("deviceorientation", this.onOrient, { passive: true });
    window.addEventListener("devicemotion", this.onMotion, { passive: true });
  }

  private unbind() {
    if (!this.bound) return;
    this.bound = false;
    window.removeEventListener("deviceorientation", this.onOrient);
    window.removeEventListener("devicemotion", this.onMotion);
  }

  private onOrient = (e: DeviceOrientationEvent) => {
    if (!this.enabled || this.locked) return;
    const gamma = e.gamma ?? 0;
    const beta = e.beta ?? 90;
    const gx = Math.max(-1, Math.min(1, gamma / 32));
    const gy = Math.max(-1, Math.min(1, (beta - 40) / 50));
    this.gx = gx;
    this.gy = gy;
    this.pgx = gx * 0.42;
    this.pgy = gy * 0.42;
  };

  private onMotion = (e: DeviceMotionEvent) => {
    if (!this.enabled) return;
    const a = e.accelerationIncludingGravity;
    if (!a) return;
    const mag = Math.hypot(a.x || 0, a.y || 0, a.z || 0);
    if (mag > 22) this.shake = Math.min(3, this.shake + (mag - 22) * 0.08);
    else this.shake *= 0.86;
  };
}

export const gyro = new Gyro();
