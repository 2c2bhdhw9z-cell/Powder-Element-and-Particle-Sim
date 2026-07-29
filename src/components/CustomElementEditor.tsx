import React, { useState } from 'react';
import { ElementRegistry } from '../engine/elementRegistry';
import { ElementDefinition, InteractionRule } from '../types/physics';
import { X, Plus, Trash2, Check, Sliders, Sparkles, AlertCircle } from 'lucide-react';

interface CustomElementEditorProps {
  registry: ElementRegistry;
  onClose: () => void;
  onElementSaved: () => void;
}

export const CustomElementEditor: React.FC<CustomElementEditorProps> = ({
  registry,
  onClose,
  onElementSaved
}) => {
  const allElements = registry.getAllElements();
  const nextId = registry.getNextAvailableId();

  // Selected element ID to edit (default to next available custom ID)
  const [selectedId, setSelectedId] = useState<number>(nextId !== -1 ? nextId : 36);

  const existingEl = registry.getElement(selectedId);
  const isBuiltIn = selectedId < 36;

  // Form State
  const [name, setName] = useState<string>(existingEl.name || `Custom Element ${selectedId}`);
  const [category, setCategory] = useState<'Solids' | 'Liquids' | 'Gases' | 'Energetic' | 'Biological' | 'Special' | 'Custom'>(
    existingEl.category || 'Custom'
  );
  const [state, setState] = useState<ElementDefinition['state']>(existingEl.state || 'solid_movable');
  const [color, setColor] = useState<string>(existingEl.color || '#38bdf8');
  const [density, setDensity] = useState<number>(existingEl.density || 15);
  const [viscosity, setViscosity] = useState<number>(existingEl.viscosity || 1);
  const [flammability, setFlammability] = useState<number>(existingEl.flammability || 0);
  const [decayTicks, setDecayTicks] = useState<number>(existingEl.decayTicks || 0);
  const [decayIntoId, setDecayIntoId] = useState<number>(existingEl.decayIntoId || 0);
  const [gravityFactor, setGravityFactor] = useState<number>(existingEl.gravityFactor !== undefined ? existingEl.gravityFactor : 1);
  const [description, setDescription] = useState<string>(existingEl.description || '');

  // Custom Interaction Rules
  const [interactions, setInteractions] = useState<InteractionRule[]>(existingEl.interactions || []);

  // When switching element selection
  const handleSelectElement = (id: number) => {
    setSelectedId(id);
    const el = registry.getElement(id);
    setName(el.name);
    setCategory(el.category);
    setState(el.state);
    setColor(el.color);
    setDensity(el.density);
    setViscosity(el.viscosity || 1);
    setFlammability(el.flammability || 0);
    setDecayTicks(el.decayTicks || 0);
    setDecayIntoId(el.decayIntoId || 0);
    setGravityFactor(el.gravityFactor !== undefined ? el.gravityFactor : 1);
    setDescription(el.description || '');
    setInteractions(el.interactions ? [...el.interactions] : []);
  };

  // Add Interaction Rule
  const handleAddRule = () => {
    setInteractions([
      ...interactions,
      {
        targetElementId: 3, // Wood
        chance: 0.5,
        resultSelfId: 4, // Fire
        resultTargetId: 5, // Smoke
        explosionRadius: 0
      }
    ]);
  };

  const handleRemoveRule = (index: number) => {
    setInteractions(interactions.filter((_, i) => i !== index));
  };

  const handleRuleChange = (index: number, field: keyof InteractionRule, value: any) => {
    const updated = [...interactions];
    updated[index] = { ...updated[index], [field]: value };
    setInteractions(updated);
  };

  // Save Element to Registry
  const handleSave = () => {
    const newDef: ElementDefinition = {
      id: selectedId,
      name: name.trim() || `Element ${selectedId}`,
      category,
      state,
      color,
      density,
      viscosity: state === 'liquid' ? viscosity : undefined,
      flammability: flammability > 0 ? flammability : undefined,
      decayTicks: decayTicks > 0 ? decayTicks : undefined,
      decayIntoId,
      gravityFactor,
      interactions,
      description
    };

    registry.registerElement(newDef);
    onElementSaved();
    onClose();
  };

  // Delete Custom Element
  const handleDelete = () => {
    if (isBuiltIn) return;
    registry.deleteCustomElement(selectedId);
    onElementSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl w-full max-w-4xl max-h-[90vh] flex flex-col shadow-2xl text-white overflow-hidden">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 flex items-center justify-between bg-neutral-950">
          <div className="flex items-center gap-2">
            <Sliders className="w-5 h-5 text-amber-400" />
            <h2 className="text-lg font-bold text-amber-300">Custom Element & Behavior Editor</h2>
            <span className="text-xs bg-amber-500/10 text-amber-400 border border-amber-500/20 px-2 py-0.5 rounded-full font-mono">
              Slot #{selectedId} / 500
            </span>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-neutral-800 text-neutral-400 hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Left Column: Element Selection */}
          <div className="md:col-span-1 bg-neutral-950 border border-neutral-800 rounded-xl p-4 flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold uppercase tracking-wider text-neutral-400">Element Slot</h3>
              <button
                onClick={() => {
                  if (nextId !== -1) handleSelectElement(nextId);
                }}
                className="text-xs text-amber-400 hover:underline flex items-center gap-1 font-semibold"
              >
                <Plus className="w-3.5 h-3.5" />
                New Slot
              </button>
            </div>

            <div className="flex-1 overflow-y-auto max-h-[450px] space-y-1.5 pr-1">
              {allElements.map(el => {
                const isSel = selectedId === el.id;
                return (
                  <button
                    key={el.id}
                    onClick={() => handleSelectElement(el.id)}
                    className={`w-full flex items-center justify-between p-2 rounded-xl text-left text-xs transition-all border ${
                      isSel
                        ? 'bg-amber-500/20 border-amber-500 text-amber-200 font-bold'
                        : 'bg-neutral-900 border-neutral-800 text-neutral-300 hover:bg-neutral-800'
                    }`}
                  >
                    <div className="flex items-center gap-2">
                      <div className="w-3.5 h-3.5 rounded-full border border-white/20" style={{ backgroundColor: el.color }} />
                      <span className="truncate">{el.name}</span>
                    </div>
                    <span className="font-mono text-[10px] text-neutral-500">#{el.id}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Right Columns: Editor Parameters & Interaction Rules */}
          <div className="md:col-span-2 space-y-5">
            {isBuiltIn && (
              <div className="p-3 bg-amber-500/10 border border-amber-500/30 rounded-xl text-xs text-amber-300 flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>Editing slot #{selectedId}. Custom changes will override built-in behavior for this slot.</span>
              </div>
            )}

            {/* Basic Physical Attributes Form */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Element Name</label>
                <input
                  type="text"
                  value={name}
                  onChange={e => setName(e.target.value)}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-amber-500"
                />
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Category</label>
                <select
                  value={category}
                  onChange={e => setCategory(e.target.value as any)}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-amber-500"
                >
                  {['Solids', 'Liquids', 'Gases', 'Energetic', 'Biological', 'Special', 'Custom'].map(cat => (
                    <option key={cat} value={cat}>{cat}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">State of Matter</label>
                <select
                  value={state}
                  onChange={e => setState(e.target.value as any)}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-amber-500"
                >
                  <option value="solid_movable">Movable Powder / Solid</option>
                  <option value="solid_fixed">Fixed Wall / Solid</option>
                  <option value="liquid">Liquid Fluid</option>
                  <option value="gas">Gas / Steam</option>
                  <option value="plasma">Plasma / Fire</option>
                  <option value="energy">Energy Arc / Spark</option>
                </select>
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Particle Color</label>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={color}
                    onChange={e => setColor(e.target.value)}
                    className="w-9 h-8 rounded-lg bg-neutral-950 border border-neutral-800 cursor-pointer p-0.5"
                  />
                  <input
                    type="text"
                    value={color}
                    onChange={e => setColor(e.target.value)}
                    className="flex-1 bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-amber-500"
                  />
                </div>
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Density (Buoyancy Sinking)</label>
                <input
                  type="number"
                  value={density}
                  onChange={e => setDensity(parseInt(e.target.value) || 1)}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-amber-500"
                />
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Gravity Factor</label>
                <select
                  value={gravityFactor}
                  onChange={e => setGravityFactor(parseFloat(e.target.value))}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-amber-500"
                >
                  <option value={1}>1x Normal Gravity (Falls Down)</option>
                  <option value={-1}>-1x Anti-Gravity (Falls Up)</option>
                  <option value={0}>0x Floating / Fixed</option>
                </select>
              </div>
            </div>

            {/* Custom Chemical Reaction Rules Section */}
            <div className="bg-neutral-950 border border-neutral-800 rounded-xl p-4 space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="text-xs font-bold uppercase tracking-wider text-amber-300 flex items-center gap-1.5">
                  <Sparkles className="w-4 h-4 text-amber-400" />
                  Custom Reaction Behavior Rules
                </h4>

                <button
                  onClick={handleAddRule}
                  className="text-xs bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 px-3 py-1 rounded-lg font-semibold flex items-center gap-1"
                >
                  <Plus className="w-3.5 h-3.5" />
                  Add Interaction Rule
                </button>
              </div>

              {interactions.length === 0 ? (
                <p className="text-xs text-neutral-500 italic">No custom interaction rules added yet.</p>
              ) : (
                <div className="space-y-2 max-h-[200px] overflow-y-auto pr-1">
                  {interactions.map((rule, idx) => (
                    <div key={idx} className="bg-neutral-900 border border-neutral-800 rounded-xl p-3 flex flex-wrap items-center justify-between gap-3 text-xs">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-neutral-400">When touching:</span>
                        <select
                          value={rule.targetElementId}
                          onChange={e => handleRuleChange(idx, 'targetElementId', parseInt(e.target.value))}
                          className="bg-neutral-950 border border-neutral-800 rounded-lg px-2 py-1 text-white font-bold"
                        >
                          {allElements.map(el => (
                            <option key={el.id} value={el.id}>{el.name}</option>
                          ))}
                        </select>

                        <span className="text-neutral-400">Convert Self to:</span>
                        <select
                          value={rule.resultSelfId || 0}
                          onChange={e => handleRuleChange(idx, 'resultSelfId', parseInt(e.target.value))}
                          className="bg-neutral-950 border border-neutral-800 rounded-lg px-2 py-1 text-white font-bold"
                        >
                          {allElements.map(el => (
                            <option key={el.id} value={el.id}>{el.name}</option>
                          ))}
                        </select>
                      </div>

                      <button
                        onClick={() => handleRemoveRule(idx)}
                        className="text-red-400 hover:text-red-300 p-1"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-neutral-800 bg-neutral-950 flex items-center justify-between">
          {!isBuiltIn ? (
            <button
              onClick={handleDelete}
              className="px-4 py-2 rounded-xl bg-red-950/60 hover:bg-red-900 text-red-300 border border-red-800/60 text-xs font-bold flex items-center gap-1.5"
            >
              <Trash2 className="w-4 h-4" />
              Delete Custom Element
            </button>
          ) : <div />}

          <div className="flex items-center gap-3">
            <button
              onClick={onClose}
              className="px-4 py-2 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-neutral-300 text-xs font-semibold"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              className="px-5 py-2 rounded-xl bg-amber-500 hover:bg-amber-400 text-neutral-950 text-xs font-bold shadow-lg shadow-amber-500/20 flex items-center gap-1.5"
            >
              <Check className="w-4 h-4" />
              Save Element #{selectedId}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
