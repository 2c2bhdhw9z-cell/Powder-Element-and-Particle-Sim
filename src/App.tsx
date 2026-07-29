import React, { useState, useRef, useEffect, useCallback } from 'react';
import { PowderEngine } from './engine/powderEngine';
import { ParticleEngine } from './engine/particleEngine';
import { ElementRegistry } from './engine/elementRegistry';
import { PresetMap, UserSaveSlot, MultiplayerEvent } from './types/physics';

import { Header } from './components/Header';
import { PowderSandbox } from './components/PowderSandbox';
import { ParticleSandbox } from './components/ParticleSandbox';
import { CustomElementEditor } from './components/CustomElementEditor';
import { WorkshopModal } from './components/WorkshopModal';
import { MultiplayerModal } from './components/MultiplayerModal';
import { CloudSavesModal } from './components/CloudSavesModal';

export default function App() {
  // Global Physics Engine Instances
  const registryRef = useRef<ElementRegistry>(new ElementRegistry());
  const powderEngineRef = useRef<PowderEngine>(new PowderEngine(240, 160, registryRef.current));
  const particleEngineRef = useRef<ParticleEngine>(new ParticleEngine(800, 600));

  // Mode Selection
  const [activeMode, setActiveMode] = useState<'powder' | 'particle'>('powder');

  // Modal Dialogs State
  const [showWorkshop, setShowWorkshop] = useState<boolean>(false);
  const [isUploadModeInitial, setIsUploadModeInitial] = useState<boolean>(false);
  const [showEditor, setShowEditor] = useState<boolean>(false);
  const [showMultiplayer, setShowMultiplayer] = useState<boolean>(false);
  const [showCloudSaves, setShowCloudSaves] = useState<boolean>(false);

  // Multiplayer State
  const [roomId, setRoomId] = useState<string>('default-sandbox');
  const [userName, setUserName] = useState<string>('Physicist-' + Math.floor(Math.random() * 900 + 100));
  const [isConnected, setIsConnected] = useState<boolean>(false);
  const [connectedUsers, setConnectedUsers] = useState<{ id: string; name: string; color: string }[]>([]);
  const [chatMessages, setChatMessages] = useState<{ userName: string; message: string; color: string }[]>([]);
  const [isPollingMode, setIsPollingMode] = useState<boolean>(false);

  const socketRef = useRef<WebSocket | null>(null);
  const userIdRef = useRef<string>(Math.random().toString(36).substring(2, 9));
  const userColorRef = useRef<string>(`hsl(${Math.floor(Math.random() * 360)}, 80%, 65%)`);
  const latestEventIdRef = useRef<number>(0);

  // Incoming event router
  const handleIncomingEvent = useCallback((event: MultiplayerEvent) => {
    if (event.type === 'join' || event.type === 'leave') {
      if (event.payload?.users) {
        setConnectedUsers(event.payload.users);
      }
    } else if (event.type === 'draw' && event.payload) {
      const { x, y, size, elementId, shape } = event.payload;
      powderEngineRef.current.drawBrush(x, y, size, elementId, shape);
    } else if (event.type === 'chat' && event.payload) {
      setChatMessages(prev => [...prev.slice(-30), {
        userName: event.userName || 'Guest',
        message: event.payload.message,
        color: event.userColor || '#38bdf8'
      }]);
    }
  }, []);

  // Activate HTTP Polling mode for room synchronization
  const activateHttpPolling = useCallback(async () => {
    setIsPollingMode(true);
    setIsConnected(true);
    try {
      const res = await fetch('/api/room/join', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          roomId,
          userName,
          userId: userIdRef.current,
          userColor: userColorRef.current
        })
      });
      if (res.ok) {
        const data = await res.json();
        if (data.users) {
          setConnectedUsers(data.users);
        }
      }
    } catch (e) {
      // Keep room state active locally
    }
  }, [roomId, userName]);

  // Connect to room (tries WebSocket silently, falls back to HTTP sync)
  const connectSocket = useCallback(() => {
    activateHttpPolling();

    if (socketRef.current) {
      try {
        socketRef.current.close();
      } catch (e) {}
    }

    try {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/ws`;
      const ws = new WebSocket(wsUrl);
      socketRef.current = ws;

      ws.onopen = () => {
        setIsConnected(true);
        setIsPollingMode(false);
        ws.send(JSON.stringify({
          type: 'join',
          roomId,
          userName,
          userId: userIdRef.current,
          userColor: userColorRef.current,
          payload: {}
        }));
      };

      ws.onmessage = (e) => {
        try {
          const event: MultiplayerEvent = JSON.parse(e.data);
          handleIncomingEvent(event);
        } catch (err) {
          // Silent
        }
      };

      ws.onclose = () => {
        setIsPollingMode(true);
      };

      ws.onerror = () => {
        setIsPollingMode(true);
      };
    } catch (err) {
      setIsPollingMode(true);
    }
  }, [roomId, userName, handleIncomingEvent, activateHttpPolling]);

  // Initial Auto Connect Socket
  useEffect(() => {
    connectSocket();
    return () => {
      if (socketRef.current) {
        try { socketRef.current.close(); } catch (e) {}
      }
    };
  }, [connectSocket]);

  // Polling loop effect when in HTTP fallback mode
  useEffect(() => {
    if (!isPollingMode) return;

    const interval = setInterval(async () => {
      try {
        const res = await fetch(`/api/room/events?roomId=${encodeURIComponent(roomId)}&since=${latestEventIdRef.current}&userId=${userIdRef.current}`);
        if (res.ok) {
          const data = await res.json();
          if (data.latestId !== undefined) {
            latestEventIdRef.current = data.latestId;
          }
          if (data.users) {
            setConnectedUsers(data.users);
          }
          if (Array.isArray(data.events)) {
            data.events.forEach((evt: MultiplayerEvent) => {
              handleIncomingEvent(evt);
            });
          }
        }
      } catch (e) {
        // Quiet catch for polling network hiccups
      }
    }, 600);

    return () => clearInterval(interval);
  }, [isPollingMode, roomId, handleIncomingEvent]);

  // Emit Multiplayer Draw Events
  const handleEmitDraw = (drawPayload: any) => {
    const event: MultiplayerEvent = {
      type: 'draw',
      roomId,
      userId: userIdRef.current,
      userName,
      userColor: userColorRef.current,
      payload: drawPayload
    };

    if (socketRef.current && socketRef.current.readyState === WebSocket.OPEN) {
      socketRef.current.send(JSON.stringify(event));
    } else {
      fetch('/api/room/event', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ roomId, userId: userIdRef.current, event })
      }).catch(() => {});
    }
  };

  // Send Chat Message
  const handleSendChat = (message: string) => {
    const event: MultiplayerEvent = {
      type: 'chat',
      roomId,
      userId: userIdRef.current,
      userName,
      userColor: userColorRef.current,
      payload: { message }
    };

    setChatMessages(prev => [...prev.slice(-30), {
      userName,
      message,
      color: userColorRef.current
    }]);

    if (socketRef.current && socketRef.current.readyState === WebSocket.OPEN) {
      socketRef.current.send(JSON.stringify(event));
    } else {
      fetch('/api/room/event', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ roomId, userId: userIdRef.current, event })
      }).catch(() => {});
    }
  };

  // Handle Loading Workshop Maps or Cloud Saves
  const handleLoadMap = (map: PresetMap) => {
    if (map.gridDataBase64) {
      powderEngineRef.current.deserializeState(map.gridDataBase64);
    } else {
      powderEngineRef.current.resetGrid();
    }
  };

  const handleLoadSave = (save: UserSaveSlot) => {
    if (save.mode === 'powder') {
      setActiveMode('powder');
      powderEngineRef.current.deserializeState(save.data);
    } else {
      setActiveMode('particle');
      try {
        const particlesObj = JSON.parse(save.data);
        if (Array.isArray(particlesObj)) {
          particleEngineRef.current.particles = particlesObj;
        }
      } catch (e) {
        console.error('Failed to parse particle save data', e);
      }
    }
  };

  return (
    <div className="min-h-screen bg-neutral-950 text-white font-sans flex flex-col antialiased selection:bg-amber-500 selection:text-black">
      {/* Top Application Header Bar */}
      <Header
        activeMode={activeMode}
        setActiveMode={setActiveMode}
        onOpenWorkshop={() => { setIsUploadModeInitial(false); setShowWorkshop(true); }}
        onOpenEditor={() => setShowEditor(true)}
        onOpenMultiplayer={() => setShowMultiplayer(true)}
        onOpenCloudSaves={() => setShowCloudSaves(true)}
        isMultiplayerActive={isConnected}
        connectedUsersCount={connectedUsers.length}
      />

      {/* Main Simulation Stage View */}
      <main className="flex-1 flex flex-col">
        {activeMode === 'powder' ? (
          <PowderSandbox
            engine={powderEngineRef.current}
            registry={registryRef.current}
            onEmitDraw={handleEmitDraw}
            onOpenUploadMap={() => { setIsUploadModeInitial(true); setShowWorkshop(true); }}
          />
        ) : (
          <ParticleSandbox engine={particleEngineRef.current} />
        )}
      </main>

      {/* Custom Element & Behavior Editor Modal */}
      {showEditor && (
        <CustomElementEditor
          registry={registryRef.current}
          onClose={() => setShowEditor(false)}
          onElementSaved={() => {
            // Force re-render of registry
          }}
        />
      )}

      {/* Community Workshop Modal */}
      {showWorkshop && (
        <WorkshopModal
          engine={powderEngineRef.current}
          onClose={() => setShowWorkshop(false)}
          onLoadMap={handleLoadMap}
          isUploadModeInitial={isUploadModeInitial}
        />
      )}

      {/* Multiplayer Realtime Room Modal */}
      {showMultiplayer && (
        <MultiplayerModal
          onClose={() => setShowMultiplayer(false)}
          roomId={roomId}
          setRoomId={setRoomId}
          userName={userName}
          setUserName={setUserName}
          isConnected={isConnected}
          connectedUsers={connectedUsers}
          onConnectRoom={connectSocket}
          chatMessages={chatMessages}
          onSendChat={handleSendChat}
        />
      )}

      {/* Cloud Saves Modal */}
      {showCloudSaves && (
        <CloudSavesModal
          powderEngine={powderEngineRef.current}
          particleEngine={particleEngineRef.current}
          activeMode={activeMode}
          onClose={() => setShowCloudSaves(false)}
          onLoadSave={handleLoadSave}
        />
      )}
    </div>
  );
}
