import React, { useRef, useEffect, useState, useCallback } from 'react';
import { PowderEngine } from '../engine/powderEngine';
import { ElementRegistry } from '../engine/elementRegistry';
import { ElementDefinition } from '../types/physics';
import { DebugMenuModal } from './DebugMenuModal';
import { PerformanceMenuModal } from './PerformanceMenuModal';
import {
  Play, Pause, FastForward, RotateCcw, Trash2, StepForward,
  ArrowDown, ArrowUp, ArrowLeft, ArrowRight,
  Circle, Square, Pipette, PaintBucket, Eraser, Wind, Pencil, Sparkles,
  Wrench, Gauge, ChevronDown, Layers, Sliders
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
  const [simSpeed, setSimSpeed] = useState<number>(1); // 0.25, 0.5, 1, 2, 5
  const [selectedElement, setSelectedElement] = useState<number>(1); // Default Sand
  const [activeCategory, setActiveCategory] = useState<string>('Solids');

  // Brush Settings
  const [brushSize, setBrushSize] = useState<number>(5);
  const [brushShape, setBrushShape] = useState<'circle' | 'square' | 'spray' | 'line' | 'fill' | 'replace' | 'eraser' | 'picker'>('circle');

  // Environment & Spawner State
  const [gravityDir, setGravityDir] = useState<'down' | 'up' | 'left' | 'right' | 'zero'>('down');
  const [ambientTemp, setAmbientTemp] = useState<number>(20);
  const [tempUnit, setTempUnit] = useState<'C' | 'F'>('C');
  const [spawnCount, setSpawnCount] = useState<number>(10000);
  const [textureMode, setTextureMode] = useState<'diagonal_matrix' | 'natural_grain' | 'organic_flow' | 'flat'>('natural_grain');

  const formatTemp = useCallback((celsius: number) => {
    if (tempUnit === 'F') {
      const fahrenheit = Math.round((celsius * 9) / 5 + 32);
      return `${fahrenheit}°F`;
    }
    return `${Math.round(celsius)}°C`;
  }, [tempUnit]);

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
      // Bresenham's line algorithm for smooth continuous strokes
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

    // Emit socket event if multiplayer active
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
  }, [brushShape, brushSize, selectedElement, engine, onEmitDraw]);

  // Mouse & Touch Event Handlers
  const handlePointerDown = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const coords = getGridCoords(e);
    if (!coords) return;

    isDrawingRef.current = true;
    setIsPointerActive(true);
    lastPosRef.current = coords;

    // Update Inspector info
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

    // Hover inspector update
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
  };

  // Main Render Loop
  useEffect(() => {
    let animId: number;

    const renderLoop = () => {
      const now = performance.now();
      const delta = now - lastTimeRef.current;
      lastTimeRef.current = now;

      // Calculate FPS
      frameTimesRef.current.push(1000 / Math.max(1, delta));
      if (frameTimesRef.current.length > 30) frameTimesRef.current.shift();

      frameCountRef.current++;
      if (frameCountRef.current % 10 === 0) {
        const avgFps = Math.round(
          frameTimesRef.current.reduce((a, b) => a + b, 0) / frameTimesRef.current.length
        );
        setFps(avgFps);
      }

      // Step physics engine if not paused
      if (!isPaused) {
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

      // Render to canvas
      const canvas = canvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          engine.renderToCanvas(ctx, 'normal');
        }
      }

      animId = requestAnimationFrame(renderLoop);
    };

    animId = requestAnimationFrame(renderLoop);
    return () => cancelAnimationFrame(animId);
  }, [engine, isPaused, simSpeed]);

  // Current active element object & element filtering for all 500 slots
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

  // Menu Collapsible States
  const [activeMenu, setActiveMenu] = useState<'elements' | 'spawner' | 'settings' | null>(null);
  const [isDebugOpen, setIsDebugOpen] = useState<boolean>(false);
  const [isPerfOpen, setIsPerfOpen] = useState<boolean>(false);

  const toggleMenu = (menu: 'elements' | 'spawner' | 'settings') => {
    setActiveMenu(prev => (prev === menu ? null : menu));
  };

  return (
    <div className="relative w-full h-[calc(100vh-65px)] bg-neutral-950 text-white flex flex-col p-2 overflow-hidden select-none">
      {/* Full-bleed Main Canvas Container */}
      <div ref={containerRef} className="relative w-full h-full flex-1 bg-black rounded-2xl border border-neutral-800 shadow-2xl overflow-hidden flex items-center justify-center group">
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
        <div className="absolute top-3 left-3 right-4 sm:top-3.5 sm:left-4 sm:right-5 flex items-center justify-between gap-1 sm:gap-1.5 pointer-events-auto z-20 max-w-[calc(100%-28px)] overflow-x-auto no-scrollbar py-0.5 scroll-smooth">
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
          </div>

          {/* Right Controls: Start/Stop, Speed Slider, Spawner, Settings, Debug, Perf, Clear */}
          <div className="flex items-center gap-1 sm:gap-1.5 shrink-0 pr-3 sm:pr-2">
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
              onClick={() => toggleMenu('spawner')}
              className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                activeMenu === 'spawner'
                  ? 'bg-amber-500 text-neutral-950 border-amber-400 shadow-amber-500/20'
                  : 'bg-neutral-900/90 text-amber-300 border-neutral-800 hover:bg-neutral-800'
              }`}
              title="Bulk Spawner"
            >
              <Layers className="w-3.5 h-3.5" />
            </button>

            <button
              onClick={() => toggleMenu('settings')}
              className={`p-1.5 rounded-xl text-xs font-bold transition-all shadow-lg backdrop-blur-md border shrink-0 ${
                activeMenu === 'settings'
                  ? 'bg-amber-500 text-neutral-950 border-amber-400'
                  : 'bg-neutral-900/90 text-neutral-300 border-neutral-800 hover:bg-neutral-800'
              }`}
              title="Settings & Gravity"
            >
              <Sliders className="w-3.5 h-3.5" />
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
              onClick={() => engine.resetGrid()}
              className="flex items-center gap-1 px-2 py-1.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/30 transition-all border border-red-400/50 active:scale-95 shrink-0"
              title="Clear Canvas Grid"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Clear</span>
            </button>
          </div>
        </div>

        {/* Floating Inspector Badge positioned cleanly at bottom left of canvas */}
        {inspectedElement && (
          <div className="absolute bottom-3 left-3 flex items-center gap-2 px-3 py-1.5 rounded-xl bg-neutral-900/95 backdrop-blur-md border border-amber-500/50 text-white text-xs shadow-2xl pointer-events-auto z-20 animate-in fade-in duration-150">
            <div
              className="w-3.5 h-3.5 rounded-full border border-white/20 shrink-0"
              style={{ backgroundColor: inspectedElement.element.color }}
            />
            <span className="font-bold text-amber-300">{inspectedElement.element.name}</span>
            <span className="text-neutral-400 font-mono text-xs">
              ({inspectedElement.x}, {inspectedElement.y})
            </span>
            <span className="text-amber-400 font-mono text-xs font-bold">
              {formatTemp(inspectedElement.temp)}
            </span>
            <button
              onClick={(e) => {
                e.stopPropagation();
                setTempUnit(prev => prev === 'C' ? 'F' : 'C');
              }}
              className="ml-1 px-1.5 py-0.5 rounded bg-amber-500/20 hover:bg-amber-500/40 text-amber-300 border border-amber-500/40 font-mono font-bold text-[10px] transition-all cursor-pointer"
              title="Click to switch temperature unit (°C / °F)"
            >
              °{tempUnit} ⇄
            </button>
          </div>
        )}

        {/* Floating Menu Drawer Panels */}

        {/* Panel 1: Elements & Brush Tools Palette Overlay */}
        {activeMenu === 'elements' && (
          <div className="absolute top-16 right-3 left-3 sm:left-auto sm:w-[460px] max-h-[calc(100%-80px)] overflow-y-auto bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-30 flex flex-col gap-3.5 animate-in fade-in slide-in-from-top-4">
            <div className="flex items-center justify-between pb-2 border-b border-neutral-800">
              <span className="text-sm font-bold text-white flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-amber-400" />
                Element Palette & Brush Tools
              </span>
              <button
                onClick={() => setActiveMenu(null)}
                className="p-1 rounded-lg text-neutral-400 hover:text-white hover:bg-neutral-800 transition-all text-xs font-bold"
              >
                ✕ Close
              </button>
            </div>

            {/* Brush Tools Bar */}
            <div className="flex flex-col gap-2 bg-neutral-950/80 p-2.5 rounded-xl border border-neutral-800/80">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-neutral-400">Brush Tool:</span>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-neutral-400 font-medium">Size:</span>
                  <input
                    type="range"
                    min="1"
                    max="35"
                    value={brushSize}
                    onChange={e => setBrushSize(parseInt(e.target.value))}
                    className="w-24 accent-amber-500 h-1.5 bg-neutral-800 rounded-lg cursor-pointer"
                  />
                  <span className="text-xs font-mono font-bold text-amber-400 w-6">{brushSize}px</span>
                </div>
              </div>

              <div className="flex items-center gap-1 bg-neutral-900 p-1 rounded-xl border border-neutral-800 overflow-x-auto">
                {[
                  { id: 'circle', label: 'Circle Brush', icon: Circle },
                  { id: 'square', label: 'Square Brush', icon: Square },
                  { id: 'spray', label: 'Spray Dust', icon: Wind },
                  { id: 'line', label: 'Pencil Line', icon: Pencil },
                  { id: 'fill', label: 'Bucket Fill', icon: PaintBucket },
                  { id: 'eraser', label: 'Eraser', icon: Eraser },
                  { id: 'picker', label: 'Color Picker', icon: Pipette },
                ].map(tool => {
                  const Icon = tool.icon;
                  return (
                    <button
                      key={tool.id}
                      onClick={() => setBrushShape(tool.id as any)}
                      className={`p-2 rounded-lg transition-all shrink-0 ${
                        brushShape === tool.id
                          ? 'bg-amber-500 text-neutral-950 font-bold shadow-md shadow-amber-500/20'
                          : 'text-neutral-400 hover:text-white hover:bg-neutral-800'
                      }`}
                      title={tool.label}
                    >
                      <Icon className="w-4 h-4" />
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Search Bar */}
            <div className="flex items-center justify-between gap-2 bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2">
              <input
                type="text"
                placeholder="Search 500 Elements..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                className="w-full bg-transparent text-xs text-white placeholder-neutral-500 focus:outline-none font-medium"
              />
              <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-amber-500/10 text-amber-400 border border-amber-500/20 whitespace-nowrap">
                {filteredElements.length} / {allElements.length}
              </span>
            </div>

            {/* Category Tabs */}
            <div className="flex items-center gap-1 overflow-x-auto pb-1 scrollbar-none border-b border-neutral-800">
              {categories.map(cat => (
                <button
                  key={cat}
                  onClick={() => setActiveCategory(cat)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold whitespace-nowrap transition-all ${
                    activeCategory === cat
                      ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                      : 'text-neutral-400 hover:text-neutral-200'
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>

            {/* Element Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-1.5 max-h-[220px] overflow-y-auto pr-1">
              {filteredElements.map(el => {
                const isSelected = selectedElement === el.id;
                return (
                  <button
                    key={el.id}
                    onClick={() => {
                      setSelectedElement(el.id);
                      if (brushShape === 'eraser' || brushShape === 'picker') {
                        setBrushShape('circle');
                      }
                    }}
                    className={`flex items-center gap-2 p-2 rounded-xl text-xs text-left transition-all border ${
                      isSelected
                        ? 'bg-amber-500/20 border-amber-500 text-amber-200 font-bold shadow-md shadow-amber-500/10'
                        : 'bg-neutral-950/60 border-neutral-800/80 text-neutral-300 hover:bg-neutral-800 hover:text-white'
                    }`}
                  >
                    <div
                      className="w-3.5 h-3.5 rounded-full border border-white/20 shrink-0"
                      style={{ backgroundColor: el.color }}
                    />
                    <span className="truncate">{el.name}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* Panel 2: Bulk Particle Spawner Drawer Overlay */}
        {activeMenu === 'spawner' && (
          <div className="absolute top-16 right-3 left-3 sm:left-auto sm:w-[420px] bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-30 flex flex-col gap-4 animate-in fade-in slide-in-from-top-4">
            <div className="flex items-center justify-between pb-2 border-b border-neutral-800">
              <span className="text-sm font-bold text-white flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-amber-400" />
                Bulk Particle Spawner
              </span>
              <button
                onClick={() => setActiveMenu(null)}
                className="p-1 rounded-lg text-neutral-400 hover:text-white hover:bg-neutral-800 transition-all text-xs font-bold"
              >
                ✕ Close
              </button>
            </div>

            <div className="flex flex-col gap-3 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-neutral-300">Selected Element:</span>
                <span className="text-xs font-bold text-amber-300 flex items-center gap-1.5">
                  <div
                    className="w-3 h-3 rounded-full border border-white/20"
                    style={{ backgroundColor: activeElObj.color }}
                  />
                  {activeElObj.name}
                </span>
              </div>

              <div className="flex items-center justify-between text-xs font-bold text-neutral-400">
                <span>Particle Spawn Amount:</span>
                <span className="font-mono text-amber-300">{spawnCount.toLocaleString()}</span>
              </div>

              <input
                type="range"
                min="1000"
                max="1000000"
                step="1000"
                value={spawnCount}
                onChange={e => setSpawnCount(parseInt(e.target.value))}
                className="w-full accent-amber-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />

              <div className="flex items-center justify-between gap-1">
                {[1000, 10000, 50000, 100000, 1000000].map(val => (
                  <button
                    key={val}
                    onClick={() => setSpawnCount(val)}
                    className={`px-2.5 py-1 rounded text-[10px] font-mono transition-all ${
                      spawnCount === val
                        ? 'bg-amber-500 text-neutral-950 font-bold'
                        : 'bg-neutral-900 text-neutral-400 hover:text-white border border-neutral-800'
                    }`}
                  >
                    {val >= 1000000 ? '1M' : val >= 1000 ? `${val / 1000}K` : val}
                  </button>
                ))}
              </div>

              <button
                onClick={() => engine.spawnAmount(selectedElement, spawnCount)}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-amber-500 hover:bg-amber-400 text-neutral-950 font-bold text-xs transition-all shadow-md shadow-amber-500/20 active:scale-95 mt-1"
              >
                <Sparkles className="w-4 h-4 fill-current" />
                Spawn {spawnCount >= 1000000 ? '1 Million' : spawnCount.toLocaleString()} {activeElObj.name} Particles
              </button>
            </div>
          </div>
        )}

        {/* Panel 3: Settings & Environment Overlay */}
        {activeMenu === 'settings' && (
          <div className="absolute top-16 right-3 left-3 sm:left-auto sm:w-[380px] bg-neutral-900/95 backdrop-blur-xl border border-neutral-800 rounded-2xl p-4 shadow-2xl z-30 flex flex-col gap-4 animate-in fade-in slide-in-from-top-4">
            <div className="flex items-center justify-between pb-2 border-b border-neutral-800">
              <span className="text-sm font-bold text-white flex items-center gap-2">
                <FastForward className="w-4 h-4 text-amber-400" />
                Settings & Environment
              </span>
              <button
                onClick={() => setActiveMenu(null)}
                className="p-1 rounded-lg text-neutral-400 hover:text-white hover:bg-neutral-800 transition-all text-xs font-bold"
              >
                ✕ Close
              </button>
            </div>

            {/* Temperature Unit & Ambient Room Temperature */}
            <div className="flex flex-col gap-2 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-neutral-300">Temperature Scale:</span>
                <div className="flex items-center gap-1 bg-neutral-900 p-1 rounded-lg border border-neutral-800">
                  <button
                    onClick={() => setTempUnit('C')}
                    className={`px-2.5 py-1 rounded text-xs font-bold font-mono transition-all ${
                      tempUnit === 'C'
                        ? 'bg-amber-500 text-neutral-950 shadow'
                        : 'text-neutral-400 hover:text-white'
                    }`}
                  >
                    °C Celsius
                  </button>
                  <button
                    onClick={() => setTempUnit('F')}
                    className={`px-2.5 py-1 rounded text-xs font-bold font-mono transition-all ${
                      tempUnit === 'F'
                        ? 'bg-amber-500 text-neutral-950 shadow'
                        : 'text-neutral-400 hover:text-white'
                    }`}
                  >
                    °F Fahrenheit
                  </button>
                </div>
              </div>

              <div className="flex items-center justify-between text-xs font-bold text-neutral-400 mt-1">
                <span>Ambient Room Temperature:</span>
                <span className="font-mono text-amber-300">{formatTemp(ambientTemp)}</span>
              </div>
              <input
                type="range"
                min="-200"
                max="3000"
                step="10"
                value={ambientTemp}
                onChange={e => {
                  const val = parseInt(e.target.value);
                  setAmbientTemp(val);
                  engine.ambientTemp = val;
                }}
                className="w-full accent-amber-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />
            </div>

            {/* Environmental Gravity Direction */}
            <div className="flex flex-col gap-2 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
              <span className="text-xs font-bold text-neutral-400">Gravity Direction:</span>
              <div className="flex items-center justify-around gap-1 bg-neutral-900 p-1.5 rounded-xl border border-neutral-800">
                <button
                  onClick={() => updateGravity('down')}
                  className={`p-2 rounded-lg ${gravityDir === 'down' ? 'bg-amber-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'}`}
                  title="Gravity Down"
                >
                  <ArrowDown className="w-4 h-4" />
                </button>
                <button
                  onClick={() => updateGravity('up')}
                  className={`p-2 rounded-lg ${gravityDir === 'up' ? 'bg-amber-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'}`}
                  title="Gravity Up"
                >
                  <ArrowUp className="w-4 h-4" />
                </button>
                <button
                  onClick={() => updateGravity('left')}
                  className={`p-2 rounded-lg ${gravityDir === 'left' ? 'bg-amber-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'}`}
                  title="Gravity Left"
                >
                  <ArrowLeft className="w-4 h-4" />
                </button>
                <button
                  onClick={() => updateGravity('right')}
                  className={`p-2 rounded-lg ${gravityDir === 'right' ? 'bg-amber-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'}`}
                  title="Gravity Right"
                >
                  <ArrowRight className="w-4 h-4" />
                </button>
                <button
                  onClick={() => updateGravity('zero')}
                  className={`px-2.5 py-1.5 rounded-lg text-xs font-mono ${gravityDir === 'zero' ? 'bg-amber-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'}`}
                  title="Zero Gravity"
                >
                  0G
                </button>
              </div>
            </div>

            {/* Simulation Speed Slider & Presets */}
            <div className="flex flex-col gap-2 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-neutral-300 flex items-center gap-1.5">
                  <FastForward className="w-3.5 h-3.5 text-amber-400" />
                  <span>Simulation Speed:</span>
                </span>
                <span className="font-mono text-xs font-bold text-amber-300">
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
                className="w-full accent-amber-500 h-2 bg-neutral-800 rounded-lg cursor-pointer"
              />
              <div className="grid grid-cols-6 gap-1">
                {[0.02, 0.05, 0.1, 0.25, 0.5, 1.0].map(speed => (
                  <button
                    key={speed}
                    onClick={() => setSimSpeed(speed)}
                    className={`py-1 rounded text-[10px] font-mono transition-all border ${
                      simSpeed === speed
                        ? 'bg-amber-500 text-neutral-950 border-amber-400 font-bold'
                        : 'bg-neutral-900 text-neutral-400 hover:text-white border border-neutral-800'
                    }`}
                  >
                    {speed < 0.1 ? `${speed}` : `${speed}x`}
                  </button>
                ))}
              </div>
            </div>

            {/* Grain Texture & Shimmer Style */}
            <div className="flex flex-col gap-2 bg-neutral-950/80 p-3 rounded-xl border border-neutral-800/80">
              <span className="text-xs font-bold text-amber-400 flex items-center justify-between">
                <span>Grain Shading Style:</span>
                <span className="text-[10px] text-neutral-400 font-normal">Switch Texture Mode</span>
              </span>
              <div className="grid grid-cols-2 gap-1.5">
                {[
                  { id: 'natural_grain', name: 'Natural Grains', desc: 'Realistic static sand speckle' },
                  { id: 'organic_flow', name: 'Organic Flow', desc: 'Fluid sine wave shimmer' },
                  { id: 'diagonal_matrix', name: 'Diagonal Matrix', desc: 'Rolling diagonal waves' },
                  { id: 'flat', name: 'Solid Flat Color', desc: 'Crisp flat element fills' }
                ].map(style => (
                  <button
                    key={style.id}
                    onClick={() => updateTextureMode(style.id as any)}
                    className={`flex flex-col items-start p-2 rounded-xl text-left border transition-all ${
                      textureMode === style.id
                        ? 'bg-amber-500/20 text-amber-300 border-amber-500/60 font-bold shadow-md shadow-amber-500/10'
                        : 'bg-neutral-900 text-neutral-400 border-neutral-800 hover:text-white hover:border-neutral-700'
                    }`}
                  >
                    <span className="text-xs font-bold">{style.name}</span>
                    <span className="text-[10px] opacity-75 font-normal leading-tight mt-0.5">{style.desc}</span>
                  </button>
                ))}
              </div>
            </div>

            {onOpenUploadMap && (
              <button
                onClick={onOpenUploadMap}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-purple-900/50 hover:bg-purple-800/60 border border-purple-500/40 text-purple-200 text-xs font-bold transition-all shadow-md"
              >
                <Sparkles className="w-4 h-4 text-purple-400" />
                Publish Custom Map
              </button>
            )}
          </div>
        )}
      </div>

      {/* Debug & Performance Modals */}
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
    </div>
  );
};
