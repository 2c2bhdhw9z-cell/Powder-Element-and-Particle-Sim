function bytesToB64(u8: Uint8Array) {
  const parts: string[] = [];
  const cs = 0x8000;
  for (let i = 0; i < u8.length; i += cs) {
    parts.push(String.fromCharCode.apply(null, Array.from(u8.subarray(i, i + cs))));
  }
  return btoa(parts.join(""));
}

function b64ToBytes(s: string) {
  const bin = atob(s);
  const u8 = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  return u8;
}

export function packSwarmSnap(sx: number[], sy: number[], svx: number[], svy: number[]) {
  const n = sx.length;
  const i16 = new Int16Array(n * 4);
  for (let i = 0; i < n; i++) {
    i16[i * 4] = Math.max(-32000, Math.min(32000, Math.round(sx[i] * 8)));
    i16[i * 4 + 1] = Math.max(-32000, Math.min(32000, Math.round(sy[i] * 8)));
    i16[i * 4 + 2] = Math.max(-32000, Math.min(32000, Math.round(svx[i] * 64)));
    i16[i * 4 + 3] = Math.max(-32000, Math.min(32000, Math.round(svy[i] * 64)));
  }
  return { n, b: bytesToB64(new Uint8Array(i16.buffer)) };
}

export function unpackSwarmSnap(n: number, b: string) {
  const i16 = new Int16Array(b64ToBytes(b).buffer);
  const sx: number[] = [];
  const sy: number[] = [];
  const svx: number[] = [];
  const svy: number[] = [];
  const take = Math.min(n, Math.floor(i16.length / 4));
  for (let i = 0; i < take; i++) {
    sx.push(i16[i * 4] / 8);
    sy.push(i16[i * 4 + 1] / 8);
    svx.push(i16[i * 4 + 2] / 64);
    svy.push(i16[i * 4 + 3] / 64);
  }
  return { sx, sy, svx, svy };
}

export function packXY(sx: number[], sy: number[]) {
  const n = sx.length;
  const i16 = new Int16Array(n * 2);
  for (let i = 0; i < n; i++) {
    i16[i * 2] = Math.max(-32000, Math.min(32000, Math.round(sx[i] * 8)));
    i16[i * 2 + 1] = Math.max(-32000, Math.min(32000, Math.round(sy[i] * 8)));
  }
  return { n, b: bytesToB64(new Uint8Array(i16.buffer)) };
}

export function unpackXY(n: number, b: string) {
  const i16 = new Int16Array(b64ToBytes(b).buffer);
  const sx: number[] = [];
  const sy: number[] = [];
  const take = Math.min(n, Math.floor(i16.length / 2));
  for (let i = 0; i < take; i++) {
    sx.push(i16[i * 2] / 8);
    sy.push(i16[i * 2 + 1] / 8);
  }
  return { sx, sy };
}
