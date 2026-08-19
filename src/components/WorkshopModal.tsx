import React, { useState, useEffect } from 'react';
import { PresetMap } from '../types/physics';
import { PowderEngine } from '../engine/powderEngine';
import {
  X, Globe, ThumbsUp, Download, Sparkles, Search, Filter, Upload,
  CheckCircle2
} from 'lucide-react';

interface WorkshopModalProps {
  engine: PowderEngine;
  onClose: () => void;
  onLoadMap: (map: PresetMap) => void;
  isUploadModeInitial?: boolean;
}

export const WorkshopModal: React.FC<WorkshopModalProps> = ({
  engine,
  onClose,
  onLoadMap,
  isUploadModeInitial = false
}) => {
  const [maps, setMaps] = useState<PresetMap[]>([]);
  const [activeTab, setActiveTab] = useState<'browse' | 'upload'>(isUploadModeInitial ? 'upload' : 'browse');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [selectedTag, setSelectedTag] = useState<string>('All');

  // Upload Form State
  const [uploadTitle, setUploadTitle] = useState<string>('');
  const [uploadAuthor, setUploadAuthor] = useState<string>('CreatorUser');
  const [uploadDesc, setUploadDesc] = useState<string>('');
  const [uploadTags, setUploadTags] = useState<string>('Physics, Sandbox');
  const [uploadSuccess, setUploadSuccess] = useState<boolean>(false);

  // Fetch Community Workshop Creations from Server API
  const fetchMaps = async () => {
    try {
      const res = await fetch('/api/maps');
      if (res.ok) {
        const data = await res.json();
        setMaps(data);
      }
    } catch (e) {
      console.error('Failed to load workshop maps', e);
    }
  };

  useEffect(() => {
    fetchMaps();
  }, []);

  // Upvote / Like Map Action
  const handleLike = async (mapId: string) => {
    try {
      const res = await fetch(`/api/maps/${mapId}/like`, { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        setMaps(prev => prev.map(m => m.id === mapId ? { ...m, likes: data.likes } : m));
      }
    } catch (e) {
      console.error('Like failed', e);
    }
  };

  // Download / Load Creation Into Engine
  const handleDownload = async (map: PresetMap) => {
    try {
      await fetch(`/api/maps/${map.id}/download`, { method: 'POST' });
      onLoadMap(map);
      onClose();
    } catch (e) {
      console.error('Download failed', e);
      onLoadMap(map);
      onClose();
    }
  };

  // Publish Current Sandbox Canvas
  const handlePublishCurrentMap = async () => {
    if (!uploadTitle.trim()) return;

    const serialized = engine.serializeState();
    let thumbnail = '';
    try {
      thumbnail = engine.captureThumbnail ? engine.captureThumbnail() : '';
    } catch (e) { thumbnail = ''; }

    const newMapPayload: Partial<PresetMap> = {
      title: uploadTitle,
      author: uploadAuthor || 'Anonymous',
      description: uploadDesc || 'A custom physics simulation level.',
      tags: uploadTags.split(',').map(t => t.trim()).filter(Boolean),
      width: engine.width,
      height: engine.height,
      gravityX: engine.gravityX,
      gravityY: engine.gravityY,
      gridDataBase64: serialized,
      thumbnail
    };

    try {
      const res = await fetch('/api/maps', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newMapPayload)
      });

      if (res.ok) {
        setUploadSuccess(true);
        setTimeout(() => {
          setUploadSuccess(false);
          setActiveTab('browse');
          fetchMaps();
        }, 1200);
      }
    } catch (e) {
      console.error('Failed to publish map', e);
    }
  };

  // Filtered maps
  const filteredMaps = maps.filter(m => {
    const matchesSearch = m.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          m.author.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          m.description.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTag = selectedTag === 'All' || m.tags.includes(selectedTag);
    return matchesSearch && matchesTag;
  });

  const allTags = ['All', 'Lava', 'Explosion', 'Acid', 'Glass', 'Circuit', 'Challenge', 'Biological', 'Ants'];

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl w-full max-w-4xl max-h-[90vh] flex flex-col shadow-2xl text-white overflow-hidden">
        {/* Header Tabs */}
        <div className="px-6 py-4 border-b border-neutral-800 flex items-center justify-between bg-neutral-950">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-xl bg-purple-500/20 border border-purple-500/40 flex items-center justify-center text-purple-300">
              <Globe className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-purple-300">Community Workshop</h2>
              <p className="text-xs text-neutral-400">Discover, like, download, and publish user creations</p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <div className="flex bg-neutral-900 p-1 rounded-xl border border-neutral-800">
              <button
                onClick={() => setActiveTab('browse')}
                className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                  activeTab === 'browse' ? 'bg-purple-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'
                }`}
              >
                Browse Creations
              </button>
              <button
                onClick={() => setActiveTab('upload')}
                className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                  activeTab === 'upload' ? 'bg-purple-500 text-neutral-950 font-bold' : 'text-neutral-400 hover:text-white'
                }`}
              >
                Publish Current Map
              </button>
            </div>

            <button
              onClick={onClose}
              className="p-1.5 rounded-xl hover:bg-neutral-800 text-neutral-400 hover:text-white"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Content Body */}
        {activeTab === 'browse' ? (
          <div className="flex-1 overflow-y-auto p-6 space-y-4">
            {/* Search Bar & Tag Filters */}
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="relative flex-1 min-w-[240px]">
                <Search className="w-4 h-4 text-neutral-500 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  placeholder="Search maps by title, author, description..."
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  className="w-full bg-neutral-950 border border-neutral-800 rounded-xl pl-9 pr-4 py-2 text-xs font-medium text-white focus:outline-none focus:border-purple-500"
                />
              </div>

              <div className="flex items-center gap-1.5 overflow-x-auto pb-1 scrollbar-none">
                {allTags.map(tag => (
                  <button
                    key={tag}
                    onClick={() => setSelectedTag(tag)}
                    className={`px-2.5 py-1 rounded-lg text-xs font-medium whitespace-nowrap transition-all ${
                      selectedTag === tag
                        ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40'
                        : 'bg-neutral-950 text-neutral-400 hover:text-neutral-200 border border-neutral-800'
                    }`}
                  >
                    {tag}
                  </button>
                ))}
              </div>
            </div>

            {/* Gallery Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredMaps.map(map => (
                <div
                  key={map.id}
                  className="bg-neutral-950 border border-neutral-800 rounded-2xl p-4 flex flex-col justify-between gap-3 hover:border-purple-500/50 transition-all shadow-md group overflow-hidden"
                >
                  {map.thumbnail && (
                    <div className=" -mx-4 -mt-4 mb-2 h-28 bg-neutral-900 overflow-hidden border-b border-neutral-800">
                      <img src={map.thumbnail} alt={map.title} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" style={{ imageRendering: 'pixelated' }} />
                    </div>
                  )}
                  <div>
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-bold text-sm text-purple-200 group-hover:text-purple-300 truncate">
                        {map.title}
                      </h3>
                      <span className="text-[10px] text-neutral-500 font-mono shrink-0">
                        by {map.author}
                      </span>
                    </div>

                    <p className="text-xs text-neutral-400 mt-2 line-clamp-2 leading-relaxed">
                      {map.description}
                    </p>

                    <div className="flex flex-wrap gap-1 mt-3">
                      {map.tags.map(t => (
                        <span key={t} className="text-[10px] px-1.5 py-0.5 rounded bg-neutral-900 border border-neutral-800 text-neutral-400 font-mono">
                          #{t}
                        </span>
                      ))}
                    </div>
                  </div>

                  {/* Actions & Likes Bar */}
                  <div className="flex items-center justify-between pt-3 border-t border-neutral-900 text-xs">
                    <button
                      onClick={() => handleLike(map.id)}
                      className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-neutral-900 hover:bg-purple-500/10 text-neutral-300 hover:text-purple-300 border border-neutral-800 transition-all font-mono"
                    >
                      <ThumbsUp className="w-3.5 h-3.5 text-purple-400" />
                      <span>{map.likes}</span>
                    </button>

                    <button
                      onClick={() => handleDownload(map)}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-purple-500 hover:bg-purple-400 text-neutral-950 font-bold shadow-md shadow-purple-500/20 transition-all"
                    >
                      <Download className="w-3.5 h-3.5" />
                      Try Level
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          /* Publish Map Form Tab */
          <div className="flex-1 overflow-y-auto p-6 max-w-xl mx-auto w-full space-y-4">
            <h3 className="text-sm font-bold text-purple-300 uppercase tracking-wider flex items-center gap-2">
              <Upload className="w-4 h-4 text-purple-400" />
              Publish Active Sandbox as Level
            </h3>

            {uploadSuccess ? (
              <div className="bg-emerald-500/10 border border-emerald-500/30 rounded-2xl p-6 text-center space-y-2">
                <CheckCircle2 className="w-10 h-10 text-emerald-400 mx-auto" />
                <h4 className="font-bold text-emerald-300">Published to Workshop!</h4>
                <p className="text-xs text-neutral-400">Your creation is now live for all players to try, like, and download.</p>
              </div>
            ) : (
              <div className="space-y-4 bg-neutral-950 border border-neutral-800 rounded-2xl p-5">
                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">Level Title</label>
                  <input
                    type="text"
                    placeholder="e.g. Acid Volcano Castle"
                    value={uploadTitle}
                    onChange={e => setUploadTitle(e.target.value)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-purple-500"
                  />
                </div>

                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">Creator Name</label>
                  <input
                    type="text"
                    value={uploadAuthor}
                    onChange={e => setUploadAuthor(e.target.value)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-purple-500"
                  />
                </div>

                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">Description</label>
                  <textarea
                    rows={3}
                    placeholder="Describe the puzzle, explosion, or ecosystem mechanics..."
                    value={uploadDesc}
                    onChange={e => setUploadDesc(e.target.value)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-xl p-3 text-xs text-white focus:outline-none focus:border-purple-500"
                  />
                </div>

                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">Tags (comma separated)</label>
                  <input
                    type="text"
                    value={uploadTags}
                    onChange={e => setUploadTags(e.target.value)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-purple-500"
                  />
                </div>

                <button
                  onClick={handlePublishCurrentMap}
                  disabled={!uploadTitle.trim()}
                  className="w-full py-2.5 rounded-xl bg-purple-500 hover:bg-purple-400 disabled:opacity-40 text-neutral-950 font-bold text-xs shadow-lg shadow-purple-500/20 flex items-center justify-center gap-2"
                >
                  <Sparkles className="w-4 h-4" />
                  Publish Map to Community
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
