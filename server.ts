import express from 'express';
import path from 'path';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { createServer as createViteServer } from 'vite';
import { PresetMap, UserSaveSlot, MultiplayerEvent } from './src/types/physics';

const app = express();
const PORT = 3000;

app.use(express.json({ limit: '10mb' }));

// Pre-seeded Community Workshop Creations
let communityMaps: PresetMap[] = [
  {
    id: 'map-volcano-01',
    title: 'Volcano Eruption Challenge',
    author: 'FireCraftMaster',
    description: 'An active magma chamber beneath a wooden valley. Trigger the TNT to launch molten lava across the map!',
    thumbnail: '',
    likes: 342,
    downloads: 1205,
    tags: ['Lava', 'Explosion', 'Challenge'],
    createdAt: new Date().toISOString(),
    width: 240,
    height: 160,
    gravityX: 0,
    gravityY: 1,
    gridDataBase64: '',
  },
  {
    id: 'map-acid-castle-02',
    title: 'Acid Pit & Glass Castle',
    author: 'QuantumArchitect',
    description: 'A fortified glass structure suspended over a boiling lake of acid. Can you break the seal without destroying the core?',
    thumbnail: '',
    likes: 218,
    downloads: 890,
    tags: ['Acid', 'Glass', 'Structure'],
    createdAt: new Date().toISOString(),
    width: 240,
    height: 160,
    gravityX: 0,
    gravityY: 1,
    gridDataBase64: '',
  },
  {
    id: 'map-circuit-laser-03',
    title: 'Electricity Circuit & Portal Loop',
    author: 'SparkEngineer',
    description: 'A continuous electrical circuit powering portal loops and duplicator machines. Connect the spark wire!',
    thumbnail: '',
    likes: 412,
    downloads: 1650,
    tags: ['Circuit', 'Portal', 'Tech'],
    createdAt: new Date().toISOString(),
    width: 240,
    height: 160,
    gravityX: 0,
    gravityY: 1,
    gridDataBase64: '',
  },
  {
    id: 'map-bio-lab-04',
    title: 'Bio-Virus Containment Unit',
    author: 'DrBiohazard',
    description: 'A sealed glass chamber filled with infectious viruses. Release water or fire to observe biological mutation.',
    thumbnail: '',
    likes: 195,
    downloads: 640,
    tags: ['Virus', 'Biological', 'Lab'],
    createdAt: new Date().toISOString(),
    width: 240,
    height: 160,
    gravityX: 0,
    gravityY: 1,
    gridDataBase64: '',
  },
  {
    id: 'map-ant-colony-05',
    title: 'Ant Colony & Plant Maze',
    author: 'NatureLover',
    description: 'Living ants tunneling through rich dirt while plant vines grow with water source blocks.',
    thumbnail: '',
    likes: 289,
    downloads: 970,
    tags: ['Ants', 'Plants', 'Ecosystem'],
    createdAt: new Date().toISOString(),
    width: 240,
    height: 160,
    gravityX: 0,
    gravityY: 1,
    gridDataBase64: '',
  }
];

// In-Memory Cloud User Saves Store
let cloudSaves: Record<string, UserSaveSlot[]> = {};

// --- API ENDPOINTS ---

// Healthcheck
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// Community Workshop - Get All Maps
app.get('/api/maps', (req, res) => {
  res.json(communityMaps);
});

// Community Workshop - Create / Upload Map
app.post('/api/maps', (req, res) => {
  const newMap: PresetMap = {
    ...req.body,
    id: 'map-' + Date.now(),
    likes: 1,
    downloads: 0,
    createdAt: new Date().toISOString(),
  };
  communityMaps.unshift(newMap);
  res.json(newMap);
});

// Community Workshop - Like Map
app.post('/api/maps/:id/like', (req, res) => {
  const map = communityMaps.find(m => m.id === req.params.id);
  if (map) {
    map.likes += 1;
    res.json({ success: true, likes: map.likes });
  } else {
    res.status(404).json({ error: 'Map not found' });
  }
});

