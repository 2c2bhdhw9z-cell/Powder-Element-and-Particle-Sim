import React, { useState } from 'react';
import {
  X, Users, Copy, Check, Send, Radio, Sparkles
} from 'lucide-react';

interface MultiplayerModalProps {
  onClose: () => void;
  roomId: string;
  setRoomId: (id: string) => void;
  userName: string;
  setUserName: (name: string) => void;
  isConnected: boolean;
  connectedUsers: { id: string; name: string; color: string }[];
  onConnectRoom: () => void;
  chatMessages: { userName: string; message: string; color: string }[];
  onSendChat: (msg: string) => void;
}

export const MultiplayerModal: React.FC<MultiplayerModalProps> = ({
  onClose,
  roomId,
  setRoomId,
  userName,
  setUserName,
  isConnected,
  connectedUsers,
  onConnectRoom,
  chatMessages,
  onSendChat
}) => {
  const [copied, setCopied] = useState<boolean>(false);
  const [chatInput, setChatInput] = useState<string>('');

  const handleCopyLink = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleSend = (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatInput.trim()) return;
    onSendChat(chatInput);
    setChatInput('');
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl w-full max-w-lg shadow-2xl text-white overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-neutral-800 flex items-center justify-between bg-neutral-950">
          <div className="flex items-center gap-2.5">
            <Users className="w-5 h-5 text-emerald-400" />
            <h2 className="text-base font-bold text-emerald-300">Real-Time Multiplayer Room</h2>
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
          {/* Room Setup Form */}
          <div className="space-y-3 bg-neutral-950 border border-neutral-800 rounded-2xl p-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Your Name</label>
                <input
                  type="text"
                  value={userName}
                  onChange={e => setUserName(e.target.value)}
                  className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-bold text-white focus:outline-none focus:border-emerald-500"
                />
              </div>

              <div>
                <label className="text-xs font-semibold text-neutral-400 block mb-1">Room Code</label>
                <input
                  type="text"
                  value={roomId}
                  onChange={e => setRoomId(e.target.value)}
                  className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-2 text-xs font-mono font-bold text-emerald-300 focus:outline-none focus:border-emerald-500"
                />
              </div>
            </div>

            <div className="flex items-center justify-between pt-2">
              <div className="flex items-center gap-2">
                <span className={`w-2.5 h-2.5 rounded-full ${isConnected ? 'bg-emerald-400 animate-pulse' : 'bg-red-500'}`} />
                <span className="text-xs font-medium text-neutral-300">
                  {isConnected ? 'Connected to Room' : 'Disconnected'}
                </span>
              </div>

              <button
                onClick={onConnectRoom}
                className="px-4 py-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 text-neutral-950 font-bold text-xs shadow-md shadow-emerald-500/20"
              >
                {isConnected ? 'Reconnect Room' : 'Join Room'}
              </button>
            </div>
          </div>

          {/* Connected Collaborators List */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-xs font-bold uppercase tracking-wider text-neutral-400">
                Collaborators In Session ({connectedUsers.length})
              </h3>
              <button
                onClick={handleCopyLink}
                className="text-xs text-emerald-400 hover:underline flex items-center gap-1 font-semibold"
              >
                {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                {copied ? 'Link Copied!' : 'Copy Room Link'}
              </button>
            </div>

            <div className="flex flex-wrap gap-2">
              {connectedUsers.map(u => (
                <div
                  key={u.id}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-neutral-950 border border-neutral-800 text-xs font-medium"
                >
                  <div
                    className="w-3 h-3 rounded-full border border-white/20"
                    style={{ backgroundColor: u.color }}
                  />
                  <span>{u.name}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Chat Messages */}
          <div className="bg-neutral-950 border border-neutral-800 rounded-2xl p-3 flex flex-col h-44">
            <div className="flex-1 overflow-y-auto space-y-2 pr-1 text-xs">
              {chatMessages.map((m, idx) => (
                <div key={idx} className="flex items-start gap-2">
                  <span className="font-bold" style={{ color: m.color }}>{m.userName}:</span>
                  <span className="text-neutral-300">{m.message}</span>
                </div>
              ))}
            </div>

            <form onSubmit={handleSend} className="flex items-center gap-2 pt-2 border-t border-neutral-900 mt-2">
              <input
                type="text"
                placeholder="Type chat message to room..."
                value={chatInput}
                onChange={e => setChatInput(e.target.value)}
                className="flex-1 bg-neutral-900 border border-neutral-800 rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-emerald-500"
              />
              <button
                type="submit"
                className="p-2 rounded-xl bg-emerald-500 text-neutral-950 font-bold hover:bg-emerald-400"
              >
                <Send className="w-3.5 h-3.5" />
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
};
