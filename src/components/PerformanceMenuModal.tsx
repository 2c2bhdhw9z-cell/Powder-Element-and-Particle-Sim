import React, { useState } from 'react';
import { PowderEngine } from '../engine/powderEngine';
import { ParticleEngine } from '../engine/particleEngine';
import { FastForward, Gauge, Cpu, Sliders, Zap, Check, Eye } from 'lucide-react';

interface PerformanceMenuModalProps {
  isOpen: boolean;
  onClose: () => void;
  engineType: 'powder' | 'particle';
  powderEngine?: PowderEngine;
  particleEngine?: ParticleEngine;
  fps: number;
  simSpeed: number;
  setSimSpeed: (speed: number) => void;
}

export const PerformanceMenuModal: React.FC<PerformanceMenuModalProps> = ({
  isOpen,
  onClose,
  engineType,
  powderEngine,
  particleEngine,
  fps,
  simSpeed,
  setSimSpeed
}) => {
  const [downscale, setDownscale] = useState<number>(1); // 1 = Native, 1.5 = Performance, 2 = Ultra
  const [substeps, setSubsteps] = useState<number>(1);
  const [showTrails, setShowTrails] = useState<boolean>(particleEngine ? particleEngine.showTrails : true);
  const [electrostatics, setElectrostatics] = useState<boolean>(true);

  if (!isOpen) return null;

  const handleDownscaleChange = (factor: number) => {
    setDownscale(factor);
    if (engineType === 'powder' && powderEngine) {
      const baseW = 280;
      const baseH = 200;
      powderEngine.resize(Math.round(baseW / factor), Math.round(baseH / factor));
    }
  };

  const handleMaxParticleChange = (limit: number) => {
    if (particleEngine) {
      particleEngine.maxParticles = limit;
      if (particleEngine.particles.length > limit) {
        particleEngine.particles = particleEngine.particles.slice(0, limit);
      }
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-in fade-in duration-200 select-none">
      <div className="w-full max-w-xl bg-neutral-900 border border-neutral-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 bg-neutral-950 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
              <Gauge className="w-5 h-5" />
            </div>
            <div>
              <h2 className="font-bold text-white text-base">
                {engineType === 'powder' ? 'Powder Simulator' : 'Particle Simulator'} Performance Tuning
              </h2>
              <p className="text-xs text-neutral-400">Optimize framerate, physics precision, and rendering resolution</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="px-3 py-1.5 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-neutral-300 hover:text-white text-xs font-semibold transition-all"
          >
            Close
          </button>
        </div>

        {/* Content */}
        <div className="p-6 space-y-5 overflow-y-auto max-h-[80vh]">
          {/* Framerate Gauge */}
          <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className={`w-3 h-3 rounded-full ${fps >= 50 ? 'bg-emerald-400' : fps >= 30 ? 'bg-amber-400' : 'bg-red-400'} animate-pulse`} />
              <div>
                <div className="text-xs text-neutral-400">Current Framerate</div>
                <div className="text-xl font-bold font-mono text-white">{fps} FPS</div>
              </div>
            </div>
            <div className="text-right font-mono text-xs text-neutral-400">
              Target: <span className="text-amber-400 font-bold">60 FPS</span>
            </div>
          </div>

          {/* Simulation Speed */}
          <div className="space-y-2.5">
            <label className="text-xs font-bold text-neutral-300 flex items-center justify-between">
              <span className="flex items-center gap-1.5">
                <FastForward className="w-3.5 h-3.5 text-amber-400" />
                <span>Simulation Time Speed</span>
              </span>
              <span className="font-mono text-xs font-bold text-amber-300">
                {simSpeed < 0.1 ? simSpeed.toFixed(2) : simSpeed.toFixed(1)}x
              </span>
            </label>

            <input
              type="range"
              min="0.01"
              max="4.00"
              step="0.01"
              value={simSpeed}
              onChange={e => setSimSpeed(parseFloat(e.target.value))}
              className="w-full accent-amber-500 h-2 bg-neutral-950 rounded-lg cursor-pointer border border-neutral-800"
            />

            <div className="grid grid-cols-7 gap-1.5">
              {[0.02, 0.05, 0.1, 0.25, 0.5, 1, 2].map(speed => (
                <button
                  key={speed}
                  onClick={() => setSimSpeed(speed)}
                  className={`py-1.5 rounded-lg text-xs font-bold font-mono transition-all border ${
                    simSpeed === speed
                      ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow-md font-bold'
                      : 'bg-neutral-950 text-neutral-300 border-neutral-800 hover:bg-neutral-800'
                  }`}
                >
                  {speed < 0.1 ? `${speed}` : `${speed}x`}
                </button>
              ))}
            </div>
          </div>

          {/* Resolution Downscaling (Powder Sandbox) */}
          {engineType === 'powder' && (
            <div className="space-y-2">
              <label className="text-xs font-bold text-neutral-300 flex items-center gap-1.5">
                <Cpu className="w-3.5 h-3.5 text-blue-400" />
                <span>Grid Resolution Scaling</span>
              </label>
              <div className="grid grid-cols-3 gap-2">
                {[
                  { factor: 1, label: 'Native (1:1)', desc: 'Highest detail' },
                  { factor: 1.5, label: 'Performance (1.5x)', desc: 'Balanced FPS' },
                  { factor: 2, label: 'Ultra Fast (2.0x)', desc: 'Max Framerate' }
                ].map(opt => (
                  <button
                    key={opt.factor}
                    onClick={() => handleDownscaleChange(opt.factor)}
                    className={`p-3 rounded-xl text-left transition-all border ${
                      downscale === opt.factor
                        ? 'bg-blue-600/20 text-blue-200 border-blue-500'
                        : 'bg-neutral-950 text-neutral-400 border-neutral-800 hover:bg-neutral-800'
                    }`}
                  >
                    <div className="font-bold text-xs text-white">{opt.label}</div>
                    <div className="text-[10px] text-neutral-400">{opt.desc}</div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Particle Limit & Trails (Particle Sandbox) */}
          {engineType === 'particle' && particleEngine && (
            <div className="space-y-4">
              <div className="space-y-2">
                <label className="text-xs font-bold text-neutral-300 flex items-center justify-between">
                  <span className="flex items-center gap-1.5">
                    <Sliders className="w-3.5 h-3.5 text-purple-400" />
                    <span>Max Particle Limit</span>
                  </span>
                  <span className="font-mono text-amber-400">{particleEngine.maxParticles.toLocaleString()}</span>
                </label>
                <input
                  type="range"
                  min="5000"
                  max="1000000"
                  step="5000"
                  value={particleEngine.maxParticles}
                  onChange={(e) => handleMaxParticleChange(Number(e.target.value))}
                  className="w-full accent-amber-500 cursor-pointer"
                />
              </div>

              <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Eye className="w-4 h-4 text-emerald-400" />
                  <div>
                    <div className="font-bold text-xs text-white">Motion Glow & Particle Trails</div>
                    <div className="text-[10px] text-neutral-400">Toggle vector trails for higher FPS at high counts</div>
                  </div>
                </div>
                <button
                  onClick={() => {
                    const next = !showTrails;
                    setShowTrails(next);
                    particleEngine.showTrails = next;
                  }}
                  className={`w-10 h-6 rounded-full p-1 transition-all ${showTrails ? 'bg-amber-500' : 'bg-neutral-800'}`}
                >
                  <div className={`w-4 h-4 rounded-full bg-neutral-950 transition-all ${showTrails ? 'translate-x-4' : 'translate-x-0'}`} />
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