// Community Workshop - Download Map
app.post('/api/maps/:id/download', (req, res) => {
  const map = communityMaps.find(m => m.id === req.params.id);
  if (map) {
    map.downloads += 1;
    res.json(map);
  } else {
    res.status(404).json({ error: 'Map not found' });
  }
});

// Cloud Saves - Get User Saves
app.get('/api/saves/:userId', (req, res) => {
  const saves = cloudSaves[req.params.userId] || [];
  res.json(saves);
});

// Cloud Saves - Save Slot
app.post('/api/saves/:userId', (req, res) => {
  const { userId } = req.params;
  if (!cloudSaves[userId]) cloudSaves[userId] = [];

  const newSave: UserSaveSlot = {
    id: 'save-' + Date.now(),
    name: req.body.name || 'Untitled Save',
    timestamp: new Date().toLocaleDateString() + ' ' + new Date().toLocaleTimeString(),
    mode: req.body.mode || 'powder',
    data: req.body.data
  };

  cloudSaves[userId].unshift(newSave);
  res.json(newSave);
});

// --- HTTP & WEBSOCKET SERVER SETUP ---
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

// HTTP Polling fallback room event storage
interface BufferedEvent {
  id: number;
  roomId: string;
  senderId: string;
  event: MultiplayerEvent;
  timestamp: number;
}

let eventCounter = 0;
const roomEventLog: Map<string, BufferedEvent[]> = new Map();
const httpRoomUsers: Map<string, Map<string, { id: string; name: string; color: string; lastActive: number }>> = new Map();

function addRoomEvent(roomId: string, senderId: string, event: MultiplayerEvent) {
  if (!roomEventLog.has(roomId)) {
    roomEventLog.set(roomId, []);
  }
  const buffer = roomEventLog.get(roomId)!;
  eventCounter++;
  buffer.push({
    id: eventCounter,
    roomId,
    senderId,
    event,
    timestamp: Date.now()
  });
  // Keep last 100 events per room
  if (buffer.length > 100) {
    buffer.shift();
  }
}

// HTTP Room API Endpoints (Polling Fallback)
app.post('/api/room/join', (req, res) => {
  const { roomId = 'default-sandbox', userName = 'Guest', userId = Math.random().toString(36).substring(2, 9) } = req.body;
  const userColor = req.body.userColor || `hsl(${Math.floor(Math.random() * 360)}, 80%, 65%)`;

  if (!httpRoomUsers.has(roomId)) {
    httpRoomUsers.set(roomId, new Map());
  }
  const roomUsers = httpRoomUsers.get(roomId)!;
  roomUsers.set(userId, { id: userId, name: userName, color: userColor, lastActive: Date.now() });

  const activeUsersList = Array.from(roomUsers.values());
  res.json({ success: true, userId, userColor, users: activeUsersList });
});

app.post('/api/room/event', (req, res) => {
  const { roomId = 'default-sandbox', userId, event } = req.body;
  if (event) {
    addRoomEvent(roomId, userId || '', event);
    // Also broadcast to WebSocket clients
    broadcastToRoom(roomId, event);
  }
  res.json({ success: true });
});

app.get('/api/room/events', (req, res) => {
  const roomId = (req.query.roomId as string) || 'default-sandbox';
  const since = parseInt(req.query.since as string) || 0;
  const userId = req.query.userId as string;

  // Refresh user heartbeat
  if (userId && httpRoomUsers.has(roomId)) {
    const user = httpRoomUsers.get(roomId)?.get(userId);
    if (user) user.lastActive = Date.now();
  }

  const buffer = roomEventLog.get(roomId) || [];
  const newEvents = buffer.filter(e => e.id > since && e.senderId !== userId);
  const latestId = buffer.length > 0 ? buffer[buffer.length - 1].id : since;

  const roomUsers = httpRoomUsers.get(roomId);
  const usersList = roomUsers ? Array.from(roomUsers.values()).filter(u => Date.now() - u.lastActive < 15000) : [];

  res.json({
    events: newEvents.map(e => e.event),
    latestId,
    users: usersList
  });
});

