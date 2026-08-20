interface GPUDevice {
  createShaderModule(d: { code: string }): unknown;
  createBindGroupLayout(d: unknown): GPUBindGroupLayout;
  createPipelineLayout(d: unknown): unknown;
  createComputePipeline(d: unknown): GPUComputePipeline;
  createRenderPipeline(d: unknown): GPURenderPipeline;
  createBuffer(d: { size: number; usage: number }): GPUBuffer;
  createBindGroup(d: unknown): unknown;
  createCommandEncoder(): {
    beginComputePass(): {
      setBindGroup(i: number, g: unknown): void;
      setPipeline(p: GPUComputePipeline): void;
      dispatchWorkgroups(n: number): void;
      end(): void;
    };
    beginRenderPass(d: unknown): {
      setPipeline(p: GPURenderPipeline): void;
      setBindGroup(i: number, g: unknown): void;
      setVertexBuffer(i: number, b: GPUBuffer): void;
      draw(n: number): void;
      end(): void;
    };
    copyBufferToBuffer(a: GPUBuffer, ao: number, b: GPUBuffer, bo: number, s: number): void;
    finish(): unknown;
  };
  queue: { writeBuffer(b: GPUBuffer, o: number, d: ArrayBuffer | ArrayBufferView): void; submit(c: unknown[]): void };
  lost: Promise<unknown>;
}
interface GPUBuffer {
  destroy(): void;
  mapAsync(mode: number): Promise<void>;
  getMappedRange(): ArrayBuffer;
  unmap(): void;
}
interface GPUComputePipeline {
  getBindGroupLayout?(i: number): GPUBindGroupLayout;
}
interface GPURenderPipeline {}
interface GPUBindGroupLayout {}
interface GPUCanvasContext {
  canvas: HTMLCanvasElement;
  configure(d: unknown): void;
  getCurrentTexture(): { createView(): unknown };
}
declare const GPUShaderStage: { COMPUTE: number; VERTEX: number; FRAGMENT: number };
declare const GPUBufferUsage: {
  STORAGE: number;
  UNIFORM: number;
  COPY_DST: number;
  COPY_SRC: number;
  MAP_READ: number;
  VERTEX: number;
};
declare const GPUMapMode: { READ: number };
interface HTMLCanvasElement {
  getContext(contextId: "webgpu"): GPUCanvasContext | null;
}
interface Navigator {
  gpu?: {
    requestAdapter(): Promise<{ requestDevice(): Promise<GPUDevice> } | null>;
    getPreferredCanvasFormat(): string;
  };
}
