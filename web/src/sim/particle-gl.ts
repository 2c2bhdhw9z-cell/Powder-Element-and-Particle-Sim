import { debug } from "@/lib/debug";
const VS = `
attribute vec2 a_pos;
attribute vec4 a_col;
uniform vec2 u_res;
uniform float u_size;
varying vec4 v_col;
void main() {
  vec2 clip = (a_pos / u_res) * 2.0 - 1.0;
  gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);
  gl_PointSize = u_size;
  v_col = a_col;
}
`;

const FS = `
precision mediump float;
varying vec4 v_col;
void main() {
  vec2 p = gl_PointCoord * 2.0 - 1.0;
  if (dot(p, p) > 1.0) discard;
  gl_FragColor = v_col;
}
`;

/**
 * Compiles a shader, or returns null with the driver's reason.
 *
 * The status was never checked, so a driver that rejected the shader produced a
 * black canvas, no error anywhere, and an `attach()` that reported success — after
 * which the view kept choosing the GL path forever.
 */
function compile(gl: WebGLRenderingContext, type: number, src: string): WebGLShader | null {
  const s = gl.createShader(type);
  if (!s) return null;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    debug.error("Particle shader failed to compile", gl.getShaderInfoLog(s));
    gl.deleteShader(s);
    return null;
  }
  return s;
}

export class ParticleGL {
  private gl: WebGLRenderingContext | null = null;
  private program: WebGLProgram | null = null;
  private posBuf: WebGLBuffer | null = null;
  private colBuf: WebGLBuffer | null = null;
  private aPos = 0;
  private aCol = 0;
  private uRes: WebGLUniformLocation | null = null;
  private uSize: WebGLUniformLocation | null = null;
  private pos = new Float32Array(0);
  private col = new Float32Array(0);
  private posCap = 0;
  private colCap = 0;
  private lastColorTick = -1;
  private lastColorN = 0;

