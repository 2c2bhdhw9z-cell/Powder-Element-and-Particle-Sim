import React, { useState, useEffect } from 'react';
import { UserSaveSlot } from '../types/physics';
import { PowderEngine } from '../engine/powderEngine';
import { ParticleEngine } from '../engine/particleEngine';
import {
  X, Save, Download, Trash2, Plus, Clock, HardDrive, CheckCircle2
} from 'lucide-react';

interface CloudSavesModalProps {
  powderEngine: PowderEngine;
  particleEngine: ParticleEngine;
  activeMode: 'powder' | 'particle';
  onClose: () => void;
  onLoadSave: (save: UserSaveSlot) => void;
}

export const CloudSavesModal: React.FC<CloudSavesModalProps> = ({
  powderEngine,
  particleEngine,
  activeMode,
  onClose,
  onLoadSave
}) => {
  const [saves, setSaves] = useState<UserSaveSlot[]>([]);
  const [saveName, setSaveName] = useState<string>('');
  const [savedSuccess, setSavedSuccess] = useState<boolean>(false);
  const userId = 'default-user';

  const fetchSaves = async () => {
    try {
      const res = await fetch(`/api/saves/${userId}`);
      if (res.ok) {
        const data = await res.json();
        setSaves(data);
      }
    } catch (e) {
      console.error('Failed to load cloud saves', e);
    }
  };

  useEffect(() => {
    fetchSaves();
  }, []);

  const handleCreateSave = async () => {
    const dataStr = activeMode === 'powder'
      ? powderEngine.serializeState()
      : JSON.stringify(particleEngine.particles);

    const payload = {
      name: saveName.trim() || `${activeMode === 'powder' ? 'Powder' : 'Particle'} Sandbox Snapshot`,
      mode: activeMode,
      data: dataStr
    };

    try {
      const res = await fetch(`/api/saves/${userId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (res.ok) {
        setSavedSuccess(true);
        setSaveName('');
        fetchSaves();
        setTimeout(() => setSavedSuccess(false), 2000);
      }
    } catch (e) {
      console.error('Save failed', e);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl w-full max-w-lg shadow-2xl text-white overflow-hidden flex flex-col max-h-[85vh]">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 flex items-center justify-between bg-neutral-950">
          <div className="flex items-center gap-2.5">
            <HardDrive className="w-5 h-5 text-amber-400" />
            <h2 className="text-base font-bold text-amber-300">Cloud Saves & Snapshots</h2>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-neutral-800 text-neutral-400 hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 space-y-5 flex-1 overflow-y-auto">
          {/* Create Save Form */}
          <div className="bg-neutral-950 border border-neutral-800 rounded-2xl p-4 space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-amber-300 flex items-center gap-2">
              <Save className="w-4 h-4 text-amber-400" />
              Save Current {activeMode === 'powder' ? 'Powder Grid' : 'Particle Sandbox'} State
            </h3>

            <div className="flex items-center gap-2">
              <input
                type="text"
                placeholder="Enter save name..."
                value={saveName}
                onChange={e => setSaveName(e.target.value)}
                className="flex-1 bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-amber-500"
              />
              <button
                onClick={handleCreateSave}
                className="px-4 py-2 rounded-xl bg-amber-500 hover:bg-amber-400 text-neutral-950 font-bold text-xs shadow-md shadow-amber-500/20 flex items-center gap-1 shrink-0"
              >
                <Plus className="w-4 h-4" />
                Save Slot
              </button>
            </div>

            {savedSuccess && (
              <p className="text-xs text-emerald-400 flex items-center gap-1 font-semibold">
                <CheckCircle2 className="w-3.5 h-3.5" /> Saved to cloud successfully!
              </p>
            )}
          </div>

          {/* Saves List */}
          <div className="space-y-2">
            <h3 className="text-xs font-bold uppercase tracking-wider text-neutral-400">
              Your Cloud Saves ({saves.length})
            </h3>

            {saves.length === 0 ? (
              <p className="text-xs text-neutral-500 italic p-4 text-center">No cloud saves stored yet.</p>
            ) : (
              <div className="space-y-2 max-h-[250px] overflow-y-auto pr-1">
                {saves.map(save => (
                  <div
                    key={save.id}
                    className="bg-neutral-950 border border-neutral-800 rounded-xl p-3 flex items-center justify-between gap-3 text-xs"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-amber-200">{save.name}</span>
                        <span className="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-neutral-900 text-neutral-400">
                          {save.mode}
                        </span>
                      </div>
                      <p className="text-[10px] text-neutral-500 flex items-center gap-1 mt-1 font-mono">
                        <Clock className="w-3 h-3" />
                        {save.timestamp}
                      </p>
                    </div>

                    <button
                      onClick={() => {
                        onLoadSave(save);
                        onClose();
                      }}
                      className="px-3 py-1.5 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 text-xs font-bold flex items-center gap-1"
                    >
                      <Download className="w-3.5 h-3.5" />
                      Restore
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
