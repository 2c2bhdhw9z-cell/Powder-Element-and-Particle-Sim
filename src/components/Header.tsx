import React from 'react';
import { Flame, Atom, Globe, Sliders, Users, Save, Sparkles } from 'lucide-react';

interface HeaderProps {
  activeMode: 'powder' | 'particle';
  setActiveMode: (mode: 'powder' | 'particle') => void;
  onOpenWorkshop: () => void;
  onOpenEditor: () => void;
  onOpenMultiplayer: () => void;
  onOpenCloudSaves: () => void;
  isMultiplayerActive: boolean;
  connectedUsersCount: number;
}

export const Header: React.FC<HeaderProps> = ({
  activeMode,
  setActiveMode,
  onOpenWorkshop,
  onOpenEditor,
  onOpenMultiplayer,
  onOpenCloudSaves,
  isMultiplayerActive,
  connectedUsersCount
}) => {
  return (
    <header className="bg-neutral-900 border-b border-neutral-800 text-white px-4 py-2.5 flex flex-wrap items-center justify-between gap-3 shadow-md select-none">
      {/* Title & Brand */}
      <div className="flex items-center gap-3">
        <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-amber-500 via-orange-600 to-red-600 flex items-center justify-center shadow-lg shadow-orange-500/20">
          <Flame className="w-5 h-5 text-white animate-pulse" />
        </div>
        <div>
          <h1 className="text-base font-bold tracking-wide bg-gradient-to-r from-amber-200 via-orange-300 to-rose-300 bg-clip-text text-transparent flex items-center gap-2">
            Powder & Particle Lab
            <span className="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-400 border border-amber-500/20">
              500 Elements
            </span>
          </h1>
          <p className="text-xs text-neutral-400">High-Performance Physics & Creation Engine</p>
        </div>
      </div>

      {/* Mode Switcher Tabs */}
      <div className="flex items-center bg-neutral-950 p-1 rounded-xl border border-neutral-800">
        <button
          onClick={() => setActiveMode('powder')}
          className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all ${
            activeMode === 'powder'
              ? 'bg-amber-500 text-neutral-950 shadow-md shadow-amber-500/20 font-bold'
              : 'text-neutral-400 hover:text-white hover:bg-neutral-900'
          }`}
        >
          <Flame className="w-3.5 h-3.5" />
          Powder Grid
        </button>
        <button
          onClick={() => setActiveMode('particle')}
          className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all ${
            activeMode === 'particle'
              ? 'bg-cyan-500 text-neutral-950 shadow-md shadow-cyan-500/20 font-bold'
              : 'text-neutral-400 hover:text-white hover:bg-neutral-900'
          }`}
        >
          <Atom className="w-3.5 h-3.5" />
          Particle Sandbox
        </button>
      </div>

      {/* Action Navigation Buttons */}
      <div className="flex items-center gap-2 flex-wrap">
        <button
          onClick={onOpenEditor}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-amber-300 border border-amber-500/30 text-xs font-medium transition-all"
        >
          <Sliders className="w-3.5 h-3.5" />
          Behavior Editor
        </button>

        <button
          onClick={onOpenWorkshop}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-purple-300 border border-purple-500/30 text-xs font-medium transition-all"
        >
          <Globe className="w-3.5 h-3.5" />
          Workshop Maps
        </button>

        <button
          onClick={onOpenMultiplayer}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg border text-xs font-medium transition-all ${
            isMultiplayerActive
              ? 'bg-emerald-500/20 border-emerald-500/50 text-emerald-300 animate-pulse'
              : 'bg-neutral-800 hover:bg-neutral-700 border-neutral-700 text-blue-300'
          }`}
        >
          <Users className="w-3.5 h-3.5" />
          {isMultiplayerActive ? `Live Room (${connectedUsersCount})` : 'Multiplayer'}
        </button>

        <button
          onClick={onOpenCloudSaves}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-neutral-200 border border-neutral-700 text-xs font-medium transition-all"
        >
          <Save className="w-3.5 h-3.5" />
          Cloud Saves
        </button>
      </div>
    </header>
  );
};