  attach(canvas: HTMLCanvasElement) {
    const gl = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
      preserveDrawingBuffer: false,
    });
    if (!gl) {
      this.gl = null;
      return false;
    }
    this.gl = gl;
    const vs = compile(gl, gl.VERTEX_SHADER, VS);
    const fs = compile(gl, gl.FRAGMENT_SHADER, FS);
    if (!vs || !fs) {
      if (vs) gl.deleteShader(vs);
      if (fs) gl.deleteShader(fs);
      this.gl = null;
      return false;
    }
    const prog = gl.createProgram();
    if (!prog) {
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      this.gl = null;
      return false;
    }
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      debug.error("Particle shader program failed to link", gl.getProgramInfoLog(prog));
      gl.deleteProgram(prog);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      this.gl = null;
      return false;
    }
    // Linked, so the shader objects themselves are no longer needed.
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    this.program = prog;
    this.aPos = gl.getAttribLocation(prog, "a_pos");
    this.aCol = gl.getAttribLocation(prog, "a_col");
    this.uRes = gl.getUniformLocation(prog, "u_res");
    this.uSize = gl.getUniformLocation(prog, "u_size");
    this.posBuf = gl.createBuffer();
    this.colBuf = gl.createBuffer();
    gl.disable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    return true;
  }

  draw(
    particles: { x: number; y: number; colorUint32?: number }[],
    width: number,
    height: number,
    pointSize: number,
  ) {
    const gl = this.gl;
    const prog = this.program;
    if (!gl || !prog) return false;
    const n = particles.length;
    if (this.pos.length < n * 2) {
      this.pos = new Float32Array(Math.max(n * 2, 64));
      this.col = new Float32Array(Math.max(n * 4, 128));
    }
    const pos = this.pos;
    const col = this.col;
    for (let i = 0; i < n; i++) {
      const p = particles[i];
      pos[i * 2] = p.x;
      pos[i * 2 + 1] = p.y;
      const c = p.colorUint32 || 0xffffffff;
      col[i * 4] = (c & 255) / 255;
      col[i * 4 + 1] = ((c >> 8) & 255) / 255;
      col[i * 4 + 2] = ((c >> 16) & 255) / 255;
      col[i * 4 + 3] = 1;
    }
    gl.viewport(0, 0, width, height);
    gl.clearColor(0.039, 0.039, 0.047, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(prog);
    gl.uniform2f(this.uRes, width, height);
    gl.uniform1f(this.uSize, Math.max(1.5, Math.min(4, pointSize + 0.5)));
    gl.bindBuffer(gl.ARRAY_BUFFER, this.posBuf);
    gl.bufferData(gl.ARRAY_BUFFER, pos.subarray(0, n * 2), gl.STREAM_DRAW);
    // Capacity has to be recorded here as well as in drawXY. Both paths share these
    // two buffers, and only drawXY tracked the size — so this call could shrink the
    // buffer while drawXY still believed it was large, after which drawXY's partial
    // upload exceeded the real allocation and the driver silently drew nothing.
    this.posCap = n * 2;
    gl.enableVertexAttribArray(this.aPos);
    gl.vertexAttribPointer(this.aPos, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.colBuf);
    gl.bufferData(gl.ARRAY_BUFFER, col.subarray(0, n * 4), gl.STREAM_DRAW);
    this.colCap = n * 4;
    // The colour cache belongs to drawXY and has just been invalidated by writing a
    // different particle set into the shared buffer.
    this.lastColorTick = -1;
    this.lastColorN = 0;
    gl.enableVertexAttribArray(this.aCol);
    gl.vertexAttribPointer(this.aCol, 4, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.POINTS, 0, n);
    return true;
  }

  drawXY(
    xy: Float32Array,
    color: Uint32Array,
    n: number,
    width: number,
    height: number,
    pointSize: number,
    colorTick = 0,
  ) {
    const gl = this.gl;
    const prog = this.program;
    if (!gl || !prog || n <= 0) return false;
    if (this.col.length < n * 4) this.col = new Float32Array(Math.max(n * 4, 128));
    const needColor = this.lastColorN !== n || this.lastColorTick !== colorTick;
    if (needColor) {
      const col = this.col;
      for (let i = 0; i < n; i++) {
        const c = color[i] || 0xffffffff;
        col[i * 4] = (c & 255) / 255;
        col[i * 4 + 1] = ((c >> 8) & 255) / 255;
        col[i * 4 + 2] = ((c >> 16) & 255) / 255;
        col[i * 4 + 3] = 1;
      }
      this.lastColorN = n;
      this.lastColorTick = colorTick;
    }
    gl.viewport(0, 0, width, height);
    gl.clearColor(0.039, 0.039, 0.047, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(prog);
    gl.uniform2f(this.uRes, width, height);
    gl.uniform1f(this.uSize, Math.max(1.4, Math.min(4, pointSize + 0.4)));
    gl.bindBuffer(gl.ARRAY_BUFFER, this.posBuf);
    const posView = xy.subarray(0, n * 2);
    if (this.posCap < n * 2) {
      gl.bufferData(gl.ARRAY_BUFFER, posView, gl.DYNAMIC_DRAW);
      this.posCap = n * 2;
    } else {
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, posView);
    }
    gl.enableVertexAttribArray(this.aPos);
    gl.vertexAttribPointer(this.aPos, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.colBuf);
    if (needColor) {
      const colView = this.col.subarray(0, n * 4);
      if (this.colCap < n * 4) {
        gl.bufferData(gl.ARRAY_BUFFER, colView, gl.DYNAMIC_DRAW);
        this.colCap = n * 4;
      } else {
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, colView);
      }
    }
    gl.enableVertexAttribArray(this.aCol);
    gl.vertexAttribPointer(this.aCol, 4, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.POINTS, 0, n);
    return true;
  }

  drawSoA(
    x: Float32Array,
    y: Float32Array,
    color: Uint32Array,
    n: number,
    width: number,
    height: number,
    pointSize: number,
    colorTick = 0,
  ) {
    if (this.pos.length < n * 2) this.pos = new Float32Array(Math.max(n * 2, 64));
    const pos = this.pos;
    for (let i = 0; i < n; i++) {
      pos[i * 2] = x[i];
      pos[i * 2 + 1] = y[i];
    }
    return this.drawXY(pos, color, n, width, height, pointSize, colorTick);
  }
}
