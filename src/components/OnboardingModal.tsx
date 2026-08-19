import React, { useEffect, useState } from 'react';
import { Flame, Atom, Sparkles, Users, Save, Globe, X, ChevronRight, Play, MousePointer, Zap } from 'lucide-react';

interface OnboardingModalProps {
  isOpen: boolean;
  onClose: () => void;
  onStartPowder: () => void;
  onStartParticle: () => void;
}

export const OnboardingModal: React.FC<OnboardingModalProps> = ({ isOpen, onClose, onStartPowder, onStartParticle }) => {
  const [step, setStep] = useState(0);
  if (!isOpen) return null;

  const steps = [
    {
      title: 'Welcome to Powder & Particle Lab',
      desc: 'A 500-element physics sandbox with dual engines — cellular powder grid + rigid-body particles — plus workshop, multiplayer, and diagnostics.',
      icon: Sparkles,
      color: 'text-amber-400',
      bg: 'bg-amber-500/10 border-amber-500/30'
    },
    {
      title: 'Two Simulators, One Lab',
      desc: 'Switch between Powder Grid (sand, lava, acid, lasers) and Particle Sandbox (galaxies, shockwaves, quantum lattices) from the top bar. Both support 60 FPS + 1M particles.',
      icon: Flame,
      color: 'text-orange-400',
      bg: 'bg-orange-500/10 border-orange-500/30'
    },
    {
      title: 'Paint, Spray, and Engineer',
      desc: 'Pick any of 500 elements, adjust brush size/shape, set gravity & wind, then draw. Use heatmap overlay to follow temperatures. Undo with Ctrl+Z.',
      icon: MousePointer,
      color: 'text-cyan-400',
      bg: 'bg-cyan-500/10 border-cyan-500/30'
    },
    {
      title: 'Create, Publish, and Play Together',
      desc: 'Save to Cloud Saves, publish your map to Community Workshop for others to like & remix, or open Multiplayer Room to draw together live.',
      icon: Users,
      color: 'text-emerald-400',
      bg: 'bg-emerald-500/10 border-emerald-500/30'
    },
  ];

  const current = steps[step];

  return (
    <div className="fixed inset-0 z-[60] bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-in fade-in">
      <div className="w-full max-w-lg bg-neutral-900 border border-neutral-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col">
        <div className="h-32 bg-gradient-to-br from-amber-600 via-orange-600 to-rose-600 relative flex items-center justify-center overflow-hidden">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_50%,rgba(255,255,255,0.15),transparent_60%)]" />
          <div className="w-14 h-14 rounded-2xl bg-white/95 flex items-center justify-center shadow-xl">
            <Flame className="w-7 h-7 text-orange-600" />
          </div>
          <button onClick={onClose} className="absolute top-3 right-3 p-1.5 rounded-xl bg-black/20 hover:bg-black/30 text-white">
            <X className="w-4 h-4" />
          </button>
          <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-1.5">
            {steps.map((_, i) => (
              <div key={i} className={`h-1.5 rounded-full transition-all ${i===step ? 'w-6 bg-white' : 'w-1.5 bg-white/40'}`} />
            ))}
          </div>
        </div>

        <div className="p-6 space-y-4 flex-1">
          <div className={`w-10 h-10 rounded-xl border flex items-center justify-center ${current.bg}`}>
            <current.icon className={`w-5 h-5 ${current.color}`} />
          </div>
          <div>
            <h2 className="font-extrabold text-white text-lg">{current.title}</h2>
            <p className="text-sm text-neutral-400 leading-relaxed mt-1.5">{current.desc}</p>
          </div>

          {step === 1 && (
            <div className="grid grid-cols-2 gap-2 pt-2">
              <button onClick={onStartPowder} className="p-3 rounded-xl bg-amber-500 text-neutral-950 font-bold text-sm flex items-center justify-center gap-2">
                <Flame className="w-4 h-4" /> Powder Grid
              </button>
              <button onClick={onStartParticle} className="p-3 rounded-xl bg-cyan-500 text-neutral-950 font-bold text-sm flex items-center justify-center gap-2">
                <Atom className="w-4 h-4" /> Particle Sandbox
              </button>
            </div>
          )}

          {step === 2 && (
            <div className="p-3 rounded-xl bg-neutral-950 border border-neutral-800 text-xs text-neutral-400 space-y-1">
              <div className="font-bold text-neutral-200 flex items-center gap-2"><Zap className="w-3.5 h-3.5 text-amber-400"/> Pro Shortcuts</div>
              <div className="font-mono text-[11px] grid grid-cols-2 gap-1">
                <span><b className="text-white">Ctrl+Z</b> Undo</span>
                <span><b className="text-white">Ctrl+Shift+Z</b> Redo</span>
                <span><b className="text-white">Space</b> Pause</span>
                <span><b className="text-white">C</b> Clear</span>
                <span><b className="text-white">R</b> Record</span>
                <span><b className="text-white">S</b> Screenshot</span>
              </div>
            </div>
          )}

          {step === 3 && (
            <div className="flex items-center gap-2 text-xs text-neutral-500">
              <Globe className="w-4 h-4 text-purple-400" /><span>Workshop</span><span className="mx-1">•</span><Save className="w-4 h-4 text-amber-400"/><span>Cloud Saves</span><span className="mx-1">•</span><Users className="w-4 h-4 text-emerald-400"/><span>Multiplayer</span>
            </div>
          )}
        </div>

        <div className="px-6 py-4 border-t border-neutral-800 flex items-center justify-between bg-neutral-950">
          <button onClick={onClose} className="text-xs text-neutral-400 hover:text-white px-3 py-1.5">Skip Tour</button>
          <div className="flex items-center gap-2">
            {step > 0 && <button onClick={()=> setStep(s=> s-1)} className="px-3 py-1.5 rounded-xl bg-neutral-800 text-neutral-300 text-xs font-semibold">Back</button>}
            {step < steps.length -1 ? (
              <button onClick={()=> setStep(s=> s+1)} className="px-4 py-1.5 rounded-xl bg-amber-500 text-neutral-950 font-bold text-xs flex items-center gap-1">Next <ChevronRight className="w-3.5 h-3.5" /></button>
            ) : (
              <button onClick={onClose} className="px-4 py-1.5 rounded-xl bg-emerald-500 text-neutral-950 font-bold text-xs flex items-center gap-1"><Play className="w-3.5 h-3.5 fill-current"/> Enter Lab</button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export function useOnboarding(): [boolean, ()=> void, ()=> void] {
  const [isOpen, setIsOpen] = useState(false);
  useEffect(()=> {
    const seen = localStorage.getItem('powder-onboarding-seen');
    if (!seen) setIsOpen(true);
  }, []);
  const close = () => { localStorage.setItem('powder-onboarding-seen','1'); setIsOpen(false); };
  const open = () => setIsOpen(true);
  return [isOpen, close, open];
}
