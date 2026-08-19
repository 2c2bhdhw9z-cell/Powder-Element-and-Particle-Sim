import React, { useRef, useEffect, useState, useCallback } from 'react';
import { PowderEngine } from '../engine/powderEngine';
import { ElementRegistry } from '../engine/elementRegistry';
import { ElementDefinition } from '../types/physics';
import { DebugMenuModal } from './DebugMenuModal';
import { PerformanceMenuModal } from './PerformanceMenuModal';
import { AnalyticsDashboardModal, AnalyticsFrameData } from './AnalyticsDashboardModal';
import { soundEngine } from '../utils/audioEngine';
import { CanvasRecorder, captureCanvasScreenshot } from '../utils/canvasRecorder';
import {
  Play, Pause, FastForward, RotateCcw, Trash2, StepForward,
  ArrowDown, ArrowUp, ArrowLeft, ArrowRight,
  Circle, Square, Pipette, PaintBucket, Eraser, Wind, Pencil, Sparkles,
  Wrench, Gauge, ChevronDown, Layers, Sliders, BarChart3, Flame, Volume2, VolumeX,
  Rewind, History, Bomb, Zap, Droplet, Thermometer, Radio, Check, X,
  Undo2, Redo2, Camera, Video, VideoOff, Keyboard, Share2
} from 'lucide-react';

interface PowderSandboxProps {
  engine: PowderEngine;
  registry: ElementRegistry;
  onEmitDraw?: (drawData: any) => void;
  onOpenUploadMap?: () => void;
}