// Upgrade Handling for WebSocket
server.on('upgrade', (request, socket, head) => {
  try {
    const host = request.headers.host || 'localhost';
    const pathname = request.url ? new URL(request.url, `http://${host}`).pathname : '';
    if (pathname === '/ws') {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } else {
      socket.destroy();
    }
  } catch (e) {
    socket.destroy();
  }
});

// Multiplayer Room Management
interface ClientSocket extends WebSocket {
  roomId?: string;
  userId?: string;
  userName?: string;
  userColor?: string;
}

const rooms: Map<string, Set<ClientSocket>> = new Map();

wss.on('connection', (ws: ClientSocket) => {
  ws.on('message', (messageRaw: string) => {
    try {
      const event: MultiplayerEvent = JSON.parse(messageRaw.toString());

      if (event.type === 'join') {
        ws.roomId = event.roomId || 'default-sandbox';
        ws.userId = event.userId || Math.random().toString(36).substring(2, 9);
        ws.userName = event.userName || 'Guest-' + ws.userId.slice(0, 4);
        ws.userColor = event.userColor || `hsl(${Math.floor(Math.random() * 360)}, 80%, 65%)`;

        if (!rooms.has(ws.roomId)) {
          rooms.set(ws.roomId, new Set());
        }
        rooms.get(ws.roomId)!.add(ws);

        // Track in HTTP users map as well
        if (!httpRoomUsers.has(ws.roomId)) {
          httpRoomUsers.set(ws.roomId, new Map());
        }
        httpRoomUsers.get(ws.roomId)!.set(ws.userId, {
          id: ws.userId,
          name: ws.userName,
          color: ws.userColor,
          lastActive: Date.now()
        });

        // Notify room members
        broadcastToRoom(ws.roomId, {
          type: 'join',
          roomId: ws.roomId,
          userId: ws.userId,
          userName: ws.userName,
          userColor: ws.userColor,
          payload: { users: getRoomUsers(ws.roomId) }
        });
      } else if (ws.roomId && rooms.has(ws.roomId)) {
        // Broadcast drawing, cursor, clear, speed, particle additions to room members
        addRoomEvent(ws.roomId, ws.userId || '', event);
        broadcastToRoom(ws.roomId, event, ws);
      }
    } catch (err) {
      console.error('Error handling WebSocket message:', err);
    }
  });

  ws.on('close', () => {
    if (ws.roomId && rooms.has(ws.roomId)) {
      const roomClients = rooms.get(ws.roomId)!;
      roomClients.delete(ws);

      if (ws.userId && httpRoomUsers.has(ws.roomId)) {
        httpRoomUsers.get(ws.roomId)!.delete(ws.userId);
      }

      if (roomClients.size === 0) {
        rooms.delete(ws.roomId);
      } else {
        broadcastToRoom(ws.roomId, {
          type: 'leave',
          roomId: ws.roomId,
          userId: ws.userId || '',
          payload: { users: getRoomUsers(ws.roomId) }
        });
      }
    }
  });
});

function broadcastToRoom(roomId: string, event: MultiplayerEvent, sender?: ClientSocket) {
  const roomClients = rooms.get(roomId);
  if (!roomClients) return;

  const msgStr = JSON.stringify(event);
  roomClients.forEach(client => {
    if (client !== sender && client.readyState === WebSocket.OPEN) {
      client.send(msgStr);
    }
  });
}

function getRoomUsers(roomId: string) {
  const roomClients = rooms.get(roomId);
  if (!roomClients) return [];
  return Array.from(roomClients).map(c => ({
    id: c.userId || '',
    name: c.userName || 'Guest',
    color: c.userColor || '#38bdf8'
  }));
}

// --- VITE / STATIC SERVING ---
async function start() {
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`Powder & Particle Simulator running on http://0.0.0.0:${PORT}`);
  });
}

start();
