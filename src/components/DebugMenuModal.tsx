import React, { useState, useEffect } from 'react';
import { PowderEngine } from '../engine/powderEngine';
import { ParticleEngine } from '../engine/particleEngine';
import {
  Activity, Wrench, Zap, CheckCircle2, AlertTriangle, RefreshCw, ShieldCheck,
  Flame, Cpu, Database, ChevronRight, Terminal, Layers, Bomb, ShieldAlert, Thermometer, Droplet
} from 'lucide-react';

interface DebugMenuModalProps {
  isOpen: boolean;
  onClose: () => void;
  engineType: 'powder' | 'particle';
  powderEngine?: PowderEngine;
  particleEngine?: ParticleEngine;
  fps: number;
}

export const DebugMenuModal: React.FC<DebugMenuModalProps> = ({
  isOpen,
  onClose,
  engineType,
  powderEngine,
  particleEngine,
  fps
}) => {
  const [activeTab, setActiveTab] = useState<'health' | 'manual' | 'autofix' | 'stress'>('health');
  const [autoFixLogs, setAutoFixLogs] = useState<string[]>([]);
  const [actionNotice, setActionNotice] = useState<string | null>(null);

  // Force tick re-render for real-time stats
  const [, setTick] = useState<number>(0);
  useEffect(() => {
    if (!isOpen) return;
    const timer = setInterval(() => setTick(t => t + 1), 500);
    return () => clearInterval(timer);
  }, [isOpen]);

  if (!isOpen) return null;

  // Retrieve current engine diagnostics
  const powderDiag = powderEngine?.getDiagnostics();
  const particleDiag = particleEngine?.getDiagnostics();

  const isHealthy = engineType === 'powder' ? powderDiag?.isHealthy : particleDiag?.isHealthy;
  const issues = engineType === 'powder' ? powderDiag?.issues : particleDiag?.issues;

  const handleRunAutoFix = () => {
    if (engineType === 'powder' && powderEngine) {
      const { logs } = powderEngine.runAutoFix();
      setAutoFixLogs(logs);
    } else if (engineType === 'particle' && particleEngine) {
      const { logs } = particleEngine.runAutoFix();
      setAutoFixLogs(logs);
    }
    setActionNotice('Auto-Fix sequence executed successfully.');
    setTimeout(() => setActionNotice(null), 3000);
  };

  const handleManualAction = (actionName: string, actionFn: () => any) => {
    const result = actionFn();
    setActionNotice(`${actionName}: Executed (${JSON.stringify(result)})`);
    setTimeout(() => setActionNotice(null), 3000);
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-in fade-in duration-200 select-none">
      <div className="w-full max-w-3xl bg-neutral-900 border border-neutral-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 bg-neutral-950 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-xl ${isHealthy ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'}`}>
              <Activity className="w-5 h-5" />
            </div>
            <div>
              <h2 className="font-bold text-white text-base flex items-center gap-2">
                <span>{engineType === 'powder' ? 'Powder Simulator' : 'Particle Simulator'} Debug & Diagnostics</span>
                <span className={`text-[10px] px-2 py-0.5 rounded-full font-mono font-semibold uppercase ${isHealthy ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30' : 'bg-amber-500/20 text-amber-300 border border-amber-500/30'}`}>
                  {isHealthy ? 'Operational' : 'Issues Found'}
                </span>
              </h2>
              <p className="text-xs text-neutral-400">System health monitor, manual troubleshooting guides, automated self-repair, and stress testing</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="px-3 py-1.5 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-neutral-300 hover:text-white text-xs font-semibold transition-all"
          >
            Close
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="px-6 py-2 border-b border-neutral-800 bg-neutral-900/60 flex items-center gap-2 overflow-x-auto no-scrollbar">
          <button
            onClick={() => setActiveTab('health')}
            className={`flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-bold transition-all shrink-0 ${
              activeTab === 'health' ? 'bg-amber-500 text-neutral-950 shadow-md' : 'text-neutral-400 hover:text-white hover:bg-neutral-800'
            }`}
          >
            <ShieldCheck className="w-4 h-4" />
            <span>Health Monitor</span>
          </button>

          <button
            onClick={() => setActiveTab('manual')}
            className={`flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-bold transition-all shrink-0 ${
              activeTab === 'manual' ? 'bg-amber-500 text-neutral-950 shadow-md' : 'text-neutral-400 hover:text-white hover:bg-neutral-800'
            }`}
          >
            <Wrench className="w-4 h-4" />
            <span>Manual Fix Tools</span>
          </button>

          <button
            onClick={() => setActiveTab('autofix')}
            className={`flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-bold transition-all shrink-0 ${
              activeTab === 'autofix' ? 'bg-amber-500 text-neutral-950 shadow-md' : 'text-neutral-400 hover:text-white hover:bg-neutral-800'
            }`}
          >
            <Zap className="w-4 h-4" />
            <span>Auto-Fix Engine</span>
          </button>

          <button
            onClick={() => setActiveTab('stress')}
            className={`flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-bold transition-all shrink-0 ${
              activeTab === 'stress' ? 'bg-amber-500 text-neutral-950 shadow-md' : 'text-neutral-400 hover:text-white hover:bg-neutral-800'
            }`}
          >
            <Bomb className="w-4 h-4" />
            <span>Stress Test Lab</span>
          </button>
        </div>

        {/* Notice Banner */}
        {actionNotice && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-emerald-950/80 border border-emerald-500/40 text-emerald-200 text-xs flex items-center gap-2 animate-in fade-in duration-150">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
            <span>{actionNotice}</span>
          </div>
        )}

        {/* Modal Content */}
        <div className="p-6 overflow-y-auto flex-1 space-y-4">
          {/* TAB 1: Health & State Monitor */}
          {activeTab === 'health' && (
            <div className="space-y-4">
              {/* Health Overview Grid */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
                  <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                    <Activity className="w-3.5 h-3.5 text-amber-400" />
                    <span>Framerate</span>
                  </div>
                  <div className="text-xl font-bold font-mono text-white flex items-baseline gap-1">
                    <span>{fps}</span>
                    <span className="text-xs font-normal text-neutral-500">FPS</span>
                  </div>
                </div>

                <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
                  <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                    <Layers className="w-3.5 h-3.5 text-blue-400" />
                    <span>Active Element Load</span>
                  </div>
                  <div className="text-xl font-bold font-mono text-white">
                    {engineType === 'powder' ? powderDiag?.activeParticles.toLocaleString() : particleDiag?.particleCount.toLocaleString()}
                  </div>
                  <div className="text-[10px] text-neutral-500 mt-0.5">
                    {engineType === 'powder' ? `${powderDiag?.loadPercentage}% grid full` : `Max ${particleDiag?.maxParticles.toLocaleString()}`}
                  </div>
                </div>

                <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
                  <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                    <Flame className="w-3.5 h-3.5 text-red-400" />
                    <span>{engineType === 'powder' ? 'Thermal Range' : 'Max Velocity'}</span>
                  </div>
                  <div className="text-base font-bold font-mono text-white">
                    {engineType === 'powder' ? `${powderDiag?.minTemp}°C to ${powderDiag?.maxTemp}°C` : `${particleDiag?.maxSpeedFound} px/f`}
                  </div>
                </div>

                <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800">
                  <div className="text-[11px] font-semibold text-neutral-400 flex items-center gap-1.5 mb-1">
                    <Database className="w-3.5 h-3.5 text-purple-400" />
                    <span>Buffer Memory</span>
                  </div>
                  <div className="text-xl font-bold font-mono text-white">
                    {Math.round(((engineType === 'powder' ? powderDiag?.memoryBytes : particleDiag?.memoryBytes) || 0) / 1024).toLocaleString()} <span className="text-xs font-normal text-neutral-500">KB</span>
                  </div>
                </div>
              </div>

              {/* Status Alert Card */}
              <div className={`p-4 rounded-xl border ${isHealthy ? 'bg-emerald-950/30 border-emerald-800/50' : 'bg-amber-950/30 border-amber-800/50'}`}>
                <div className="flex items-center gap-2 mb-2">
                  {isHealthy ? (
                    <CheckCircle2 className="w-5 h-5 text-emerald-400" />
                  ) : (
                    <AlertTriangle className="w-5 h-5 text-amber-400" />
                  )}
                  <h3 className="font-bold text-sm text-white">
                    {isHealthy ? 'All Engine Integrity Checks Passed' : 'Active Engine Anomaly Warnings'}
                  </h3>
                </div>
                {issues && issues.length > 0 ? (
                  <ul className="space-y-1.5 pl-6 list-disc text-xs text-amber-200">
                    {issues.map((issue, idx) => (
                      <li key={idx}>{issue}</li>
                    ))}
                  </ul>
                ) : (
                  <p className="text-xs text-neutral-400">
                    No NaN coordinates, corrupt memory cells, or invalid thermal states detected in simulation buffers.
                  </p>
                )}
              </div>
            </div>
          )}

          {/* TAB 2: Manual Troubleshooting & Step-by-Step Fixes */}
          {activeTab === 'manual' && (
            <div className="space-y-3">
              <p className="text-xs text-neutral-400">
                Execute surgical troubleshooting actions to clear stuck cells, normalize runaway reactions, or rebuild canvas buffers:
              </p>

              {/* Fix 1 */}
              <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <div className="p-2 rounded-lg bg-blue-500/20 text-blue-400">
                    <RefreshCw className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="font-bold text-xs text-white">Flush Corrupted & Stuck Cells</h4>
                    <p className="text-[11px] text-neutral-400">Clears invalid element IDs, stuck visited flags, or NaN values.</p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    if (engineType === 'powder' && powderEngine) {
                      handleManualAction('Flush Cells', () => powderEngine.flushStuckCells());
                    } else if (engineType === 'particle' && particleEngine) {
                      handleManualAction('Purge NaN', () => particleEngine.purgeNaNParticles());
                    }
                  }}
                  className="px-3 py-1.5 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold transition-all shadow-md shrink-0"
                >
                  Flush Cells
                </button>
              </div>

              {/* Fix 2 */}
              <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <div className="p-2 rounded-lg bg-amber-500/20 text-amber-400">
                    <Flame className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="font-bold text-xs text-white">Clamp Extreme Thermal & Speed Spikes</h4>
                    <p className="text-[11px] text-neutral-400">Normalizes wild thermal values or runaway particle vectors.</p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    if (engineType === 'powder' && powderEngine) {
                      handleManualAction('Normalize Thermal', () => powderEngine.zeroThermalExtremes());
                    } else if (engineType === 'particle' && particleEngine) {
                      handleManualAction('Clamp Velocity', () => particleEngine.clampVelocities());
                    }
                  }}
                  className="px-3 py-1.5 rounded-xl bg-amber-600 hover:bg-amber-500 text-white text-xs font-bold transition-all shadow-md shrink-0"
                >
                  Clamp Values
                </button>
              </div>

              {/* Extra Fix Tools for Powder / Particle */}
              {engineType === 'powder' && powderEngine && (
                <>
                  <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <div className="p-2 rounded-lg bg-red-500/20 text-red-400">
                        <Flame className="w-4 h-4" />
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-white">Extinguish Wild Fire & Cool Lava</h4>
                        <p className="text-[11px] text-neutral-400">Extinguishes active flames and solidifies lava to stone.</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleManualAction('Extinguish Fire', () => powderEngine.extinguishFires())}
                      className="px-3 py-1.5 rounded-xl bg-red-600 hover:bg-red-500 text-white text-xs font-bold transition-all shrink-0"
                    >
                      Extinguish
                    </button>
                  </div>

                  <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <div className="p-2 rounded-lg bg-emerald-500/20 text-emerald-400">
                        <Droplet className="w-4 h-4" />
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-white">Neutralize Acids to Water</h4>
                        <p className="text-[11px] text-neutral-400">Converts corrosive acid cells into harmless water.</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleManualAction('Neutralize Acid', () => powderEngine.neutralizeAcids())}
                      className="px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold transition-all shrink-0"
                    >
                      Neutralize
                    </button>
                  </div>

                  <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <div className="p-2 rounded-lg bg-purple-500/20 text-purple-400">
                        <ShieldAlert className="w-4 h-4" />
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-white">Seal Bedrock Border Frame</h4>
                        <p className="text-[11px] text-neutral-400">Re-enforces indestructible bedrock borders around canvas edges.</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleManualAction('Seal Bedrock', () => powderEngine.sealBedrockBorders())}
                      className="px-3 py-1.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white text-xs font-bold transition-all shrink-0"
                    >
                      Seal Borders
                    </button>
                  </div>
                </>
              )}

              {engineType === 'particle' && particleEngine && (
                <>
                  <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <div className="p-2 rounded-lg bg-cyan-500/20 text-cyan-400">
                        <Activity className="w-4 h-4" />
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-white">Zero Velocity Forces</h4>
                        <p className="text-[11px] text-neutral-400">Stops all moving particles in place without removing them.</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleManualAction('Zero Forces', () => particleEngine.zeroForces())}
                      className="px-3 py-1.5 rounded-xl bg-cyan-600 hover:bg-cyan-500 text-white text-xs font-bold transition-all shrink-0"
                    >
                      Zero Forces
                    </button>
                  </div>

                  <div className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <div className="p-2 rounded-lg bg-indigo-500/20 text-indigo-400">
                        <Zap className="w-4 h-4" />
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-white">Reset Particle Charges</h4>
                        <p className="text-[11px] text-neutral-400">Rebalances positive and negative Coulomb electrostatic charges.</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleManualAction('Reset Charges', () => particleEngine.resetCharges())}
                      className="px-3 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition-all shrink-0"
                    >
                      Reset Charges
                    </button>
                  </div>
                </>
              )}
            </div>
          )}

          {/* TAB 3: Auto-Fix Routine */}
          {activeTab === 'autofix' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 flex items-center justify-between gap-4">
                <div>
                  <h3 className="font-bold text-sm text-white flex items-center gap-2">
                    <Zap className="w-4 h-4 text-amber-400" />
                    <span>Automated Self-Repair Suite</span>
                  </h3>
                  <p className="text-xs text-neutral-400 mt-1">
                    Triggers a multi-stage diagnostic sequence that automatically purges corruption, seals borders, normalizes thermal spikes, and verifies buffer health.
                  </p>
                </div>
                <button
                  onClick={handleRunAutoFix}
                  className="px-4 py-2.5 rounded-xl bg-amber-500 hover:bg-amber-400 text-neutral-950 font-bold text-xs shadow-lg transition-all flex items-center gap-2 shrink-0"
                >
                  <Zap className="w-4 h-4 fill-current" />
                  <span>Run Auto-Fix Suite</span>
                </button>
              </div>

              {/* Console Output Log */}
              <div className="p-4 rounded-xl bg-black border border-neutral-800 font-mono text-xs space-y-2">
                <div className="flex items-center gap-2 text-neutral-500 text-[11px] uppercase border-b border-neutral-800 pb-2">
                  <Terminal className="w-3.5 h-3.5 text-amber-400" />
                  <span>Auto-Fix Diagnostics Console</span>
                </div>
                {autoFixLogs.length > 0 ? (
                  <div className="space-y-1 text-emerald-400">
                    {autoFixLogs.map((log, idx) => (
                      <div key={idx} className="flex items-start gap-2">
                        <ChevronRight className="w-3.5 h-3.5 text-neutral-600 shrink-0 mt-0.5" />
                        <span>{log}</span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-neutral-500 italic py-4 text-center">
                    Click "Run Auto-Fix Suite" above to execute auto-repair and output diagnostics log...
                  </div>
                )}
              </div>
            </div>
          )}

          {/* TAB 4: Stress & Failure Injection Lab */}
          {activeTab === 'stress' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-rose-950/30 border border-rose-800/40">
                <h3 className="font-bold text-sm text-rose-300 flex items-center gap-2 mb-1">
                  <Bomb className="w-4 h-4 text-rose-400" />
                  <span>Stress Test & Anomaly Injector</span>
                </h3>
                <p className="text-xs text-neutral-400">
                  Inject artificial failures or thermal spikes to test how the diagnostic scanner detects issues and how the Auto-Fix engine repairs them:
                </p>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {engineType === 'powder' && powderEngine && (
                  <>
                    <button
                      onClick={() => handleManualAction('Thermal Spike Injected', () => powderEngine.injectThermalSpike())}
                      className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 hover:border-rose-500/50 text-left transition-all"
                    >
                      <div className="font-bold text-xs text-rose-300 flex items-center gap-2">
                        <Thermometer className="w-4 h-4 text-rose-400" />
                        <span>Inject 2800°C Thermal Spike</span>
                      </div>
                      <div className="text-[11px] text-neutral-400 mt-1">Spawns a super-heated core to test thermal clamp diagnostics.</div>
                    </button>

                    <button
                      onClick={() => handleManualAction('Acid Flood Injected', () => powderEngine.injectAcidFlood())}
                      className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 hover:border-emerald-500/50 text-left transition-all"
                    >
                      <div className="font-bold text-xs text-emerald-300 flex items-center gap-2">
                        <Droplet className="w-4 h-4 text-emerald-400" />
                        <span>Inject Corrosive Acid Flood</span>
                      </div>
                      <div className="text-[11px] text-neutral-400 mt-1">Fills the lower grid with acid to test neutralizer routines.</div>
                    </button>

                    <button
                      onClick={() => handleManualAction('Corrupt NaN Cells Injected', () => powderEngine.injectCorruptCells())}
                      className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 hover:border-amber-500/50 text-left transition-all col-span-1 sm:col-span-2"
                    >
                      <div className="font-bold text-xs text-amber-300 flex items-center gap-2">
                        <AlertTriangle className="w-4 h-4 text-amber-400" />
                        <span>Inject Corrupt NaN Array Values</span>
                      </div>
                      <div className="text-[11px] text-neutral-400 mt-1">Inserts invalid NaN float values into grid buffers to verify flush algorithms.</div>
                    </button>
                  </>
                )}

                {engineType === 'particle' && particleEngine && (
                  <>
                    <button
                      onClick={() => handleManualAction('Hyper-Speed Particles Injected', () => particleEngine.injectHyperVelocityExplosion())}
                      className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 hover:border-amber-500/50 text-left transition-all"
                    >
                      <div className="font-bold text-xs text-amber-300 flex items-center gap-2">
                        <Zap className="w-4 h-4 text-amber-400" />
                        <span>Inject Hyper-Velocity Blast</span>
                      </div>
                      <div className="text-[11px] text-neutral-400 mt-1">Spawns 250 px/frame particles to trigger velocity cap diagnostics.</div>
                    </button>

                    <button
                      onClick={() => handleManualAction('Corrupt Particle Vectors Injected', () => particleEngine.injectCorruptVectorParticles())}
                      className="p-3.5 rounded-xl bg-neutral-950 border border-neutral-800 hover:border-rose-500/50 text-left transition-all"
                    >
                      <div className="font-bold text-xs text-rose-300 flex items-center gap-2">
                        <AlertTriangle className="w-4 h-4 text-rose-400" />
                        <span>Inject Corrupt NaN Particle Vectors</span>
                      </div>
                      <div className="text-[11px] text-neutral-400 mt-1">Creates NaN coordinate particles to test vector purging.</div>
                    </button>
                  </>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