export const PowderSandbox: React.FC<PowderSandboxProps> = ({
  engine,
  registry,
  onEmitDraw,
  onOpenUploadMap
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  // Responsive Screen Size & Aspect Ratio Detection
  useEffect(() => {
    const handleResize = () => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;

      const isMobile = window.innerWidth < 640;
      const scale = isMobile ? 2.2 : 2.8;

      const newW = Math.max(120, Math.round(rect.width / scale));
      const newH = Math.max(120, Math.round(rect.height / scale));

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

  // Engine State
  const [fps, setFps] = useState<number>(60);
  const [isPaused, setIsPaused] = useState<boolean>(false);
  const [simSpeed, setSimSpeed] = useState<number>(1);
  const [selectedElement, setSelectedElement] = useState<number>(1); // Default Sand
  const [activeCategory, setActiveCategory] = useState<string>('Solids');

  // Heatmap Overlay Mode
  const [heatmapMode, setHeatmapMode] = useState<'normal' | 'temp_overlay' | 'temp'>('normal');

  // Audio Engine State
  const [soundEnabled, setSoundEnabled] = useState<boolean>(true);

  // Analytics State
  const [isAnalyticsOpen, setIsAnalyticsOpen] = useState<boolean>(false);
  const [analyticsHistory, setAnalyticsHistory] = useState<AnalyticsFrameData[]>([]);

  // DVR / Physics Time Scrubber State
  const [snapshots, setSnapshots] = useState<string[]>([]);
  const [dvrIndex, setDvrIndex] = useState<number>(-1); // -1 = live edge
  const [isDvrOpen, setIsDvrOpen] = useState<boolean>(false);

  // God Tools Disaster Menu & Screen Shake
  const [isDisasterMenuOpen, setIsDisasterMenuOpen] = useState<boolean>(false);
  const [isSettingsOpen, setIsSettingsOpen] = useState<boolean>(false);
  const [screenShake, setScreenShake] = useState<number>(0);

  // Brush Settings
  const [brushSize, setBrushSize] = useState<number>(5);
  const [brushShape, setBrushShape] = useState<'circle' | 'square' | 'spray' | 'line' | 'fill' | 'replace' | 'eraser' | 'picker'>('circle');

  // Environment & Spawner State
  const [gravityDir, setGravityDir] = useState<'down' | 'up' | 'left' | 'right' | 'zero'>('down');
  const [ambientTemp, setAmbientTemp] = useState<number>(20);
  const [tempUnit, setTempUnit] = useState<'C' | 'F'>('C');
  const [spawnCount, setSpawnCount] = useState<number>(10000);
  const [textureMode, setTextureMode] = useState<'diagonal_matrix' | 'natural_grain' | 'organic_flow' | 'flat'>('natural_grain');
  const [windX, setWindX] = useState<number>(0);
  const [isRecording, setIsRecording] = useState<boolean>(false);
  const [undoTick, setUndoTick] = useState<number>(0);

  const formatTemp = useCallback((celsius: number) => {
    if (tempUnit === 'F') {
      const fahrenheit = Math.round((celsius * 9) / 5 + 32);
      return `${fahrenheit}°F`;
    }
    return `${Math.round(celsius)}°C`;
  }, [tempUnit]);

  const getTempSpectrumPercent = useCallback((celsius: number): number => {
    if (celsius <= -100) return 0;
    if (celsius <= 0) return ((celsius + 100) / 100) * 15;
    if (celsius <= 20) return 15 + (celsius / 20) * 15;
    if (celsius <= 100) return 30 + ((celsius - 20) / 80) * 15;
    if (celsius <= 500) return 45 + ((celsius - 100) / 400) * 25;
    if (celsius <= 3000) return 70 + Math.min(1, (celsius - 500) / 2500) * 30;
    return 100;
  }, []);

  const [, setRenderTick] = useState<number>(0);

  const updateTextureMode = (mode: 'diagonal_matrix' | 'natural_grain' | 'organic_flow' | 'flat') => {
    setTextureMode(mode);
    engine.textureMode = mode;
  };

  // Inspector State
  const [inspectedElement, setInspectedElement] = useState<{
    x: number;
    y: number;
    element: ElementDefinition;
    temp: number;
  } | null>(null);
  const [isPointerActive, setIsPointerActive] = useState<boolean>(false);

  // Drawing Interaction Refs
  const isDrawingRef = useRef<boolean>(false);
  const lastPosRef = useRef<{ x: number; y: number } | null>(null);
  const hasPushedUndoRef = useRef<boolean>(false);
  const recorderRef = useRef<CanvasRecorder | null>(null);

  // FPS Tracking
  const frameTimesRef = useRef<number[]>([]);
  const frameCountRef = useRef<number>(0);
  const lastTimeRef = useRef<number>(performance.now());
  const speedAccumulatorRef = useRef<number>(0);

  // Search and Category List
  const [searchTerm, setSearchTerm] = useState<string>('');
  const categories = ['All', 'Solids', 'Liquids', 'Gases', 'Energetic', 'Biological', 'Special'];

  // Handle Gravity Direction Change
  const updateGravity = (dir: 'down' | 'up' | 'left' | 'right' | 'zero') => {
    setGravityDir(dir);
    if (dir === 'down') { engine.gravityX = 0; engine.gravityY = 1; }
    else if (dir === 'up') { engine.gravityX = 0; engine.gravityY = -1; }
    else if (dir === 'left') { engine.gravityX = -1; engine.gravityY = 0; }
    else if (dir === 'right') { engine.gravityX = 1; engine.gravityY = 0; }
    else if (dir === 'zero') { engine.gravityX = 0; engine.gravityY = 0; }
  };

  // Convert Mouse/Touch coordinates to Canvas Grid coordinates
  const getGridCoords = useCallback((e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return null;

    const rect = canvas.getBoundingClientRect();
    let clientX = 0;
    let clientY = 0;

    if ('touches' in e) {
      if (e.touches.length === 0) return null;
      clientX = e.touches[0].clientX;
      clientY = e.touches[0].clientY;
    } else {
      clientX = e.clientX;
      clientY = e.clientY;
    }

    const scaleX = engine.width / rect.width;
    const scaleY = engine.height / rect.height;

    const gx = Math.floor((clientX - rect.left) * scaleX);
    const gy = Math.floor((clientY - rect.top) * scaleY);

    return {
      x: Math.max(0, Math.min(engine.width - 1, gx)),
      y: Math.max(0, Math.min(engine.height - 1, gy))
    };
  }, [engine.width, engine.height]);

  // Apply Paint Action
  const applyPaint = useCallback((gx: number, gy: number) => {
    if (brushShape === 'picker') {
      const el = engine.getElementAt(gx, gy);
      setSelectedElement(el.id);
      return;
    }

    const elementIdToDraw = brushShape === 'eraser' ? 0 : selectedElement;

    if (brushShape === 'line' && lastPosRef.current) {
      let x0 = lastPosRef.current.x;
      let y0 = lastPosRef.current.y;
      const x1 = gx;
      const y1 = gy;
      const dx = Math.abs(x1 - x0);
      const dy = Math.abs(y1 - y0);
      const sx = x0 < x1 ? 1 : -1;
      const sy = y0 < y1 ? 1 : -1;
      let err = dx - dy;

      while (true) {
        engine.drawBrush(x0, y0, brushSize, elementIdToDraw, 'circle');
        if (x0 === x1 && y0 === y1) break;
        const e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 < dx) { err += dx; y0 += sy; }
      }
    } else {
      const shapeType = brushShape === 'eraser' ? 'circle' : (brushShape === 'line' ? 'circle' : brushShape);
      engine.drawBrush(gx, gy, brushSize, elementIdToDraw, shapeType as any);
    }

    // Audio sound trigger on active drawing
    if (soundEnabled) {
      if (elementIdToDraw === 4) soundEngine.playFireCrackle(); // Fire
      else if (elementIdToDraw === 8) soundEngine.playAcidFizz(); // Acid
      else soundEngine.playCollisionChime();
    }

    if (onEmitDraw) {
      onEmitDraw({
        x: gx,
        y: gy,
        size: brushSize,
        elementId: elementIdToDraw,
        shape: brushShape
      });
    }

    lastPosRef.current = { x: gx, y: gy };
  }, [brushShape, brushSize, selectedElement, engine, onEmitDraw, soundEnabled]);

  // Snapshot helper for undo grouping
  const triggerUndoPush = useCallback(() => {
    if (!hasPushedUndoRef.current) {
      engine.pushUndo();
      hasPushedUndoRef.current = true;
      setUndoTick(t=> t+1);
    }
  }, [engine]);

  // Screenshot & Recording handlers
  const handleScreenshot = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    captureCanvasScreenshot(canvas, `powder-lab-${Date.now()}.png`);
    soundEngine.playCollisionChime();
  }, []);

  const handleToggleRecording = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    if (!recorderRef.current) {
      recorderRef.current = new CanvasRecorder(canvas, (rec)=> setIsRecording(rec));
    }
    recorderRef.current.toggle(30);
  }, []);

  // Global keyboard shortcuts for powder sandbox
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) {
          if (engine.canRedo()) { engine.redo(); setUndoTick(t=>t+1); }
        } else {
          if (engine.canUndo()) { engine.undo(); setUndoTick(t=>t+1); }
        }
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') {
        e.preventDefault();
        if (engine.canRedo()) { engine.redo(); setUndoTick(t=>t+1); }
      } else if (e.key === ' ') {
        e.preventDefault();
        setIsPaused(v=> !v);
      } else if (e.key.toLowerCase() === 'c' && !e.ctrlKey && !e.metaKey) {
        engine.clear(); setUndoTick(t=>t+1);
      } else if (e.key.toLowerCase() === 's' && !e.ctrlKey && !e.metaKey) {
        handleScreenshot();
      } else if (e.key.toLowerCase() === 'r' && !e.ctrlKey && !e.metaKey) {
        handleToggleRecording();
      } else if (e.key.toLowerCase() === 'h') {
        setHeatmapMode(m=> m==='normal' ? 'temp_overlay' : m==='temp_overlay' ? 'temp' : 'normal');
      } else if (e.key === '[') {
        setBrushSize(s=> Math.max(1, s-1));
      } else if (e.key === ']') {
        setBrushSize(s=> Math.min(25, s+1));
      } else if (e.key.toLowerCase() === 'e') {
        setBrushShape('eraser');
      } else if (e.key.toLowerCase() === 'b' && !e.shiftKey) {
        setBrushShape('circle');
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return ()=> window.removeEventListener('keydown', onKeyDown);
  }, [engine, handleScreenshot, handleToggleRecording]);

  // Pointer Handlers
  const handlePointerDown = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const coords = getGridCoords(e);
    if (!coords) return;

    // Push undo snapshot at stroke start (grouped per stroke)
    if (brushShape !== 'picker') triggerUndoPush();

    isDrawingRef.current = true;
    setIsPointerActive(true);
    lastPosRef.current = coords;

    const el = engine.getElementAt(coords.x, coords.y);
    const idx = engine.getIndex(coords.x, coords.y);
    setInspectedElement({
      x: coords.x,
      y: coords.y,
      element: el,
      temp: Math.round(engine.gridTemp[idx])
    });

    applyPaint(coords.x, coords.y);
  };

  const handlePointerMove = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const coords = getGridCoords(e);
    if (!coords) return;

    setIsPointerActive(true);
    if (isDrawingRef.current) {
      applyPaint(coords.x, coords.y);
    }

    const el = engine.getElementAt(coords.x, coords.y);
    const idx = engine.getIndex(coords.x, coords.y);
    setInspectedElement({
      x: coords.x,
      y: coords.y,
      element: el,
      temp: Math.round(engine.gridTemp[idx])
    });
  };

  const handlePointerUp = () => {
    isDrawingRef.current = false;
    setIsPointerActive(false);
    lastPosRef.current = null;
    // allow next stroke to push new undo grouping
    hasPushedUndoRef.current = false;
    setUndoTick(t=> t+1);
  };

  // Capture periodic DVR snapshots and Recharts Telemetry
  useEffect(() => {
    const timer = setInterval(() => {
      // 1. DVR Snapshot
      if (!isPaused && dvrIndex === -1) {
        const serialized = engine.serializeState();
        setSnapshots(prev => [...prev.slice(-30), serialized]);
      }

      // 2. Telemetry History for Recharts
      const diag = engine.getDiagnostics();
      const timeLabel = new Date().toLocaleTimeString([], { hour12: false, minute: '2-digit', second: '2-digit' });
      setAnalyticsHistory(prev => [...prev.slice(-40), {
        time: timeLabel,
        fps,
        particles: diag.activeParticles,
        diversity: 12,
        maxTemp: diag.maxTemp,
        avgTemp: diag.avgTemp
      }]);
    }, 1000);

    return () => clearInterval(timer);
  }, [engine, isPaused, dvrIndex, fps]);

  // Main Render Loop
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
      }
      if (frameCountRef.current % 2 === 0) {
        setRenderTick(t => t + 1);
        setScreenShake(s => (s > 0 ? Math.max(0, s - 1) : 0));
      }

      if (!isPaused && dvrIndex === -1) {
        speedAccumulatorRef.current += Math.max(0.001, simSpeed);
        let stepsExecuted = 0;
        while (speedAccumulatorRef.current >= 1 && stepsExecuted < 10) {
          engine.step();
          speedAccumulatorRef.current -= 1;
          stepsExecuted++;
        }
        if (speedAccumulatorRef.current > 5) {
          speedAccumulatorRef.current = 0;
        }
      } else {
        speedAccumulatorRef.current = 0;
      }

      const canvas = canvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          engine.renderToCanvas(ctx, heatmapMode);
        }
      }

      animId = requestAnimationFrame(renderLoop);
    };

    animId = requestAnimationFrame(renderLoop);
    return () => cancelAnimationFrame(animId);
  }, [engine, isPaused, simSpeed, heatmapMode, dvrIndex]);

  // DVR Scrubbing controls
  const handleScrubDvr = (index: number) => {
    setDvrIndex(index);
    if (index >= 0 && index < snapshots.length) {
      engine.deserializeState(snapshots[index]);
    }
  };

  const handleReturnToLive = () => {
    setDvrIndex(-1);
    if (snapshots.length > 0) {
      engine.deserializeState(snapshots[snapshots.length - 1]);
    }
  };

  // God Tools Disaster Event Trigger Handlers
  const handleTriggerMeteor = () => {
    soundEngine.playMeteor();
    soundEngine.playExplosion(2.0);
    setScreenShake(16);
    const cx = Math.floor(engine.width / 2);

    // Spawn massive fiery magma meteor at top of screen with downward velocity
    for (let dy = -12; dy <= 12; dy++) {
      for (let dx = -12; dx <= 12; dx++) {
        if (dx * dx + dy * dy <= 144) {
          const x = cx + dx;
          const y = 18 + dy;
          if (engine.isValid(x, y)) {
            const idx = engine.getIndex(x, y);
            engine.gridType[idx] = Math.random() < 0.8 ? 6 : 4; // Lava & Fire
            engine.gridTemp[idx] = 2800;
            engine.gridVx[idx] = Math.round((Math.random() - 0.5) * 6);
            engine.gridVy[idx] = 18; // High downward kinetic impact
          }
        }
      }
    }

    // Trigger explosive impact crater when meteor hits ground
    setTimeout(() => {
      const impactY = Math.floor(engine.height * 0.65);
      engine.triggerExplosion(cx, impactY, 35, 18, 3000);
      setScreenShake(24);
      soundEngine.playExplosion(2.5);
    }, 200);
  };

  const handleTriggerNuke = () => {
    soundEngine.playExplosion(3.0);
    setScreenShake(26);
    const cx = Math.floor(engine.width / 2);
    const cy = Math.floor(engine.height / 2);

    // Primary nuclear shockwave explosion
    engine.triggerExplosion(cx, cy, 45, 22, 3500);

    // Staggered secondary shockwave blasts across map
    setTimeout(() => {
      engine.triggerExplosion(cx - 25, cy - 18, 28, 18, 3000);
      engine.triggerExplosion(cx + 25, cy + 18, 28, 18, 3000);
      setScreenShake(18);
      soundEngine.playExplosion(2.0);
    }, 120);
  };

  const handleTriggerTsunami = () => {
    soundEngine.playAcidFizz();
    const startY = Math.floor(engine.height * 0.25);

    // Massive 30-cell tall rushing water wave with horizontal velocity
    for (let y = startY; y < engine.height - 2; y++) {
      for (let x = 2; x < 30; x++) {
        if (engine.isValid(x, y)) {
          const idx = engine.getIndex(x, y);
          engine.gridType[idx] = 2; // Water
          engine.gridTemp[idx] = 12;
          engine.gridVx[idx] = 16; // High horizontal wave velocity
          engine.gridVy[idx] = -2;
        }
      }
    }
  };

  const handleTriggerFreeze = () => {
    soundEngine.playFreeze();

    // Flash-freeze grid to -200°C & freeze liquids to Ice/Obsidian
    for (let i = 0; i < engine.gridType.length; i++) {
      const t = engine.gridType[i];
      if (t !== 0 && t !== 29) {
        engine.gridTemp[i] = -200;
        if (t === 2 || t === 8 || t === 9) { // Water, Acid, Oil -> Ice
          engine.gridType[i] = 13;
        } else if (t === 6) { // Lava -> Obsidian / Stone
          engine.gridType[i] = 7;
        }
      }
    }
  };

  const activeElObj = registry.getElement(selectedElement);
  const allElements = registry.getAllElements().filter(e => e.id !== 0);
  const filteredElements = (
    activeCategory === 'All'
      ? allElements
      : registry.getElementsByCategory(activeCategory)
  ).filter(e =>
    e.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    e.id.toString() === searchTerm
  );

  const [activeMenu, setActiveMenu] = useState<'elements' | 'spawner' | 'settings' | 'texture' | null>(null);
  const [isDebugOpen, setIsDebugOpen] = useState<boolean>(false);
  const [isPerfOpen, setIsPerfOpen] = useState<boolean>(false);

  const toggleMenu = (menu: 'elements' | 'spawner' | 'settings' | 'texture') => {
    setActiveMenu(prev => (prev === menu ? null : menu));
  };

  return (
    <div className="relative w-full h-[calc(100vh-65px)] bg-neutral-950 text-white flex flex-col p-2 overflow-hidden select-none">
      {/* Full-bleed Main Canvas Container */}
      <div
        ref={containerRef}
        className="relative w-full h-full flex-1 bg-black rounded-2xl border border-neutral-800 shadow-2xl overflow-hidden flex items-center justify-center group transition-transform duration-75"
        style={{
          transform: screenShake > 0
            ? `translate(${(Math.random() - 0.5) * screenShake * 1.5}px, ${(Math.random() - 0.5) * screenShake * 1.5}px)`
            : 'none'
        }}
      >
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
          className="w-full h-full object-fill cursor-crosshair touch-none select-none"
          style={{ imageRendering: 'pixelated' }}
        />

        {/* Heatmap Temperature Scale Legend HUD Bar with Real-Time Indicator Line & Element Badge */}
        {heatmapMode !== 'normal' && (() => {
          let liveSpectrumEl: ElementDefinition = registry.getElement(selectedElement) || {
            id: selectedElement,
            name: 'Selected Element',
            category: 'Solids',
            state: 'solid',
            color: '#fbbf24',
            density: 1,
            defaultTemp: 20
          };
          let liveSpectrumTemp: number = liveSpectrumEl.defaultTemp ?? 20;

          if (inspectedElement) {
            const liveIdx = engine.getIndex(inspectedElement.x, inspectedElement.y);
            if (liveIdx >= 0 && liveIdx < engine.gridType.length) {
              const typeId = engine.gridType[liveIdx];
              const elAtCell = registry.getElement(typeId);
              if (typeId !== 0 && elAtCell) {
                liveSpectrumEl = elAtCell;
              }
              liveSpectrumTemp = Math.round(engine.gridTemp[liveIdx] ?? inspectedElement.temp);
            }
          }

          const gridDiagnostics = engine.getDiagnostics();
          const gridMaxTemp = Math.round(gridDiagnostics.maxTemp ?? 0);
          const spectrumPercent = getTempSpectrumPercent(liveSpectrumTemp);

          return (
            <div className="absolute bottom-3 left-3 right-3 sm:left-auto sm:right-5 sm:w-96 p-3 rounded-2xl bg-neutral-900/95 backdrop-blur-md border border-neutral-800 shadow-2xl z-20 flex flex-col gap-1.5 animate-in fade-in duration-200">
              <div className="flex items-center justify-between text-[11px] font-bold">
                <span className="text-cyan-400 flex items-center gap-1.5">
                  <Thermometer className="w-4 h-4 text-orange-400" />
                  <span>Thermal Colormap Spectrum</span>
                </span>
                <span className="text-amber-300 font-mono text-[10px] px-2 py-0.5 rounded-full bg-amber-500/10 border border-amber-500/20">
                  {heatmapMode === 'temp_overlay' ? 'Heatmap Overlay' : 'Pure Thermal Vision'}
                </span>
              </div>

              {/* Gradient Spectrum Bar with Live Indicator Line */}
              <div className="relative w-full h-4 rounded-lg bg-gradient-to-r from-blue-600 via-teal-400 via-yellow-400 via-orange-500 to-rose-600 shadow-inner border border-white/20 my-3">
                {/* Live Element Indicator Marker & Real-Time Temperature Badge */}
                <div
                  className="absolute top-0 bottom-0 z-30 transition-all duration-75 pointer-events-none"
                  style={{ left: `${Math.max(0, Math.min(100, spectrumPercent))}%` }}
                >
                  {/* Small sharp vertical indicator line */}
                  <div className="w-[3px] h-full bg-white shadow-[0_0_10px_rgba(255,255,255,1)] -translate-x-1/2 rounded-full" />

                  {/* Floating badge showing element name & real-time temperature */}
                  <div className="absolute -top-7 -translate-x-1/2 flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-neutral-950/95 border border-white/60 text-white shadow-2xl whitespace-nowrap text-[10px] font-mono font-extrabold z-40">
                    <div
                      className="w-2.5 h-2.5 rounded-full border border-white/40 shrink-0"
                      style={{ backgroundColor: liveSpectrumEl.color }}
                    />
                    <span>{liveSpectrumEl.name}</span>
                    <span className="text-amber-300 font-bold">({formatTemp(liveSpectrumTemp)})</span>
                  </div>
                </div>

                {/* Grid Peak Temperature Flame Indicator */}
                {gridMaxTemp > 50 && Math.abs(gridMaxTemp - liveSpectrumTemp) > 40 && (
                  <div
                    className="absolute top-0 bottom-0 z-20 transition-all duration-200 pointer-events-none"
                    style={{ left: `${Math.max(0, Math.min(100, getTempSpectrumPercent(gridMaxTemp)))}%` }}
                  >
                    <div className="w-[2px] h-full bg-rose-500 shadow-[0_0_6px_rgba(244,63,94,0.9)] -translate-x-1/2" />
                    <div className="absolute -bottom-6 -translate-x-1/2 px-1.5 py-0.2 rounded bg-rose-950/90 border border-rose-500/50 text-rose-200 font-mono text-[9px] font-bold shadow-md whitespace-nowrap flex items-center gap-0.5">
                      <Flame className="w-2.5 h-2.5 text-yellow-400" />
                      <span>Peak: {formatTemp(gridMaxTemp)}</span>
                    </div>
                  </div>
                )}
              </div>

              {/* Temperature Scale Tick Marks */}
              <div className="flex items-center justify-between font-mono text-[9px] text-neutral-400 px-0.5">
                <span>-100°C</span>
                <span>0°C</span>
                <span>20°C</span>
                <span>100°C</span>
                <span>500°C</span>
                <span>3000°C</span>
              </div>
            </div>
          );
        })()}

        {isPointerActive && inspectedElement && (
          <div
            className="absolute pointer-events-none -translate-x-1/2 -translate-y-1/2 border border-amber-400/80 bg-amber-400/10 rounded-full shadow-[0_0_10px_rgba(251,191,36,0.3)] z-10 flex items-center justify-center"
            style={{
              left: `${(inspectedElement.x / engine.width) * 100}%`,
              top: `${(inspectedElement.y / engine.height) * 100}%`,
              width: `${(Math.max(2, brushSize) * 2 / engine.width) * 100}%`,
              height: `${(Math.max(2, brushSize) * 2 / engine.height) * 100}%`,
              minWidth: '8px',
              minHeight: '8px'
            }}
          >
            <div className="w-1 h-1 rounded-full bg-amber-400" />
          </div>
        )}

        {/* Floating Minimal HUD Bar */}
        <div className="absolute top-2 left-2 right-2 sm:top-3.5 sm:left-4 sm:right-4 flex items-center justify-between gap-1 sm:gap-1.5 pointer-events-auto z-20 max-w-full overflow-x-auto no-scrollbar py-0.5 scroll-smooth">
          {/* Left Controls: FPS & Element Picker */}
          <div className="flex items-center gap-1 sm:gap-1.5 shrink-0">
            {/* FPS Badge */}
            <div className="flex items-center gap-1 font-mono px-1.5 sm:px-2 py-1 rounded-xl bg-neutral-900/90 backdrop-blur-md border border-neutral-800/80 shadow-lg font-bold text-xs">
              <span className={`w-2 h-2 rounded-full ${fps >= 50 ? 'bg-emerald-400' : fps >= 30 ? 'bg-amber-400' : 'bg-red-400'} animate-pulse`} />
              <span className="text-amber-400">{fps}</span>
              <span className="text-neutral-500 text-[10px] hidden xs:inline">FPS</span>
            </div>

            {/* Selected Element Pill */}
            <button
              onClick={() => toggleMenu('elements')}
              className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-xl backdrop-blur-md border shadow-lg font-bold text-xs transition-all shrink-0 ${
                activeMenu === 'elements'
                  ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow-amber-500/20'
                  : 'bg-neutral-900/90 text-amber-200 border-neutral-800 hover:border-amber-500/50'
              }`}
              title="Select Element or Tool"
            >
              <div
                className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full border border-white/20 shrink-0"
                style={{ backgroundColor: activeElObj.color }}
              />
              <span className={`text-xs font-semibold max-w-[45px] xs:max-w-[80px] sm:max-w-[110px] truncate ${activeMenu === 'elements' ? 'text-neutral-950' : 'text-amber-200'}`}>
                {activeElObj.name}
              </span>
              <ChevronDown className={`w-3 h-3 shrink-0 transition-transform ${activeMenu === 'elements' ? 'rotate-180' : ''}`} />
            </button>

            {/* Heatmap Overlay Toggle Button */}
            <button
              onClick={() => {
                const modes: ('normal' | 'temp_overlay' | 'temp')[] = ['normal', 'temp_overlay', 'temp'];
                const nextIdx = (modes.indexOf(heatmapMode) + 1) % modes.length;
                setHeatmapMode(modes[nextIdx]);
              }}
              className={`flex items-center gap-1 px-2 py-1 rounded-xl backdrop-blur-md border shadow-lg font-bold text-xs transition-all shrink-0 ${
                heatmapMode !== 'normal'
                  ? 'bg-gradient-to-r from-orange-500 to-rose-600 text-white border-orange-400'
                  : 'bg-neutral-900/90 text-neutral-300 border-neutral-800 hover:text-white'
              }`}
              title="Toggle Heatmap Overlay Mode"
            >
              <Thermometer className="w-3.5 h-3.5 text-orange-400" />
              <span className="hidden md:inline">
                {heatmapMode === 'normal' ? 'Heatmap: OFF' : heatmapMode === 'temp_overlay' ? 'Heat Overlay' : 'Pure Thermal'}
              </span>
            </button>
          </div>

          {/* Right Controls: Start/Stop, DVR Time Travel, Analytics, Disasters, Settings, Sound */}
          <div className="flex items-center gap-1 sm:gap-1.5 shrink-0">
              {/* Settings & Environment Modal Toggle */}
              <button
                onClick={() => setIsSettingsOpen(!isSettingsOpen)}
                className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                  isSettingsOpen
                    ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow-amber-500/20'
                    : 'bg-neutral-900/90 text-amber-300 border-neutral-800 hover:bg-neutral-800'
                }`}
                title="Settings & Environment"
              >
                <Sliders className="w-3.5 h-3.5" />
              </button>

              {/* Undo / Redo */}
              <div className="flex items-center rounded-xl overflow-hidden border border-neutral-800 bg-neutral-900/90 backdrop-blur-md shadow-lg">
                <button
                  onClick={()=> { if (engine.canUndo()) { engine.undo(); setUndoTick(t=>t+1); }}}
                  disabled={!engine.canUndo()}
                  className={`p-1.5 text-xs font-bold ${engine.canUndo() ? 'text-amber-300 hover:bg-neutral-800' : 'text-neutral-600'}`}
                  title="Undo (Ctrl+Z)"
                >
                  <Undo2 className="w-3.5 h-3.5" />
                </button>
                <div className="w-px h-4 bg-neutral-800" />
                <button
                  onClick={()=> { if (engine.canRedo()) { engine.redo(); setUndoTick(t=>t+1); }}}
                  disabled={!engine.canRedo()}
                  className={`p-1.5 text-xs font-bold ${engine.canRedo() ? 'text-amber-300 hover:bg-neutral-800' : 'text-neutral-600'}`}
                  title="Redo (Ctrl+Shift+Z)"
                >
                  <Redo2 className="w-3.5 h-3.5" />
                </button>
              </div>

              {/* Screenshot & Recording */}
              <button
                onClick={handleScreenshot}
                className="p-1.5 rounded-xl bg-neutral-900/90 hover:bg-neutral-800 border border-neutral-800 text-neutral-300 shadow-lg backdrop-blur-md"
                title="Screenshot PNG (S)"
              >
                <Camera className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={handleToggleRecording}
                className={`p-1.5 rounded-xl border shadow-lg backdrop-blur-md text-xs font-bold ${isRecording ? 'bg-red-600 text-white border-red-500 animate-pulse' : 'bg-neutral-900/90 text-red-300 border-neutral-800 hover:bg-neutral-800'}`}
                title={isRecording ? 'Stop Recording (R)' : 'Start Recording WebM (R)'}
              >
                {isRecording ? <VideoOff className="w-3.5 h-3.5" /> : <Video className="w-3.5 h-3.5" />}
              </button>

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

            {/* DVR Physics Time Travel Scrubber Toggle */}
            <button
              onClick={() => setIsDvrOpen(!isDvrOpen)}
              className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                isDvrOpen
                  ? 'bg-cyan-500 text-neutral-950 border-cyan-400'
                  : 'bg-neutral-900/90 text-cyan-300 border-neutral-800 hover:bg-neutral-800'
              }`}
              title="Physics Time Travel & Rewind (DVR)"
            >
              <History className="w-3.5 h-3.5" />
            </button>

            {/* Recharts Telemetry Analytics Dashboard Toggle */}
            <button
              onClick={() => setIsAnalyticsOpen(true)}
              className="p-1.5 rounded-xl bg-purple-950/80 hover:bg-purple-900 border border-purple-500/40 text-purple-300 text-xs font-bold transition-all shadow-lg backdrop-blur-md shrink-0"
              title="Open Recharts Real-Time Analytics Dashboard"
            >
              <BarChart3 className="w-3.5 h-3.5" />
            </button>

            {/* God Tools Disaster Trigger Menu Toggle */}
            <button
              onClick={() => setIsDisasterMenuOpen(!isDisasterMenuOpen)}
              className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                isDisasterMenuOpen
                  ? 'bg-rose-500 text-neutral-950 border-rose-400'
                  : 'bg-neutral-900/90 text-rose-300 border-neutral-800 hover:bg-neutral-800'
              }`}
              title="God Tools Environmental Disasters"
            >
              <Bomb className="w-3.5 h-3.5" />
            </button>

            {/* Web Audio Mute/Unmute */}
            <button
              onClick={() => {
                const next = !soundEnabled;
                setSoundEnabled(next);
                soundEngine.enabled = next;
              }}
              className="p-1.5 rounded-xl bg-neutral-900/90 hover:bg-neutral-800 border border-neutral-800 text-neutral-300 text-xs font-bold transition-all shrink-0"
              title={soundEnabled ? "Mute Web Audio Sound Effects" : "Unmute Web Audio Sound Effects"}
            >
              {soundEnabled ? <Volume2 className="w-3.5 h-3.5 text-emerald-400" /> : <VolumeX className="w-3.5 h-3.5 text-neutral-500" />}
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
              className="p-1.5 rounded-xl bg-amber-950/80 hover:bg-amber-900 border border-amber-500/40 text-amber-300 text-xs font-bold transition-all shadow-lg backdrop-blur-md shrink-0"
              title="Open Performance Tuning Menu"
            >
              <Gauge className="w-3.5 h-3.5" />
            </button>

            {/* PROMINENT CLEAR BUTTON */}
            <button
              onClick={() => { engine.clear(); setUndoTick(t=>t+1); }}
              className="flex items-center gap-1 px-2 py-1.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/30 transition-all border border-red-400/50 active:scale-95 shrink-0"
              title="Clear Powder Canvas Grid (C)"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Clear</span>
            </button>
          </div>
        </div>

        {/* Floating DVR Physics Time Scrubber Drawer */}
        {isDvrOpen && (
          <div className="absolute top-16 left-3 right-3 sm:left-auto sm:right-5 sm:w-96 bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-3.5 shadow-2xl z-30 flex flex-col gap-3 animate-in fade-in duration-200">
            <div className="flex items-center justify-between border-b border-neutral-800 pb-2">
              <div className="flex items-center gap-2 text-xs font-bold text-cyan-300">
                <History className="w-4 h-4 text-cyan-400" />
                <span>Physics Time Scrubber (Snapshot DVR)</span>
              </div>
              {dvrIndex !== -1 && (
                <button
                  onClick={handleReturnToLive}
                  className="px-2 py-0.5 rounded-lg bg-emerald-500 text-neutral-950 text-[10px] font-bold"
                >
                  Return to Live
                </button>
              )}
            </div>

            <div className="flex flex-col gap-1.5">
              <div className="flex items-center justify-between text-xs text-neutral-400 font-mono">
                <span>{dvrIndex === -1 ? 'LIVE Stream' : `Snapshot Frame -${snapshots.length - dvrIndex}s`}</span>
                <span>{snapshots.length} frames saved</span>
              </div>

              <input
                type="range"
                min="0"
                max={Math.max(0, snapshots.length - 1)}
                value={dvrIndex === -1 ? snapshots.length - 1 : dvrIndex}
                onChange={e => handleScrubDvr(parseInt(e.target.value))}
                className="w-full accent-cyan-400 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />

              <div className="flex items-center justify-between gap-2 mt-1">
                <button
                  onClick={() => handleScrubDvr(Math.max(0, (dvrIndex === -1 ? snapshots.length - 1 : dvrIndex) - 5))}
                  className="flex-1 py-1 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-neutral-200 text-xs font-semibold flex items-center justify-center gap-1"
                >
                  <Rewind className="w-3.5 h-3.5 text-cyan-400" />
                  <span>Rewind 5s</span>
                </button>

                <button
                  onClick={handleReturnToLive}
                  className={`flex-1 py-1 rounded-lg text-xs font-bold flex items-center justify-center gap-1 ${
                    dvrIndex === -1 ? 'bg-cyan-500 text-neutral-950' : 'bg-neutral-800 text-neutral-300 hover:text-white'
                  }`}
                >
                  <Radio className="w-3.5 h-3.5" />
                  <span>Live Stream</span>
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Floating God Tools Disaster Triggers Menu */}
        {isDisasterMenuOpen && (
          <div className="absolute top-16 right-3 sm:right-5 sm:w-80 bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-3.5 shadow-2xl z-30 flex flex-col gap-3 animate-in fade-in duration-200">
            <div className="flex items-center justify-between border-b border-neutral-800 pb-2">
              <span className="text-xs font-bold text-rose-400 flex items-center gap-2">
                <Bomb className="w-4 h-4" />
                <span>God Tools Disaster Triggers</span>
              </span>
              <button
                onClick={() => setIsDisasterMenuOpen(false)}
                className="text-neutral-500 hover:text-white text-xs"
              >
                ✕
              </button>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={handleTriggerMeteor}
                className="p-2.5 rounded-xl bg-orange-950/40 border border-orange-500/40 hover:border-orange-400 text-left transition-all"
              >
                <div className="text-xs font-bold text-orange-300 flex items-center gap-1.5">
                  <Flame className="w-3.5 h-3.5 text-orange-400" />
                  Meteor Strike
                </div>
                <div className="text-[10px] text-neutral-400 mt-0.5">Flaming magma strike</div>
              </button>

              <button
                onClick={handleTriggerNuke}
                className="p-2.5 rounded-xl bg-rose-950/40 border border-rose-500/40 hover:border-rose-400 text-left transition-all"
              >
                <div className="text-xs font-bold text-rose-300 flex items-center gap-1.5">
                  <Zap className="w-3.5 h-3.5 text-rose-400" />
                  Nuke Shockwave
                </div>
                <div className="text-[10px] text-neutral-400 mt-0.5">3000°C plasma blast</div>
              </button>

              <button
                onClick={handleTriggerTsunami}
                className="p-2.5 rounded-xl bg-blue-950/40 border border-blue-500/40 hover:border-blue-400 text-left transition-all"
              >
                <div className="text-xs font-bold text-blue-300 flex items-center gap-1.5">
                  <Droplet className="w-3.5 h-3.5 text-blue-400" />
                  Tsunami Wave
                </div>
                <div className="text-[10px] text-neutral-400 mt-0.5">Rushing water wave</div>
              </button>

              <button
                onClick={handleTriggerFreeze}
                className="p-2.5 rounded-xl bg-cyan-950/40 border border-cyan-500/40 hover:border-cyan-400 text-left transition-all"
              >
                <div className="text-xs font-bold text-cyan-300 flex items-center gap-1.5">
                  <Thermometer className="w-3.5 h-3.5 text-cyan-400" />
                  Deep Freeze
                </div>
                <div className="text-[10px] text-neutral-400 mt-0.5">-150°C cryo freeze</div>
              </button>
            </div>
          </div>
        )}

        {/* Floating Menu Drawer Panels for Elements, Spawner, Settings */}
        {activeMenu === 'elements' && (
          <div className="absolute top-16 left-3 right-3 sm:left-4 sm:w-[460px] max-h-[calc(100%-80px)] overflow-y-auto bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-30 flex flex-col gap-3 animate-in fade-in slide-in-from-top-4">
            <div className="flex items-center justify-between pb-2 border-b border-neutral-800">
              <span className="text-xs font-bold text-amber-400">Select Element or Brush Tool</span>
              <button onClick={() => setActiveMenu(null)} className="text-neutral-400 hover:text-white text-xs">✕</button>
            </div>

            {/* Brush Tools Grid */}
            <div className="flex items-center gap-1.5 overflow-x-auto pb-2 no-scrollbar border-b border-neutral-800">
              {[
                { id: 'circle', name: 'Circle', icon: Circle },
                { id: 'square', name: 'Square', icon: Square },
                { id: 'spray', name: 'Spray', icon: Sparkles },
                { id: 'line', name: 'Line', icon: Pencil },
                { id: 'fill', name: 'Bucket', icon: PaintBucket },
                { id: 'eraser', name: 'Eraser', icon: Eraser },
                { id: 'picker', name: 'Picker', icon: Pipette }
              ].map(tool => {
                const Icon = tool.icon;
                return (
                  <button
                    key={tool.id}
                    onClick={() => setBrushShape(tool.id as any)}
                    className={`p-2 rounded-xl border text-xs font-medium flex items-center gap-1.5 shrink-0 transition-all ${
                      brushShape === tool.id
                        ? 'bg-amber-500 text-neutral-950 border-amber-400 font-bold'
                        : 'bg-neutral-950 border-neutral-800 text-neutral-300 hover:text-white'
                    }`}
                  >
                    <Icon className="w-3.5 h-3.5" />
                    <span>{tool.name}</span>
                  </button>
                );
              })}
            </div>

            {/* Size Slider */}
            <div className="flex items-center gap-3 bg-neutral-950 p-2.5 rounded-xl border border-neutral-800 text-xs">
              <span className="text-neutral-400 font-bold min-w-[70px]">Brush Size:</span>
              <input
                type="range"
                min="1"
                max="25"
                value={brushSize}
                onChange={e => setBrushSize(parseInt(e.target.value))}
                className="w-full accent-amber-500 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
              />
              <span className="font-mono text-amber-300 font-bold min-w-[30px] text-right">{brushSize}px</span>
            </div>

            {/* Search Input */}
            <input
              type="text"
              placeholder="Search 500 elements..."
              value={searchTerm}
              onChange={e => setSearchTerm(e.target.value)}
              className="w-full px-3 py-2 rounded-xl bg-neutral-950 border border-neutral-800 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-amber-500"
            />

            {/* Category Tabs */}
            <div className="flex items-center gap-1 overflow-x-auto pb-1 no-scrollbar text-[11px] font-bold">
              {categories.map(cat => (
                <button
                  key={cat}
                  onClick={() => setActiveCategory(cat)}
                  className={`px-2.5 py-1 rounded-lg shrink-0 transition-all ${
                    activeCategory === cat ? 'bg-amber-500 text-neutral-950 font-bold' : 'bg-neutral-950 text-neutral-400 hover:text-white'
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>

            {/* Elements Grid */}
            <div className="grid grid-cols-3 sm:grid-cols-4 gap-1.5 max-h-60 overflow-y-auto pr-1 scrollbar-thin">
              {filteredElements.map(el => (
                <button
                  key={el.id}
                  onClick={() => { setSelectedElement(el.id); setActiveMenu(null); }}
                  className={`p-2 rounded-xl border text-left transition-all flex items-center gap-2 ${
                    selectedElement === el.id
                      ? 'bg-amber-500/20 border-amber-500 text-white shadow-md'
                      : 'bg-neutral-950 border-neutral-800/80 text-neutral-300 hover:border-neutral-700'
                  }`}
                >
                  <div className="w-3 h-3 rounded-full shrink-0 border border-white/20" style={{ backgroundColor: el.color }} />
                  <span className="text-xs font-semibold truncate">{el.name}</span>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Floating Settings & Environment Modal Panel */}
        {isSettingsOpen && (
          <div className="absolute top-16 right-3 sm:right-5 w-[calc(100%-24px)] sm:w-[420px] max-h-[calc(100%-80px)] overflow-y-auto bg-neutral-900/98 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-40 flex flex-col gap-3.5 animate-in fade-in duration-150 scrollbar-thin">
            {/* Header */}
            <div className="flex items-center justify-between border-b border-neutral-800 pb-2.5">
              <div className="flex items-center gap-2 text-amber-400 font-extrabold text-sm">
                <FastForward className="w-4 h-4 text-amber-400" />
                <span>Settings & Environment</span>
              </div>
              <button
                onClick={() => setIsSettingsOpen(false)}
                className="px-2 py-1 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-neutral-300 hover:text-white text-xs font-bold transition-all flex items-center gap-1"
              >
                <span>× Close</span>
              </button>
            </div>

            {/* Temperature Scale & Ambient Room Temperature */}
            <div className="p-3.5 rounded-xl bg-neutral-950/90 border border-neutral-800/80 flex flex-col gap-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-neutral-300">Temperature Scale:</span>
                <div className="flex items-center gap-1 bg-neutral-900 p-1 rounded-xl border border-neutral-800">
                  <button
                    onClick={() => setTempUnit('C')}
                    className={`px-3 py-1 rounded-lg font-bold text-xs transition-all ${
                      tempUnit === 'C'
                        ? 'bg-amber-500 text-neutral-950 shadow-md font-extrabold'
                        : 'text-neutral-400 hover:text-white'
                    }`}
                  >
                    °C Celsius
                  </button>
                  <button
                    onClick={() => setTempUnit('F')}
                    className={`px-3 py-1 rounded-lg font-bold text-xs transition-all ${
                      tempUnit === 'F'
                        ? 'bg-amber-500 text-neutral-950 shadow-md font-extrabold'
                        : 'text-neutral-400 hover:text-white'
                    }`}
                  >
                    °F Fahrenheit
                  </button>
                </div>
              </div>

              <div className="flex flex-col gap-1.5 pt-1">
                <div className="flex items-center justify-between text-xs font-bold">
                  <span className="text-neutral-300">Ambient Room Temperature:</span>
                  <span className="text-amber-400 font-mono">{formatTemp(ambientTemp)}</span>
                </div>
                <input
                  type="range"
                  min="-50"
                  max="200"
                  value={ambientTemp}
                  onChange={(e) => {
                    const val = parseInt(e.target.value);
                    setAmbientTemp(val);
                    engine.ambientTemp = val;
                  }}
                  className="w-full accent-amber-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
                />
              </div>
            </div>

            {/* Gravity Direction */}
            <div className="p-3.5 rounded-xl bg-neutral-950/90 border border-neutral-800/80 flex flex-col gap-2.5">
              <span className="text-xs font-bold text-neutral-300">Gravity Direction:</span>
              <div className="grid grid-cols-5 gap-1.5">
                {[
                  { dir: 'down', label: '↓' },
                  { dir: 'up', label: '↑' },
                  { dir: 'left', label: '←' },
                  { dir: 'right', label: '→' },
                  { dir: 'zero', label: '0G' }
                ].map(item => (
                  <button
                    key={item.dir}
                    onClick={() => updateGravity(item.dir as any)}
                    className={`py-2 rounded-xl border text-center font-extrabold text-xs transition-all flex items-center justify-center ${
                      gravityDir === item.dir
                        ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow-lg shadow-amber-500/20'
                        : 'bg-neutral-900 border-neutral-800 text-neutral-300 hover:bg-neutral-800 hover:text-white'
                    }`}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Wind Control */}
            <div className="p-3.5 rounded-xl bg-neutral-950/90 border border-neutral-800/80 flex flex-col gap-2.5">
              <div className="flex items-center justify-between text-xs font-bold">
                <span className="text-blue-300 flex items-center gap-1.5">
                  <Wind className="w-3.5 h-3.5" />
                  <span>Horizontal Wind Drift:</span>
                </span>
                <span className="text-blue-300 font-mono">{windX >0 ? `→ ${windX.toFixed(1)}` : windX <0 ? `← ${Math.abs(windX).toFixed(1)}` : '0'}</span>
              </div>
              <input
                type="range"
                min="-5"
                max="5"
                step="0.5"
                value={windX}
                onChange={(e)=> {
                  const v = parseFloat(e.target.value);
                  setWindX(v);
                  engine.setWind(v);
                }}
                className="w-full accent-blue-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />
              <div className="flex justify-between text-[10px] text-neutral-500 font-mono"><span>← West</span><span>Calm</span><span>East →</span></div>
              <label className="flex items-center gap-2 text-xs text-neutral-300 mt-1">
                <input type="checkbox" checked={engine.heatConductionEnabled} onChange={(e)=> {engine.heatConductionEnabled = e.target.checked; setUndoTick(t=>t+1);}} className="rounded" />
                <span>Heat Conduction Diffusion</span>
              </label>
            </div>

            {/* Simulation Speed */}
            <div className="p-3.5 rounded-xl bg-neutral-950/90 border border-neutral-800/80 flex flex-col gap-2.5">
              <div className="flex items-center justify-between text-xs font-bold">
                <span className="text-amber-400 flex items-center gap-1.5">
                  <FastForward className="w-3.5 h-3.5" />
                  <span>Simulation Speed:</span>
                </span>
                <span className="text-amber-300 font-mono">{simSpeed.toFixed(2)}x</span>
              </div>

              <input
                type="range"
                min="0.02"
                max="2.0"
                step="0.01"
                value={simSpeed}
                onChange={(e) => setSimSpeed(parseFloat(e.target.value))}
                className="w-full accent-amber-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />

              <div className="grid grid-cols-6 gap-1 pt-1">
                {[0.02, 0.05, 0.1, 0.25, 0.5, 1.0].map(preset => (
                  <button
                    key={preset}
                    onClick={() => setSimSpeed(preset)}
                    className={`py-1 rounded-lg text-[10px] font-mono font-bold transition-all border ${
                      Math.abs(simSpeed - preset) < 0.01
                        ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow'
                        : 'bg-neutral-900 border-neutral-800 text-neutral-400 hover:text-white'
                    }`}
                  >
                    {preset === 1.0 ? '1x' : `${preset}x`}
                  </button>
                ))}
              </div>
            </div>

            {/* Grain Shading Style / Switch Texture Mode (Exact 2x2 grid from screenshot) */}
            <div className="p-3.5 rounded-xl bg-neutral-950/90 border border-neutral-800/80 flex flex-col gap-2.5">
              <div className="flex items-center justify-between text-xs font-bold">
                <span className="text-amber-400">Grain Shading Style:</span>
                <span className="text-[10px] text-neutral-400 font-normal">Switch Texture Mode</span>
              </div>

              <div className="grid grid-cols-2 gap-2">
                {[
                  {
                    id: 'natural_grain',
                    title: 'Natural Grains',
                    subtitle: 'Realistic static sand speckle'
                  },
                  {
                    id: 'organic_flow',
                    title: 'Organic Flow',
                    subtitle: 'Fluid sine wave shimmer'
                  },
                  {
                    id: 'diagonal_matrix',
                    title: 'Diagonal Matrix',
                    subtitle: 'Rolling diagonal waves'
                  },
                  {
                    id: 'flat',
                    title: 'Solid Flat Color',
                    subtitle: 'Crisp flat element fills'
                  }
                ].map((item) => {
                  const isActive = textureMode === item.id;
                  return (
                    <button
                      key={item.id}
                      onClick={() => updateTextureMode(item.id as any)}
                      className={`p-3 rounded-xl border text-left transition-all ${
                        isActive
                          ? 'bg-amber-500/15 border-amber-500/80 shadow-lg shadow-amber-500/10'
                          : 'bg-neutral-900/90 border-neutral-800/80 hover:bg-neutral-800/80 hover:border-neutral-700'
                      }`}
                    >
                      <div className={`font-bold text-xs ${isActive ? 'text-amber-400' : 'text-neutral-200'}`}>
                        {item.title}
                      </div>
                      <div className={`text-[10px] leading-snug mt-0.5 ${isActive ? 'text-amber-200/80' : 'text-neutral-400'}`}>
                        {item.subtitle}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        )}

      </div>

      {/* Modals */}
      <DebugMenuModal
        isOpen={isDebugOpen}
        onClose={() => setIsDebugOpen(false)}
        engineType="powder"
        powderEngine={engine}
        fps={fps}
      />

      <PerformanceMenuModal
        isOpen={isPerfOpen}
        onClose={() => setIsPerfOpen(false)}
        engineType="powder"
        powderEngine={engine}
        fps={fps}
        simSpeed={simSpeed}
        setSimSpeed={setSimSpeed}
      />

      <AnalyticsDashboardModal
        isOpen={isAnalyticsOpen}
        onClose={() => setIsAnalyticsOpen(false)}
        engineType="powder"
        powderEngine={engine}
        history={analyticsHistory}
        fps={fps}
        onClearHistory={() => setAnalyticsHistory([])}
      />
    </div>
  );
};
