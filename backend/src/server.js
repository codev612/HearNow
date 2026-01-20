import express from 'express';
import { WebSocketServer } from 'ws';
import { createClient, LiveTranscriptionEvents } from '@deepgram/sdk';
import dotenv from 'dotenv';
import cors from 'cors';
import { createServer } from 'http';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'HearNow backend is running' });
});

// Create HTTP server
const server = createServer(app);

// Create WebSocket server
const wss = new WebSocketServer({ server, path: '/listen' });

// Deepgram client
const deepgram = createClient(process.env.DEEPGRAM_API_KEY);

wss.on('connection', (ws) => {
  console.log('Client connected');

  let deepgramLive = null;

  // Handle incoming messages from client
  ws.on('message', async (message) => {
    try {
      // Try to parse as JSON first, otherwise treat as binary audio data
      let data;
      try {
        data = JSON.parse(message);
      } catch (e) {
        // Not JSON, might be binary audio data
        if (deepgramLive) {
          deepgramLive.send(message);
        }
        return;
      }

      if (data.type === 'start') {
        // Check if API key is set
        if (!process.env.DEEPGRAM_API_KEY) {
          console.error('Deepgram API key not configured');
          ws.send(JSON.stringify({ 
            type: 'error', 
            message: 'Server error: Deepgram API key not configured. Please set DEEPGRAM_API_KEY in .env file' 
          }));
          return;
        }

        // Initialize Deepgram live connection
        console.log('Starting Deepgram connection...');
        
        try {
          deepgramLive = deepgram.listen.live({
            model: 'nova-3',
            language: 'en',
            smart_format: true,
            punctuate: true,
            interim_results: true,
            encoding: 'linear16',
            sample_rate: 16000,
          });

          // Handle Deepgram events
          deepgramLive.on(LiveTranscriptionEvents.Open, () => {
            console.log('Deepgram connection opened');
            ws.send(JSON.stringify({ type: 'status', message: 'ready' }));
          });

          deepgramLive.on(LiveTranscriptionEvents.Transcript, (data) => {
            const transcript = data.channel.alternatives[0]?.transcript;
            if (transcript) {
              const isFinal = data.is_final === true;
              const isInterim = data.is_final === false;
              ws.send(JSON.stringify({
                type: 'transcript',
                text: transcript,
                is_final: isFinal,
                is_interim: isInterim,
                confidence: data.channel.alternatives[0].confidence || 0
              }));
            }
          });

          deepgramLive.on(LiveTranscriptionEvents.Error, (error) => {
            console.error('Deepgram error:', error);
            ws.send(JSON.stringify({ type: 'error', message: error.message || 'Deepgram error' }));
          });

          deepgramLive.on(LiveTranscriptionEvents.Close, () => {
            console.log('Deepgram connection closed');
            deepgramLive = null;
          });
        } catch (error) {
          console.error('Failed to start Deepgram connection:', error);
          ws.send(JSON.stringify({ type: 'error', message: 'Failed to connect to Deepgram: ' + error.message }));
          deepgramLive = null;
        }

      } else if (data.type === 'audio' && deepgramLive) {
        // Forward audio data to Deepgram
        try {
          const audioBuffer = Buffer.from(data.audio, 'base64');
          deepgramLive.send(audioBuffer);
        } catch (error) {
          console.error('Error sending audio to Deepgram:', error);
          ws.send(JSON.stringify({ type: 'error', message: 'Error processing audio' }));
        }
      } else if (data.type === 'stop' && deepgramLive) {
        // Close Deepgram connection
        console.log('Stopping transcription...');
        deepgramLive.finish();
        deepgramLive = null;
        ws.send(JSON.stringify({ type: 'status', message: 'stopped' }));
      }
    } catch (error) {
      console.error('Error processing message:', error);
      ws.send(JSON.stringify({ type: 'error', message: error.message }));
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    if (deepgramLive) {
      deepgramLive.finish();
    }
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`WebSocket endpoint: ws://localhost:${PORT}/listen`);
  if (!process.env.DEEPGRAM_API_KEY) {
    console.warn('WARNING: DEEPGRAM_API_KEY environment variable not set!');
  }
});

