import React from 'react';
import {
  ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, BarChart, Bar, Cell, PieChart, Pie
} from 'recharts';
import { PowderEngine } from '../engine/powderEngine';
import { ParticleEngine } from '../engine/particleEngine';
import { Activity, BarChart3, PieChart as PieIcon, Cpu, Zap, RefreshCw, X } from 'lucide-react';

export interface AnalyticsFrameData {
  time: string;
  fps: number;
  particles: number;
  diversity: number;
  maxTemp?: number;
  avgTemp?: number;
}

export interface ElementCompositionData {
  name: string;
  count: number;
  color: string;
  percentage: number;
}

interface AnalyticsDashboardModalProps {
  isOpen: boolean;
  onClose: () => void;
  engineType: 'powder' | 'particle';
  powderEngine?: PowderEngine;
  particleEngine?: ParticleEngine;
  history: AnalyticsFrameData[];
  fps: number;
  onClearHistory?: () => void;
}

export const AnalyticsDashboardModal: React.FC<AnalyticsDashboardModalProps> = ({
  isOpen,
  onClose,
  engineType,
  powderEngine,
  particleEngine,
  history,
  fps,
  onClearHistory
}) => {
  if (!isOpen) return null;

  // Compute live element composition breakdown
  const compositionData: ElementCompositionData[] = [];
  let totalParticles = 0;

  if (engineType === 'powder' && powderEngine) {
    const elementCounts: Map<number, number> = new Map();
    const len = powderEngine.gridType.length;
    for (let i = 0; i < len; i++) {
      const type = powderEngine.gridType[i];
      if (type !== 0) {
        elementCounts.set(type, (elementCounts.get(type) || 0) + 1);
        totalParticles++;
      }
    }

    const sorted = Array.from(elementCounts.entries()).sort((a, b) => b[1] - a[1]);
    const topElements = sorted.slice(0, 7);
    let otherCount = 0;
    for (let i = 7; i < sorted.length; i++) {
      otherCount += sorted[i][1];
    }

    topElements.forEach(([id, count]) => {
      const def = powderEngine.registry.getElement(id);
      compositionData.push({
        name: def.name,
        count,
        color: def.color,
        percentage: totalParticles > 0 ? Math.round((count / totalParticles) * 100) : 0
      });
    });

    if (otherCount > 0) {
      compositionData.push({
        name: 'Other Elements',
        count: otherCount,
        color: '#94a3b8',
        percentage: totalParticles > 0 ? Math.round((otherCount / totalParticles) * 100) : 0
      });
    }
  } else if (engineType === 'particle' && particleEngine) {
    totalParticles = particleEngine.particles.length;
    const typeCounts: Map<string, number> = new Map();
    particleEngine.particles.forEach(p => {
      const t = p.type || 'standard';
      typeCounts.set(t, (typeCounts.get(t) || 0) + 1);
    });

    const colorMap: Record<string, string> = {
      standard: '#38bdf8',
      emitter: '#a855f7',
      blackhole: '#f43f5e',
      repulsor: '#10b981',
      bouncy: '#f59e0b',
      glow: '#fb923c'
    };

    typeCounts.forEach((count, type) => {
      compositionData.push({
        name: type.charAt(0).toUpperCase() + type.slice(1),
        count,
        color: colorMap[type] || '#38bdf8',
        percentage: totalParticles > 0 ? Math.round((count / totalParticles) * 100) : 0
      });
    });
  }

  const powderDiag = powderEngine?.getDiagnostics();
  const particleDiag = particleEngine?.getDiagnostics();

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-in fade-in duration-200 select-none">
      <div className="w-full max-w-4xl bg-neutral-900 border border-neutral-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 bg-neutral-950 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
              <BarChart3 className="w-5 h-5" />
            </div>
            <div>
              <h2 className="font-bold text-white text-base flex items-center gap-2">
                <span>Real-Time Analytics Dashboard</span>
                <span className="text-[10px] px-2 py-0.5 rounded-full font-mono font-semibold uppercase bg-amber-500/20 text-amber-300 border border-amber-500/30">
                  {engineType === 'powder' ? 'Powder Engine' : 'Particle Engine'}
                </span>
              </h2>
              <p className="text-xs text-neutral-400">Live Recharts telemetry: FPS stability, particle load, and active element diversity</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {onClearHistory && (
              <button
                onClick={onClearHistory}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-neutral-300 text-xs font-semibold transition-all"
                title="Reset analytics telemetry history"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                Reset Data
              </button>
            )}
            <button
              onClick={onClose}
              className="p-1.5 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-neutral-300 hover:text-white transition-all"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="p-6 overflow-y-auto flex-1 space-y-6">
          {/* Top Quick Telemetry Metric Cards */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
              <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                <Activity className="w-3.5 h-3.5 text-amber-400" />
                <span>Framerate (FPS)</span>
              </div>
              <div className="text-2xl font-bold font-mono text-white flex items-baseline gap-1">
                <span className={fps >= 50 ? 'text-emerald-400' : fps >= 30 ? 'text-amber-400' : 'text-rose-400'}>{fps}</span>
                <span className="text-xs text-neutral-500 font-normal">/ 60 FPS</span>
              </div>
            </div>

            <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
              <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                <Cpu className="w-3.5 h-3.5 text-cyan-400" />
                <span>Total Active Particles</span>
              </div>
              <div className="text-2xl font-bold font-mono text-white">
                {totalParticles.toLocaleString()}
              </div>
            </div>

            <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
              <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                <PieIcon className="w-3.5 h-3.5 text-purple-400" />
                <span>Active Element Diversity</span>
              </div>
              <div className="text-2xl font-bold font-mono text-purple-300">
                {compositionData.length} <span className="text-xs font-normal text-neutral-500">Types</span>
              </div>
            </div>

            <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
              <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                <Zap className="w-3.5 h-3.5 text-rose-400" />
                <span>{engineType === 'powder' ? 'Thermal Peak' : 'Velocity Peak'}</span>
              </div>
              <div className="text-xl font-bold font-mono text-white">
                {engineType === 'powder' ? `${powderDiag?.maxTemp}°C` : `${particleDiag?.maxSpeedFound} px/f`}
              </div>
            </div>
          </div>

          {/* Chart Section 1: FPS and Particle Count Over Time (Area Charts) */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* FPS Chart */}
            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-bold text-white flex items-center gap-2">
                  <Activity className="w-4 h-4 text-emerald-400" />
                  <span>Framerate Stability (FPS History)</span>
                </h3>
                <span className="text-[10px] font-mono text-neutral-500">{history.length} frames logged</span>
              </div>
              <div className="h-48 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={history} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                    <defs>
                      <linearGradient id="fpsGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#10b981" stopOpacity={0.4} />
                        <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <XAxis dataKey="time" stroke="#525252" fontSize={10} tickLine={false} />
                    <YAxis domain={[0, 70]} stroke="#525252" fontSize={10} tickLine={false} />
                    <Tooltip
                      contentStyle={{ backgroundColor: '#0a0a0c', borderColor: '#27272a', borderRadius: '12px', fontSize: '11px', color: '#fff' }}
                    />
                    <Area type="monotone" dataKey="fps" stroke="#10b981" strokeWidth={2} fillOpacity={1} fill="url(#fpsGradient)" name="FPS" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Particle Count Chart */}
            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-bold text-white flex items-center gap-2">
                  <Cpu className="w-4 h-4 text-amber-400" />
                  <span>Particle Load Over Time</span>
                </h3>
                <span className="text-[10px] font-mono text-amber-400">{totalParticles.toLocaleString()} active</span>
              </div>
              <div className="h-48 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={history} margin={{ top: 10, right: 10, left: -10, bottom: 0 }}>
                    <defs>
                      <linearGradient id="particleGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#f59e0b" stopOpacity={0.4} />
                        <stop offset="95%" stopColor="#f59e0b" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <XAxis dataKey="time" stroke="#525252" fontSize={10} tickLine={false} />
                    <YAxis stroke="#525252" fontSize={10} tickLine={false} />
                    <Tooltip
                      contentStyle={{ backgroundColor: '#0a0a0c', borderColor: '#27272a', borderRadius: '12px', fontSize: '11px', color: '#fff' }}
                    />
                    <Area type="monotone" dataKey="particles" stroke="#f59e0b" strokeWidth={2} fillOpacity={1} fill="url(#particleGradient)" name="Active Particles" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>

          {/* Chart Section 2: Active Element Composition & Diversity */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Bar Chart composition */}
            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
              <h3 className="text-xs font-bold text-white flex items-center gap-2">
                <BarChart3 className="w-4 h-4 text-purple-400" />
                <span>Element Volume Breakdown</span>
              </h3>
              <div className="h-48 w-full">
                {compositionData.length > 0 ? (
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={compositionData} margin={{ top: 10, right: 10, left: -10, bottom: 20 }}>
                      <XAxis dataKey="name" stroke="#525252" fontSize={10} tickLine={false} angle={-20} textAnchor="end" />
                      <YAxis stroke="#525252" fontSize={10} tickLine={false} />
                      <Tooltip
                        contentStyle={{ backgroundColor: '#0a0a0c', borderColor: '#27272a', borderRadius: '12px', fontSize: '11px', color: '#fff' }}
                      />
                      <Bar dataKey="count" radius={[6, 6, 0, 0]} name="Count">
                        {compositionData.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Bar>
                    </BarChart>
                  </ResponsiveContainer>
                ) : (
                  <div className="h-full flex items-center justify-center text-xs text-neutral-500 italic">
                    Grid is empty. Paint elements to generate analytics...
                  </div>
                )}
              </div>
            </div>

            {/* Pie Chart / Legend Breakdown */}
            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
              <h3 className="text-xs font-bold text-white flex items-center gap-2">
                <PieIcon className="w-4 h-4 text-cyan-400" />
                <span>Element Diversity Ratio (%)</span>
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 items-center gap-2 h-48">
                {compositionData.length > 0 ? (
                  <>
                    <div className="h-full w-full">
                      <ResponsiveContainer width="100%" height="100%">
                        <PieChart>
                          <Pie
                            data={compositionData}
                            dataKey="count"
                            nameKey="name"
                            cx="50%"
                            cy="50%"
                            innerRadius={30}
                            outerRadius={60}
                            paddingAngle={3}
                          >
                            {compositionData.map((entry, index) => (
                              <Cell key={`pie-cell-${index}`} fill={entry.color} />
                            ))}
                          </Pie>
                          <Tooltip
                            contentStyle={{ backgroundColor: '#0a0a0c', borderColor: '#27272a', borderRadius: '12px', fontSize: '11px', color: '#fff' }}
                          />
                        </PieChart>
                      </ResponsiveContainer>
                    </div>

                    <div className="space-y-1.5 max-h-44 overflow-y-auto pr-1">
                      {compositionData.map((item, idx) => (
                        <div key={idx} className="flex items-center justify-between text-xs">
                          <div className="flex items-center gap-2 truncate">
                            <div className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: item.color }} />
                            <span className="text-neutral-300 truncate font-medium">{item.name}</span>
                          </div>
                          <span className="font-mono text-amber-300 font-bold shrink-0">{item.percentage}%</span>
                        </div>
                      ))}
                    </div>
                  </>
                ) : (
                  <div className="col-span-2 h-full flex items-center justify-center text-xs text-neutral-500 italic">
                    No active particles detected on simulation grid.
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
