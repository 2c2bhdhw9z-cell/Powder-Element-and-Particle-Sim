import React, { useRef, useEffect, useState } from 'react';
import { ParticleEngine } from '../engine/particleEngine';
import { DebugMenuModal } from './DebugMenuModal';
import { PerformanceMenuModal } from './PerformanceMenuModal';
import { AnalyticsDashboardModal, AnalyticsFrameData } from './AnalyticsDashboardModal';
import {
  Play, Pause, FastForward, Trash2, Sparkles, Orbit, Waves, Magnet, Activity,
  Sliders, X, Settings2, Zap, RefreshCw, Compass, Shield,
  Crosshair, Palette, Layers, Flame, Maximize2, Wrench, Gauge, BarChart3
} from 'lucide-react';

interface ParticleSandboxProps {
  engine: ParticleEngine;
}

export const ParticleSandbox: React.FC<ParticleSandboxProps> = ({ engine }) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  // Responsive Screen Size & Aspect Ratio Detection
  useEffect(() => {
    const handleResize = () => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;

      const newW = Math.round(rect.width);
      const newH = Math.round(rect.height);

      engine.resize(newW, newH);
    };

    handleResize();

    const observer = new ResizeObserver(() => handleResize());
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }
    window.addEventListener('resize', handleResize);

    return () => {
      observer.disconnect();
      window.removeEventListener('resize', handleResize);
    };
  }, [engine]);

  const [fps, setFps] = useState<number>(60);
  const [particleCount, setParticleCount] = useState<number>(0);
  const [isPaused, setIsPaused] = useState<boolean>(false);
  const [showTrails, setShowTrails] = useState<boolean>(true);

  // Menu Collapsible State
  const [isMenuOpen, setIsMenuOpen] = useState<boolean>(false);
  const [isDebugOpen, setIsDebugOpen] = useState<boolean>(false);
  const [isPerfOpen, setIsPerfOpen] = useState<boolean>(false);
  const [isAnalyticsOpen, setIsAnalyticsOpen] = useState<boolean>(false);
  const [analyticsHistory, setAnalyticsHistory] = useState<AnalyticsFrameData[]>([]);
  const [simSpeed, setSimSpeed] = useState<number>(1);
  const [activeTab, setActiveTab] = useState<'presets' | 'physics' | 'mouse' | 'visuals'>('presets');

  // Physics & Spawner Settings
  const [spawnBatchCount, setSpawnBatchCount] = useState<number>(10000);
  const [gravityX, setGravityX] = useState<number>(0);
  const [gravityY, setGravityY] = useState<number>(0.3);
  const [damping, setDamping] = useState<number>(0.99);
  const [elasticity, setElasticity] = useState<number>(0.8);
  const [electrostatic, setElectrostatic] = useState<number>(100);
  const [vortexForce, setVortexForce] = useState<number>(0);
  const [maxSpeed, setMaxSpeed] = useState<number>(30);
  const [boundaryMode, setBoundaryMode] = useState<'bounce' | 'wrap' | 'void'>('bounce');
  const [mouseMode, setMouseMode] = useState<'attract' | 'repel' | 'vortex' | 'emitter' | 'painter' | 'gravity_well' | 'freeze' | 'hyper_drive'>('attract');
  const [mouseRadius, setMouseRadius] = useState<number>(120);
  const [mouseForceMultiplier, setMouseForceMultiplier] = useState<number>(1.0);
  const [colorMode, setColorMode] = useState<'element' | 'velocity' | 'charge' | 'rainbow' | 'density' | 'lifespan'>('element');
  const [particleSize, setParticleSize] = useState<number>(2);
  const [decaySpeed, setDecaySpeed] = useState<number>(0);

  // Capture periodic Recharts Telemetry
  useEffect(() => {
    const timer = setInterval(() => {
      const diag = engine.getDiagnostics();
      const timeLabel = new Date().toLocaleTimeString([], { hour12: false, minute: '2-digit', second: '2-digit' });
      setAnalyticsHistory(prev => [...prev.slice(-40), {
        time: timeLabel,
        fps,
        particles: diag.particleCount,
        diversity: 8,
        maxTemp: diag.maxSpeedFound,
        avgTemp: Math.round(diag.maxSpeedFound / 2)
      }]);
    }, 1000);

    return () => clearInterval(timer);
  }, [engine, fps]);
  const mousePosRef = useRef<{ x: number; y: number; active: boolean }>({
    x: 0,
    y: 0,
    active: false
  });

  const frameTimesRef = useRef<number[]>([]);
  const frameCountRef = useRef<number>(0);
  const lastTimeRef = useRef<number>(performance.now());
  const speedAccumulatorRef = useRef<number>(0);

  // Spawner Presets
  const handleAddBurst = () => engine.spawnBurst(150);
  const handleAddGalaxy = () => { setGravityY(0); setVortexForce(0); engine.spawnGalaxy(300); };
  const handleAddWaterfall = () => { setGravityY(0.4); engine.spawnWaterfall(250); };
  const handleAddRepulsor = () => { setGravityY(0); engine.spawnRepulsor(); };
  const handleAddShockwave = () => { setGravityY(0); engine.spawnShockwave(300); };
  const handleAddBlackHole = () => { setGravityY(0); engine.spawnBlackHole(250); };
  const handleAddDoubleVortex = () => { setGravityY(0); engine.spawnDoubleVortex(300); };
  const handleAddSolarFlare = () => { setGravityY(0); engine.spawnSolarFlare(350); };
  const handleAddQuantumLattice = () => { setGravityY(0); engine.spawnQuantumLattice(18, 24); };
  const handleAddDnaHelix = () => { setGravityY(0); engine.spawnDnaHelix(280); };
  const handleAddCosmicFountain = () => { setGravityY(0.3); engine.spawnCosmicFountain(250); };
  const handleAddSynchrotron = () => { setGravityY(0); engine.spawnSynchrotron(300); };
  const handleClear = () => engine.clear();

  // Mouse Handlers - High performance ref updates with 0ms React latency
  const handlePointerDown = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    let cx = 0, cy = 0;

    if ('touches' in e && e.touches.length > 0) {
      cx = e.touches[0].clientX;
      cy = e.touches[0].clientY;
    } else if ('clientX' in e) {
      cx = e.clientX;
      cy = e.clientY;
    }

    const scaleX = engine.width / rect.width;
    const scaleY = engine.height / rect.height;

    mousePosRef.current = {
      x: (cx - rect.left) * scaleX,
      y: (cy - rect.top) * scaleY,
      active: true
    };
  };

  const handlePointerMove = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    if (!mousePosRef.current.active) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    let cx = 0, cy = 0;

    if ('touches' in e && e.touches.length > 0) {
      cx = e.touches[0].clientX;
      cy = e.touches[0].clientY;
    } else if ('clientX' in e) {
      cx = e.clientX;
      cy = e.clientY;
    }

    const scaleX = engine.width / rect.width;
    const scaleY = engine.height / rect.height;

    mousePosRef.current.x = (cx - rect.left) * scaleX;
    mousePosRef.current.y = (cy - rect.top) * scaleY;
  };

  const handlePointerUp = () => {
    mousePosRef.current.active = false;
  };

  // Main Render Loop - Continuous 60+ FPS execution without React re-render teardown
  useEffect(() => {
    let animId: number;

    const renderLoop = () => {
      const now = performance.now();
      const delta = now - lastTimeRef.current;
      lastTimeRef.current = now;

      frameTimesRef.current.push(1000 / Math.max(1, delta));
      if (frameTimesRef.current.length > 30) frameTimesRef.current.shift();

      frameCountRef.current++;
      if (frameCountRef.current % 10 === 0) {
        const avgFps = Math.round(
          frameTimesRef.current.reduce((a, b) => a + b, 0) / frameTimesRef.current.length
        );
        setFps(avgFps);
        setParticleCount(engine.particles.length);
      }

      // Sync parameters to engine
      engine.gravityX = gravityX;
      engine.gravityY = gravityY;
      engine.damping = damping;
      engine.elasticity = elasticity;
      engine.electrostaticFactor = electrostatic;
      engine.vortexForce = vortexForce;
      engine.maxSpeed = maxSpeed;
      engine.boundaryMode = boundaryMode;
      engine.mouseMode = mouseMode;
      engine.mouseRadius = mouseRadius;
      engine.mouseForceMultiplier = mouseForceMultiplier;
      engine.colorMode = colorMode;
      engine.particleSize = particleSize;
      engine.decaySpeed = decaySpeed;
      engine.showTrails = showTrails;

      const mPos = mousePosRef.current;

      if (!isPaused) {
        speedAccumulatorRef.current += Math.max(0.001, simSpeed);
        let stepsExecuted = 0;
        while (speedAccumulatorRef.current >= 1 && stepsExecuted < 10) {
          engine.step(mPos.x, mPos.y, mPos.active);
          speedAccumulatorRef.current -= 1;
          stepsExecuted++;
        }
        if (speedAccumulatorRef.current > 5) {
          speedAccumulatorRef.current = 0;
        }
      } else {
        speedAccumulatorRef.current = 0;
        engine.lastMouseX = mPos.x;
        engine.lastMouseY = mPos.y;
        engine.lastMouseActive = mPos.active;
      }

      const canvas = canvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          engine.render(ctx);
        }
      }

      animId = requestAnimationFrame(renderLoop);
    };

    animId = requestAnimationFrame(renderLoop);
    return () => cancelAnimationFrame(animId);
  }, [engine, isPaused, simSpeed, gravityX, gravityY, damping, elasticity, electrostatic, vortexForce, maxSpeed, boundaryMode, mouseMode, mouseRadius, mouseForceMultiplier, colorMode, particleSize, decaySpeed, showTrails]);

  return (
    <div className="relative w-full h-[calc(100vh-65px)] bg-neutral-950 text-white flex flex-col p-2 overflow-hidden select-none">
      {/* Full-bleed Canvas Container */}
      <div ref={containerRef} className="relative w-full h-full flex-1 bg-black rounded-2xl border border-neutral-800 shadow-2xl overflow-hidden flex items-center justify-center">
        <canvas
          ref={canvasRef}
          width={engine.width}
          height={engine.height}
          onMouseDown={handlePointerDown}
          onMouseMove={handlePointerMove}
          onMouseUp={handlePointerUp}
          onMouseLeave={handlePointerUp}
          onTouchStart={handlePointerDown}
          onTouchMove={handlePointerMove}
          onTouchEnd={handlePointerUp}
          className="w-full h-full object-fill cursor-grab touch-none select-none"
        />

        {/* Floating Minimal HUD Bar */}
        <div className="absolute top-2 left-2 right-2 sm:top-3.5 sm:left-4 sm:right-4 flex items-center justify-between gap-1 sm:gap-1.5 pointer-events-auto z-20 max-w-full overflow-x-auto no-scrollbar py-0.5 scroll-smooth">
          <div className="flex items-center gap-1 sm:gap-1.5 shrink-0">
            <div className="flex items-center gap-1 font-mono px-1.5 sm:px-2 py-1 rounded-xl bg-neutral-900/90 backdrop-blur-md border border-neutral-800/80 shadow-lg font-bold text-xs">
              <span className={`w-2 h-2 rounded-full ${fps >= 50 ? 'bg-cyan-400' : 'bg-amber-400'} animate-pulse`} />
              <span className="text-cyan-400">{fps}</span>
              <span className="text-neutral-500 text-[10px] hidden xs:inline">FPS</span>
            </div>

            <div className="flex items-center gap-1 font-mono px-1.5 sm:px-2 py-1 rounded-xl bg-neutral-900/90 backdrop-blur-md border border-neutral-800/80 shadow-lg font-bold text-xs">
              <Activity className="w-3.5 h-3.5 text-purple-400 shrink-0" />
              <span className="text-purple-300">{particleCount.toLocaleString()}</span>
              <span className="text-neutral-500 text-[10px] hidden sm:inline">Particles</span>
            </div>
          </div>

          <div className="flex items-center gap-1 sm:gap-1.5 shrink-0">
            {/* Start / Stop Button */}
            <button
              onClick={() => setIsPaused(!isPaused)}
              className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-3 py-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 active:scale-95 ${
                isPaused
                  ? 'bg-emerald-500 hover:bg-emerald-400 text-neutral-950 border-emerald-400 shadow-emerald-500/20'
                  : 'bg-rose-600 hover:bg-rose-500 text-white border-rose-500 shadow-rose-600/20'
              }`}
              title={isPaused ? "Start Simulation" : "Stop Simulation"}
            >
              {isPaused ? (
                <>
                  <Play className="w-3.5 h-3.5 fill-current" />
                  <span className="hidden xs:inline">Start</span>
                </>
              ) : (
                <>
                  <Pause className="w-3.5 h-3.5 fill-current" />
                  <span className="hidden xs:inline">Stop</span>
                </>
              )}
            </button>

            {/* Speed Slider Control */}
            <div className="flex items-center gap-1 sm:gap-1.5 px-1.5 sm:px-2.5 py-1 rounded-xl bg-neutral-900/90 backdrop-blur-md border border-neutral-800/80 shadow-lg text-xs font-bold shrink-0">
              <FastForward className="w-3.5 h-3.5 text-amber-400 shrink-0" />
              <input
                type="range"
                min="0.01"
                max="3.00"
                step="0.01"
                value={simSpeed}
                onChange={e => setSimSpeed(parseFloat(e.target.value))}
                className="w-10 xs:w-14 sm:w-24 accent-amber-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                title={`Simulation Speed: ${simSpeed.toFixed(2)}x`}
              />
              <span className="font-mono text-[10px] sm:text-[11px] text-amber-300 min-w-[28px] sm:min-w-[36px] text-right">
                {simSpeed < 0.1 ? simSpeed.toFixed(2) : simSpeed.toFixed(1)}x
              </span>
            </div>

            <button
              onClick={() => setIsAnalyticsOpen(true)}
              className="p-1.5 rounded-xl bg-purple-950/80 hover:bg-purple-900 border border-purple-500/40 text-purple-300 text-xs font-bold transition-all shadow-lg backdrop-blur-md shrink-0"
              title="Open Recharts Real-Time Analytics Dashboard"
            >
              <BarChart3 className="w-3.5 h-3.5" />
            </button>

            <button
              onClick={() => setIsDebugOpen(true)}
              className="p-1.5 rounded-xl bg-blue-950/80 hover:bg-blue-900 border border-blue-500/40 text-blue-300 text-xs font-bold transition-all shadow-lg backdrop-blur-md shrink-0"
              title="Open Debug & Diagnostics Menu"
            >
              <Wrench className="w-3.5 h-3.5" />
            </button>

            <button
              onClick={() => setIsPerfOpen(true)}
              className="p-1.5 rounded-xl bg-purple-950/80 hover:bg-purple-900 border border-purple-500/40 text-purple-300 text-xs font-bold transition-all shadow-lg backdrop-blur-md shrink-0"
              title="Open Performance Tuning Menu"
            >
              <Gauge className="w-3.5 h-3.5" />
            </button>

            <button
              onClick={() => setIsMenuOpen(!isMenuOpen)}
              className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                isMenuOpen
                  ? 'bg-cyan-500 text-neutral-950 border-cyan-400 shadow-cyan-500/20'
                  : 'bg-neutral-900/90 text-cyan-300 border-neutral-800 hover:bg-neutral-800'
              }`}
              title="Settings & Particle Tools"
            >
              <Settings2 className="w-3.5 h-3.5" />
            </button>

            {/* PROMINENT CLEAR BUTTON */}
            <button
              onClick={handleClear}
              className="flex items-center gap-1 px-2 py-1.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/30 transition-all border border-red-400/50 active:scale-95 shrink-0"
              title="Clear Canvas Particles"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Clear</span>
            </button>
          </div>
        </div>

        {/* Collapsible Floating Menu Drawer Panel */}
        {isMenuOpen && (
          <div className="absolute top-16 right-3 left-3 sm:left-auto sm:w-[440px] max-h-[calc(100%-80px)] overflow-y-auto bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-30 flex flex-col gap-4 animate-in fade-in slide-in-from-top-4 scrollbar-thin">
            <div className="flex items-center justify-between pb-2 border-b border-neutral-800">
              <div className="flex items-center gap-2">
                <Sliders className="w-4 h-4 text-cyan-400" />
                <span className="text-sm font-bold text-white">Particle Simulator Controls</span>
              </div>
              <button
                onClick={() => setIsMenuOpen(false)}
                className="p-1 rounded-lg text-neutral-400 hover:text-white hover:bg-neutral-800 transition-all"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Tab Navigation */}
            <div className="grid grid-cols-4 gap-1 p-1 bg-neutral-950 rounded-xl border border-neutral-800 text-[11px] font-bold">
              <button
                onClick={() => setActiveTab('presets')}
                className={`py-1.5 rounded-lg flex items-center justify-center gap-1 transition-all ${
                  activeTab === 'presets' ? 'bg-cyan-500 text-neutral-950' : 'text-neutral-400 hover:text-white'
                }`}
              >
                <Sparkles className="w-3.5 h-3.5" />
                <span>Spawner</span>
              </button>
              <button
                onClick={() => setActiveTab('physics')}
                className={`py-1.5 rounded-lg flex items-center justify-center gap-1 transition-all ${
                  activeTab === 'physics' ? 'bg-cyan-500 text-neutral-950' : 'text-neutral-400 hover:text-white'
                }`}
              >
                <Compass className="w-3.5 h-3.5" />
                <span>Physics</span>
              </button>
              <button
                onClick={() => setActiveTab('mouse')}
                className={`py-1.5 rounded-lg flex items-center justify-center gap-1 transition-all ${
                  activeTab === 'mouse' ? 'bg-cyan-500 text-neutral-950' : 'text-neutral-400 hover:text-white'
                }`}
              >
                <Crosshair className="w-3.5 h-3.5" />
                <span>Mouse</span>
              </button>
              <button
                onClick={() => setActiveTab('visuals')}
                className={`py-1.5 rounded-lg flex items-center justify-center gap-1 transition-all ${
                  activeTab === 'visuals' ? 'bg-cyan-500 text-neutral-950' : 'text-neutral-400 hover:text-white'
                }`}
              >
                <Palette className="w-3.5 h-3.5" />
                <span>Visuals</span>
              </button>
            </div>

            {/* TAB 1: PRESETS & SPAWNER */}
            {activeTab === 'presets' && (
              <div className="flex flex-col gap-4">
                {/* Batch Spawner Controls */}
                <div className="flex flex-col gap-2.5 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
                  <span className="text-xs font-bold text-neutral-300 flex items-center justify-between">
                    <span>Batch Spawner Amount:</span>
                    <span className="font-mono text-cyan-300">{spawnBatchCount.toLocaleString()}</span>
                  </span>

                  <input
                    type="range"
                    min="1000"
                    max="1000000"
                    step="1000"
                    value={spawnBatchCount}
                    onChange={e => setSpawnBatchCount(parseInt(e.target.value))}
                    className="w-full accent-cyan-400 h-2 bg-neutral-800 rounded-lg cursor-pointer"
                  />

                  <div className="flex items-center justify-between gap-1">
                    {[1000, 10000, 50000, 100000, 500000, 1000000].map(val => (
                      <button
                        key={val}
                        onClick={() => setSpawnBatchCount(val)}
                        className={`px-2 py-1 rounded text-[10px] font-mono transition-all ${
                          spawnBatchCount === val
                            ? 'bg-cyan-500 text-neutral-950 font-bold'
                            : 'bg-neutral-900 text-neutral-400 hover:text-white border border-neutral-800'
                        }`}
                      >
                        {val >= 1000000 ? '1M' : val >= 1000 ? `${val / 1000}K` : val}
                      </button>
                    ))}
                  </div>

                  <button
                    onClick={() => engine.spawnBatch(spawnBatchCount)}
                    className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-cyan-500 hover:bg-cyan-400 text-neutral-950 font-bold text-xs transition-all shadow-md shadow-cyan-500/20 active:scale-95 mt-1"
                  >
                    <Sparkles className="w-4 h-4 fill-current" />
                    Spawn {spawnBatchCount >= 1000000 ? '1 Million' : spawnBatchCount.toLocaleString()} Particles
                  </button>
                </div>

                {/* Spawner Presets */}
                <div className="flex flex-col gap-2">
                  <span className="text-xs font-bold text-neutral-400">Simulation Presets & Emitters:</span>
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      onClick={handleAddGalaxy}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-purple-500/20 hover:bg-purple-500/30 border border-purple-500/40 text-purple-300 text-xs font-semibold transition-all"
                    >
                      <Orbit className="w-3.5 h-3.5" />
                      Galaxy Orbital
                    </button>

                    <button
                      onClick={handleAddWaterfall}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-blue-500/20 hover:bg-blue-500/30 border border-blue-500/40 text-blue-300 text-xs font-semibold transition-all"
                    >
                      <Waves className="w-3.5 h-3.5" />
                      Waterfall Stream
                    </button>

                    <button
                      onClick={handleAddShockwave}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 border border-amber-500/40 text-amber-300 text-xs font-semibold transition-all"
                    >
                      <Sparkles className="w-3.5 h-3.5" />
                      Shockwave Ring
                    </button>

                    <button
                      onClick={handleAddDoubleVortex}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-cyan-500/20 hover:bg-cyan-500/30 border border-cyan-500/40 text-cyan-300 text-xs font-semibold transition-all"
                    >
                      <RefreshCw className="w-3.5 h-3.5" />
                      Double Vortex
                    </button>

                    <button
                      onClick={handleAddSolarFlare}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-orange-500/20 hover:bg-orange-500/30 border border-orange-500/40 text-orange-300 text-xs font-semibold transition-all"
                    >
                      <Zap className="w-3.5 h-3.5" />
                      Solar Flare
                    </button>

                    <button
                      onClick={handleAddQuantumLattice}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-teal-500/20 hover:bg-teal-500/30 border border-teal-500/40 text-teal-300 text-xs font-semibold transition-all"
                    >
                      <Layers className="w-3.5 h-3.5" />
                      Quantum Lattice
                    </button>

                    <button
                      onClick={handleAddDnaHelix}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-indigo-500/20 hover:bg-indigo-500/30 border border-indigo-500/40 text-indigo-300 text-xs font-semibold transition-all"
                    >
                      <Activity className="w-3.5 h-3.5" />
                      DNA Helix
                    </button>

                    <button
                      onClick={handleAddCosmicFountain}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-pink-500/20 hover:bg-pink-500/30 border border-pink-500/40 text-pink-300 text-xs font-semibold transition-all"
                    >
                      <Compass className="w-3.5 h-3.5" />
                      Cosmic Fountain
                    </button>

                    <button
                      onClick={handleAddSynchrotron}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-violet-500/20 hover:bg-violet-500/30 border border-violet-500/40 text-violet-300 text-xs font-semibold transition-all"
                    >
                      <Crosshair className="w-3.5 h-3.5" />
                      Synchrotron
                    </button>

                    <button
                      onClick={handleAddBlackHole}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-rose-500/20 hover:bg-rose-500/30 border border-rose-500/40 text-rose-300 text-xs font-semibold transition-all"
                    >
                      <Flame className="w-3.5 h-3.5" />
                      Black Hole
                    </button>

                    <button
                      onClick={handleAddRepulsor}
                      className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-emerald-500/20 hover:bg-emerald-500/30 border border-emerald-500/40 text-emerald-300 text-xs font-semibold transition-all"
                    >
                      <Magnet className="w-3.5 h-3.5" />
                      Repulsor Shield
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* TAB 2: PHYSICS & FORCES */}
            {activeTab === 'physics' && (
              <div className="flex flex-col gap-3 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80 text-xs">
                {/* Simulation Time Speed Slider */}
                <div className="flex flex-col gap-1.5 pb-2 border-b border-neutral-800">
                  <div className="flex items-center justify-between">
                    <span className="text-neutral-300 font-bold flex items-center gap-1.5">
                      <FastForward className="w-3.5 h-3.5 text-amber-400" />
                      <span>Simulation Speed:</span>
                    </span>
                    <span className="font-mono font-bold text-amber-300 text-xs">
                      {simSpeed < 0.1 ? simSpeed.toFixed(2) : simSpeed.toFixed(1)}x
                    </span>
                  </div>
                  <input
                    type="range"
                    min="0.01"
                    max="3.00"
                    step="0.01"
                    value={simSpeed}
                    onChange={e => setSimSpeed(parseFloat(e.target.value))}
                    className="w-full accent-amber-400 h-2 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <div className="grid grid-cols-6 gap-1 mt-1">
                    {[0.02, 0.05, 0.1, 0.25, 0.5, 1.0].map(s => (
                      <button
                        key={s}
                        onClick={() => setSimSpeed(s)}
                        className={`py-1 rounded text-[10px] font-mono transition-all border ${
                          simSpeed === s
                            ? 'bg-amber-500 text-neutral-950 border-amber-400 font-bold'
                            : 'bg-neutral-900 text-neutral-400 hover:text-white border-neutral-800'
                        }`}
                      >
                        {s < 0.1 ? `${s}` : `${s}x`}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Gravity X */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Gravity X:</span>
                  <input
                    type="range"
                    min="-1"
                    max="1"
                    step="0.1"
                    value={gravityX}
                    onChange={e => setGravityX(parseFloat(e.target.value))}
                    className="w-full accent-cyan-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-cyan-300 min-w-[35px] text-right">{gravityX}G</span>
                </div>

                {/* Gravity Y */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Gravity Y:</span>
                  <input
                    type="range"
                    min="-1"
                    max="1"
                    step="0.1"
                    value={gravityY}
                    onChange={e => setGravityY(parseFloat(e.target.value))}
                    className="w-full accent-cyan-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-cyan-300 min-w-[35px] text-right">{gravityY}G</span>
                </div>

                {/* Air Friction */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Friction:</span>
                  <input
                    type="range"
                    min="0.80"
                    max="1.00"
                    step="0.005"
                    value={damping}
                    onChange={e => setDamping(parseFloat(e.target.value))}
                    className="w-full accent-purple-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-purple-300 min-w-[35px] text-right">
                    {Math.round((1 - damping) * 100)}%
                  </span>
                </div>

                {/* Wall Bounciness */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Bounciness:</span>
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value={elasticity}
                    onChange={e => setElasticity(parseFloat(e.target.value))}
                    className="w-full accent-emerald-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-emerald-300 min-w-[35px] text-right">
                    {Math.round(elasticity * 100)}%
                  </span>
                </div>

                {/* Center Vortex Attractor */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Center Vortex:</span>
                  <input
                    type="range"
                    min="-200"
                    max="200"
                    step="10"
                    value={vortexForce}
                    onChange={e => setVortexForce(parseInt(e.target.value))}
                    className="w-full accent-rose-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-rose-300 min-w-[35px] text-right">{vortexForce}</span>
                </div>

                {/* Coulomb Electrostatic Charge */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Coulomb:</span>
                  <input
                    type="range"
                    min="0"
                    max="500"
                    step="10"
                    value={electrostatic}
                    onChange={e => setElectrostatic(parseInt(e.target.value))}
                    className="w-full accent-amber-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-amber-300 min-w-[35px] text-right">{electrostatic}</span>
                </div>

                {/* Velocity Cap */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Speed Limit:</span>
                  <input
                    type="range"
                    min="5"
                    max="100"
                    value={maxSpeed}
                    onChange={e => setMaxSpeed(parseInt(e.target.value))}
                    className="w-full accent-blue-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-blue-300 min-w-[35px] text-right">{maxSpeed}px</span>
                </div>

                {/* Boundary Mode */}
                <div className="flex flex-col gap-1.5 pt-1 border-t border-neutral-800">
                  <span className="text-neutral-400 font-semibold">Boundary Collision Mode:</span>
                  <div className="grid grid-cols-3 gap-1.5">
                    {[
                      { id: 'bounce', name: 'Bounce' },
                      { id: 'wrap', name: 'Screen Wrap' },
                      { id: 'void', name: 'Void Wall' }
                    ].map(mode => (
                      <button
                        key={mode.id}
                        onClick={() => setBoundaryMode(mode.id as any)}
                        className={`py-1.5 rounded-lg text-[11px] font-bold transition-all ${
                          boundaryMode === mode.id
                            ? 'bg-cyan-500 text-neutral-950'
                            : 'bg-neutral-900 text-neutral-400 hover:text-white border border-neutral-800'
                        }`}
                      >
                        {mode.name}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {/* TAB 3: MOUSE INTERACTION TOOL */}
            {activeTab === 'mouse' && (
              <div className="flex flex-col gap-3 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80 text-xs">
                {/* Touch / Tap Radius Slider */}
                <div className="flex flex-col gap-1.5 pb-2 border-b border-neutral-800">
                  <div className="flex items-center justify-between text-neutral-400 font-semibold">
                    <span>Tap / Touch Radius:</span>
                    <span className="font-mono text-cyan-300 font-bold">
                      {mouseRadius >= 800 ? 'Full Canvas' : `${mouseRadius}px`}
                    </span>
                  </div>
                  <input
                    type="range"
                    min="30"
                    max="500"
                    step="10"
                    value={mouseRadius > 500 ? 500 : mouseRadius}
                    onChange={e => setMouseRadius(parseInt(e.target.value))}
                    className="w-full accent-cyan-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <div className="grid grid-cols-5 gap-1 mt-0.5">
                    {[
                      { label: '30px', val: 30 },
                      { label: '60px', val: 60 },
                      { label: '120px', val: 120 },
                      { label: '250px', val: 250 },
                      { label: 'Full', val: 800 }
                    ].map(preset => (
                      <button
                        key={preset.label}
                        onClick={() => setMouseRadius(preset.val)}
                        className={`py-1 rounded text-[10px] font-mono transition-all border ${
                          mouseRadius === preset.val
                            ? 'bg-cyan-500 text-neutral-950 border-cyan-400 font-bold'
                            : 'bg-neutral-900 text-neutral-400 hover:text-white border-neutral-800'
                        }`}
                      >
                        {preset.label}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Touch Force Strength */}
                <div className="flex flex-col gap-1.5 pb-2 border-b border-neutral-800">
                  <div className="flex items-center justify-between text-neutral-400 font-semibold">
                    <span>Force Strength:</span>
                    <span className="font-mono text-amber-300 font-bold">{mouseForceMultiplier.toFixed(1)}x</span>
                  </div>
                  <input
                    type="range"
                    min="0.2"
                    max="3.0"
                    step="0.1"
                    value={mouseForceMultiplier}
                    onChange={e => setMouseForceMultiplier(parseFloat(e.target.value))}
                    className="w-full accent-amber-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                </div>

                <span className="text-neutral-400 font-bold">Interactive Cursor Tool Mode:</span>
                <div className="grid grid-cols-1 gap-2">
                  {[
                    { id: 'attract', name: 'Attractor Gravity', desc: 'Pull particles toward cursor' },
                    { id: 'repel', name: 'Repulsor Shield', desc: 'Push particles away from cursor' },
                    { id: 'vortex', name: 'Vortex Swirl', desc: 'Spin particles around cursor' },
                    { id: 'emitter', name: 'Continuous Emitter', desc: 'Spray particles on click & drag' },
                    { id: 'painter', name: 'Rainbow Painter', desc: 'Colorize particles on touch' },
                    { id: 'gravity_well', name: 'Gravity Well Swirl', desc: 'Pull and spin in deep gravity well' },
                    { id: 'freeze', name: 'Zero-G Freeze Ray', desc: 'Freeze velocity on touch' },
                    { id: 'hyper_drive', name: 'Hyper Drive Accelerator', desc: 'Supercharge particles into laser streaks' }
                  ].map(tool => (
                    <button
                      key={tool.id}
                      onClick={() => setMouseMode(tool.id as any)}
                      className={`p-2.5 rounded-xl border text-left transition-all flex items-center justify-between ${
                        mouseMode === tool.id
                          ? 'bg-cyan-500/20 border-cyan-500 text-white'
                          : 'bg-neutral-900 border-neutral-800 text-neutral-400 hover:text-white'
                      }`}
                    >
                      <div>
                        <div className="font-bold text-xs">{tool.name}</div>
                        <div className="text-[10px] text-neutral-400">{tool.desc}</div>
                      </div>
                      {mouseMode === tool.id && <div className="w-2 h-2 rounded-full bg-cyan-400 animate-ping" />}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* TAB 4: VISUALS & RENDERER */}
            {activeTab === 'visuals' && (
              <div className="flex flex-col gap-3 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80 text-xs">
                {/* Color Mode Selector */}
                <div className="flex flex-col gap-1.5">
                  <span className="text-neutral-400 font-semibold">Color Visualizer Mode:</span>
                  <div className="grid grid-cols-2 gap-1.5">
                    {[
                      { id: 'element', name: 'Default Color' },
                      { id: 'velocity', name: 'Velocity Heatmap' },
                      { id: 'charge', name: 'Charge Polarity' },
                      { id: 'rainbow', name: 'Rainbow Spectrum' },
                      { id: 'density', name: 'Kinetic Heatmap' },
                      { id: 'lifespan', name: 'Lifespan Decay' }
                    ].map(mode => (
                      <button
                        key={mode.id}
                        onClick={() => setColorMode(mode.id as any)}
                        className={`py-1.5 px-2 rounded-lg text-[11px] font-bold transition-all ${
                          colorMode === mode.id
                            ? 'bg-cyan-500 text-neutral-950'
                            : 'bg-neutral-900 text-neutral-400 hover:text-white border border-neutral-800'
                        }`}
                      >
                        {mode.name}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Particle Size */}
                <div className="flex items-center justify-between gap-3 pt-2 border-t border-neutral-800">
                  <span className="text-neutral-400 min-w-[80px]">Render Size:</span>
                  <input
                    type="range"
                    min="1"
                    max="8"
                    value={particleSize}
                    onChange={e => setParticleSize(parseInt(e.target.value))}
                    className="w-full accent-cyan-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-cyan-300 min-w-[35px] text-right">{particleSize}px</span>
                </div>

                {/* Lifespan Auto Decay */}
                <div className="flex items-center justify-between gap-3">
                  <span className="text-neutral-400 min-w-[80px]">Auto Decay:</span>
                  <input
                    type="range"
                    min="0"
                    max="10"
                    value={decaySpeed}
                    onChange={e => setDecaySpeed(parseInt(e.target.value))}
                    className="w-full accent-purple-400 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="font-mono font-bold text-purple-300 min-w-[35px] text-right">
                    {decaySpeed === 0 ? 'Off' : `${decaySpeed}x`}
                  </span>
                </div>

                {/* Motion Trails Toggle */}
                <button
                  onClick={() => setShowTrails(!showTrails)}
                  className={`flex items-center justify-center gap-2 px-3 py-2 rounded-xl border text-xs font-semibold transition-all mt-1 ${
                    showTrails
                      ? 'bg-cyan-500/20 border-cyan-500/50 text-cyan-300'
                      : 'bg-neutral-900 border-neutral-800 text-neutral-400'
                  }`}
                >
                  <Zap className="w-3.5 h-3.5" />
                  Motion Glow & Trails: {showTrails ? 'ON' : 'OFF'}
                </button>
              </div>
            )}

            {/* Clear All Simulation Particles Button in Drawer */}
            <button
              onClick={handleClear}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/30 transition-all border border-red-500 active:scale-95"
            >
              <Trash2 className="w-4 h-4" />
              <span>Clear All Particles ({particleCount.toLocaleString()})</span>
            </button>
          </div>
        )}
      </div>

      {/* Modals */}
      <DebugMenuModal
        isOpen={isDebugOpen}
        onClose={() => setIsDebugOpen(false)}
        engineType="particle"
        particleEngine={engine}
        fps={fps}
      />

      <PerformanceMenuModal
        isOpen={isPerfOpen}
        onClose={() => setIsPerfOpen(false)}
        engineType="particle"
        particleEngine={engine}
        fps={fps}
        simSpeed={simSpeed}
        setSimSpeed={setSimSpeed}
      />

      <AnalyticsDashboardModal
        isOpen={isAnalyticsOpen}
        onClose={() => setIsAnalyticsOpen(false)}
        engineType="particle"
        particleEngine={engine}
        history={analyticsHistory}
        fps={fps}
        onClearHistory={() => setAnalyticsHistory([])}
      />
    </div>
  );
};
