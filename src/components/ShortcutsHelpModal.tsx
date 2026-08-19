import React from 'react';
import { X, Keyboard, Zap, MousePointer, Film, Camera, History, Wind, Thermometer, Layers } from 'lucide-react';

interface Props { isOpen: boolean; onClose: ()=> void;}

export const ShortcutsHelpModal: React.FC<Props> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;
  const Row = ({ keys, desc }: { keys: string[], desc: string}) => (
    <div className="flex items-center justify-between py-1.5 border-b border-neutral-900 last:border-0">
      <span className="text-xs text-neutral-300">{desc}</span>
      <span className="flex gap-1">
        {keys.map(k=> <span key={k} className="px-1.5 py-0.5 rounded bg-neutral-800 border border-neutral-700 text-[10px] font-mono font-bold text-amber-300">{k}</span>)}
      </span>
    </div>
  );
  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-in fade-in">
      <div className="w-full max-w-lg bg-neutral-900 border border-neutral-800 rounded-2xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">
        <div className="px-6 py-4 border-b border-neutral-800 bg-neutral-950 flex items-center justify-between">
          <div className="flex items-center gap-2 font-bold text-white"><Keyboard className="w-5 h-5 text-cyan-400"/> Keyboard & Gesture Shortcuts</div>
          <button onClick={onClose} className="p-1.5 rounded-xl bg-neutral-800 text-neutral-400 hover:text-white"><X className="w-4 h-4"/></button>
        </div>
        <div className="p-6 space-y-5 overflow-y-auto">
          <div className="space-y-1">
            <div className="text-xs font-bold text-amber-400 flex items-center gap-1.5"><Zap className="w-3.5 h-3.5"/> General</div>
            <div className="p-3 rounded-xl bg-neutral-950 border border-neutral-800">
              <Row keys={['Space']} desc="Pause / Resume simulation"/>
              <Row keys={['C']} desc="Clear canvas (with undo)"/>
              <Row keys={['Ctrl','Z']} desc="Undo last stroke / action"/>
              <Row keys={['Ctrl','Shift','Z']} desc="Redo"/>
              <Row keys={['Ctrl','Y']} desc="Redo (alt)"/>
              <Row keys={['S']} desc="Screenshot PNG"/>
              <Row keys={['R']} desc="Toggle Recording (WebM)"/>
              <Row keys={['H']} desc="Toggle heatmap overlay (powder)"/>
            </div>
          </div>

          <div className="space-y-1">
            <div className="text-xs font-bold text-cyan-400 flex items-center gap-1.5"><MousePointer className="w-3.5 h-3.5"/> Brush & Paint (Powder)</div>
            <div className="p-3 rounded-xl bg-neutral-950 border border-neutral-800">
              <Row keys={['[',']']} desc="Decrease / Increase brush size"/>
              <Row keys={['E']} desc="Eraser tool"/>
              <Row keys={['B']} desc="Circle brush"/>
              <Row keys={['Shift','B']} desc="Square / Fill bucket"/>
              <Row keys={['Alt','Click']} desc="Color picker (hover+click)"/>
              <Row keys={['Scroll']} desc="Zoom brush preview"/>
              <Row keys={['Drag']} desc="Paint — touch & mouse both work"/>
              <Row keys={['Pinch']} desc="Pinch-to-paint on mobile"/>
            </div>
          </div>

          <div className="space-y-1">
            <div className="text-xs font-bold text-purple-400 flex items-center gap-1.5"><Film className="w-3.5 h-3.5"/> Recording & Sharing</div>
            <div className="p-3 rounded-xl bg-neutral-950 border border-neutral-800 text-xs text-neutral-400 leading-relaxed">
              <div className="flex items-center gap-2 mb-1 text-neutral-200 font-semibold"><Camera className="w-3.5 h-3.5 text-emerald-400"/> Capture</div>
              Click <b className="text-white">📸 Screenshot</b> for PNG or <b className="text-white">● Record</b> for WebM video (Chrome/Edge). Recordings auto-download. Workshop uploads now auto-generate thumbnails from your canvas.
            </div>
          </div>

          <div className="space-y-1">
            <div className="text-xs font-bold text-rose-400 flex items-center gap-1.5"><History className="w-3.5 h-3.5"/> DVR & Wind (Powder)</div>
            <div className="p-3 rounded-xl bg-neutral-950 border border-neutral-800 text-xs text-neutral-400">
              <Row keys={['J']} desc="Scrub DVR backwards"/>
              <Row keys={['L']} desc="Return to Live"/>
              <div className="pt-2 flex items-center gap-2 text-[11px]"><Wind className="w-3.5 h-3.5 text-blue-400"/>Wind slider in Settings pushes gases sideways. Heat conduction diffuses temps between conductive metals.</div>
            </div>
          </div>
        </div>
        <div className="px-6 py-3 border-t border-neutral-800 bg-neutral-950 flex justify-end">
          <button onClick={onClose} className="px-4 py-1.5 rounded-xl bg-amber-500 text-neutral-950 font-bold text-xs">Got it</button>
        </div>
      </div>
    </div>
  );
};
