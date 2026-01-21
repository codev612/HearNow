import express from 'express';
import { WebSocketServer } from 'ws';
import { createClient, LiveTranscriptionEvents } from '@deepgram/sdk';
import OpenAI from 'openai';
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

const openai = process.env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

// AI response endpoint
// Accepts a short transcript history and returns a single assistant reply.
app.post('/ai/respond', async (req, res) => {
  try {
    if (!openai) {
      return res.status(500).json({
        error: 'OpenAI API key not configured. Set OPENAI_API_KEY in backend .env',
      });
    }

    const { turns, mode, question } = req.body ?? {};
    if (!Array.isArray(turns) || turns.length === 0) {
      return res.status(400).json({ error: 'Missing turns[]' });
    }

    const questionText = typeof question === 'string' ? question.trim() : '';
    if (questionText.length > 800) {
      return res.status(400).json({ error: 'Question too long (max 800 chars)' });
    }

    // Basic size limits to avoid accidental huge payloads.
    if (turns.length > 50) {
      return res.status(400).json({ error: 'Too many turns (max 50)' });
    }

    const normalized = turns
      .map((t) => ({
        source: String(t?.source ?? 'unknown'),
        text: String(t?.text ?? '').trim(),
      }))
      .filter((t) => t.text.length > 0);

    if (normalized.length === 0) {
      return res.status(400).json({ error: 'All turns were empty' });
    }

    const totalChars = normalized.reduce((sum, t) => sum + t.text.length, 0);
    if (totalChars > 12000) {
      return res.status(400).json({ error: 'Turns too long (max 12000 chars total)' });
    }

    const requestMode = ['summary', 'insights', 'questions'].includes(mode) ? mode : 'reply';

    let systemPrompt;
    let userPrompt;
    
    const historyText = normalized
      .map((t) => {
        const label = t.source.toLowerCase() === 'mic' ? 'MIC' : t.source.toLowerCase() === 'system' ? 'SYSTEM' : t.source.toUpperCase();
        return `${label}: ${t.text}`;
      })
      .join('\n');

    switch (requestMode) {
      case 'summary':
        systemPrompt = 'You are HearNow, an interview assistant. Summarize the interview conversation so far into concise bullet points. Include key topics discussed, candidate responses, and any notable points. If action items or follow-ups exist, list them separately.';
        userPrompt = `Interview transcript:\n${historyText}\n\nProvide a concise summary of this interview.`;
        break;
      case 'insights':
        systemPrompt = 'You are HearNow, an interview assistant. Analyze the interview transcript and provide key insights about the candidate. Focus on strengths, areas of concern, communication style, technical knowledge, cultural fit, and overall assessment. Be objective and specific.';
        userPrompt = `Interview transcript:\n${historyText}\n\nProvide key insights about this interview and candidate.`;
        break;
      case 'questions':
        systemPrompt = 'You are HearNow, an interview assistant. Based on the interview transcript so far, suggest 3-5 relevant follow-up questions the interviewer should ask. Consider what has been discussed, what gaps exist, and what would help make a better hiring decision. Format as a numbered list.';
        userPrompt = `Interview transcript:\n${historyText}\n\nSuggest relevant follow-up questions for this interview.`;
        break;
      default: // 'reply'
        systemPrompt = 'You are HearNow, an interview assistant. Reply helpfully and concisely to what was said. If the user asks a question, answer it. If the transcript is incomplete, ask one clarifying question.';
        userPrompt = `Conversation transcript (most recent last):\n${historyText}\n\nUser question (optional): ${questionText || '(none)'}\n\nWrite your assistant reply.`;
        break;
    }

    const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
    const maxTokens = requestMode === 'insights' ? 600 : requestMode === 'questions' ? 300 : 400;

    const completion = await openai.chat.completions.create({
      model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: maxTokens,
      temperature: 0.2,
    });

    const text = completion?.choices?.[0]?.message?.content ?? '';
    return res.json({ text });
  } catch (error) {
    console.error('AI respond error:', error);
    const status = typeof error?.status === 'number' ? error.status : 500;
    const message =
      error?.error?.message ||
      error?.message ||
      'Failed to generate AI response';
    return res.status(status).json({ error: message });
  }
});

// Create HTTP server
const server = createServer(app);

// Create WebSocket servers (we route upgrades manually so multiple WS endpoints
// can coexist safely on the same HTTP server).
const wss = new WebSocketServer({ noServer: true });
const aiWss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;

    if (pathname === '/listen') {
      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
      });
      return;
    }

    if (pathname === '/ai') {
      aiWss.handleUpgrade(req, socket, head, (ws) => {
        aiWss.emit('connection', ws, req);
      });
      return;
    }

    socket.destroy();
  } catch (_) {
    socket.destroy();
  }
});

// Deepgram client
const deepgram = createClient(process.env.DEEPGRAM_API_KEY);

wss.on('connection', (ws) => {
  console.log('Client connected');

  let deepgramMic = null;
  let deepgramSystem = null;

  const startDeepgram = (source) => {
    const live = deepgram.listen.live({
      model: 'nova-3',
      language: 'en',
      smart_format: true,
      punctuate: true,
      interim_results: true,
      encoding: 'linear16',
      sample_rate: 16000,
    });

    live.on(LiveTranscriptionEvents.Open, () => {
      console.log(`Deepgram connection opened (${source})`);
      ws.send(JSON.stringify({ type: 'status', message: `ready:${source}` }));
    });

    live.on(LiveTranscriptionEvents.Transcript, (data) => {
      const transcript = data.channel.alternatives[0]?.transcript;
      if (transcript) {
        const isFinal = data.is_final === true;
        const isInterim = data.is_final === false;
        ws.send(
          JSON.stringify({
            type: 'transcript',
            source,
            text: transcript,
            is_final: isFinal,
            is_interim: isInterim,
            confidence: data.channel.alternatives[0].confidence || 0,
          }),
        );
      }
    });

    live.on(LiveTranscriptionEvents.Error, (error) => {
      console.error(`Deepgram error (${source}):`, error);
      ws.send(
        JSON.stringify({
          type: 'error',
          message: error.message || `Deepgram error (${source})`,
        }),
      );
    });

    live.on(LiveTranscriptionEvents.Close, () => {
      console.log(`Deepgram connection closed (${source})`);
      if (source === 'mic') deepgramMic = null;
      if (source === 'system') deepgramSystem = null;
    });

    return live;
  };

  // Handle incoming messages from client
  ws.on('message', async (message) => {
    try {
      // ws can deliver Buffer; convert to string before JSON.parse.
      const text = typeof message === 'string' ? message : message.toString('utf8');
      let data;
      try {
        data = JSON.parse(text);
      } catch (_) {
        // We only support JSON messages from the Flutter client.
        return;
      }

      console.log('WS /listen message:', data?.type, data?.source ? `source=${data.source}` : '');

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

        // Initialize Deepgram live connections (mic + system)
        console.log('Starting Deepgram connections (mic + system)...');
        
        try {
          if (deepgramMic) {
            deepgramMic.finish();
            deepgramMic = null;
          }
          if (deepgramSystem) {
            deepgramSystem.finish();
            deepgramSystem = null;
          }

          deepgramMic = startDeepgram('mic');
          deepgramSystem = startDeepgram('system');
        } catch (error) {
          console.error('Failed to start Deepgram connection:', error);
          ws.send(JSON.stringify({ type: 'error', message: 'Failed to connect to Deepgram: ' + error.message }));
          deepgramMic = null;
          deepgramSystem = null;
        }

      } else if (data.type === 'audio') {
        const source = data.source === 'system' ? 'system' : 'mic';
        const target = source === 'system' ? deepgramSystem : deepgramMic;
        if (!target) return;

        // Forward audio data to Deepgram (per-source session)
        try {
          const audioBuffer = Buffer.from(data.audio, 'base64');
          target.send(audioBuffer);
        } catch (error) {
          console.error('Error sending audio to Deepgram:', error);
          ws.send(JSON.stringify({ type: 'error', message: 'Error processing audio' }));
        }
      } else if (data.type === 'stop') {
        // Close Deepgram connections
        console.log('Stopping transcription (mic + system)...');
        if (deepgramMic) {
          deepgramMic.finish();
          deepgramMic = null;
        }
        if (deepgramSystem) {
          deepgramSystem.finish();
          deepgramSystem = null;
        }
        ws.send(JSON.stringify({ type: 'status', message: 'stopped' }));
      }
    } catch (error) {
      console.error('Error processing message:', error);
      try {
        ws.send(JSON.stringify({ type: 'error', message: error?.message ?? 'Server error' }));
      } catch (_) {}
    }
  });

  ws.on('close', (code, reason) => {
    console.log('Client disconnected', { code, reason: reason?.toString?.() ?? '' });
    if (deepgramMic) deepgramMic.finish();
    if (deepgramSystem) deepgramSystem.finish();
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

// AI WebSocket server (streams tokens to the client)
aiWss.on('connection', (ws) => {
  console.log('AI client connected');

  // Only allow one in-flight request per socket for simplicity.
  let currentRequestId = null;
  let cancelled = false;

  const send = (obj) => {
    try {
      ws.send(JSON.stringify(obj));
    } catch (_) {}
  };

  ws.on('message', async (message) => {
    try {
      let data;
      try {
        data = JSON.parse(message);
      } catch (_) {
        return;
      }

      if (data?.type === 'ai_cancel') {
        if (typeof data.requestId === 'string' && data.requestId === currentRequestId) {
          cancelled = true;
        }
        return;
      }

      if (data?.type !== 'ai_request') return;

      if (!openai) {
        return send({
          type: 'ai_error',
          requestId: data.requestId ?? null,
          status: 500,
          message: 'OpenAI API key not configured. Set OPENAI_API_KEY in backend .env',
        });
      }

      const requestId = typeof data.requestId === 'string' && data.requestId.length > 0
        ? data.requestId
        : String(Date.now());

      // Cancel any existing request for this socket.
      currentRequestId = requestId;
      cancelled = false;

      const { turns, mode, question } = data ?? {};
      if (!Array.isArray(turns) || turns.length === 0) {
        return send({ type: 'ai_error', requestId, status: 400, message: 'Missing turns[]' });
      }

      const questionText = typeof question === 'string' ? question.trim() : '';
      if (questionText.length > 800) {
        return send({ type: 'ai_error', requestId, status: 400, message: 'Question too long (max 800 chars)' });
      }

      if (turns.length > 50) {
        return send({ type: 'ai_error', requestId, status: 400, message: 'Too many turns (max 50)' });
      }

      const normalized = turns
        .map((t) => ({
          source: String(t?.source ?? 'unknown'),
          text: String(t?.text ?? '').trim(),
        }))
        .filter((t) => t.text.length > 0);

      if (normalized.length === 0) {
        return send({ type: 'ai_error', requestId, status: 400, message: 'All turns were empty' });
      }

      const totalChars = normalized.reduce((sum, t) => sum + t.text.length, 0);
      if (totalChars > 12000) {
        return send({ type: 'ai_error', requestId, status: 400, message: 'Turns too long (max 12000 chars total)' });
      }

      const requestMode = ['summary', 'insights', 'questions'].includes(mode) ? mode : 'reply';
      let systemPrompt;
      let userPrompt;

      const historyText = normalized
        .map((t) => {
          const label =
            t.source.toLowerCase() === 'mic'
              ? 'MIC'
              : t.source.toLowerCase() === 'system'
                ? 'SYSTEM'
                : t.source.toUpperCase();
          return `${label}: ${t.text}`;
        })
        .join('\n');

      switch (requestMode) {
        case 'summary':
          systemPrompt =
            'You are HearNow, an interview assistant. Summarize the interview conversation so far into concise bullet points. Include key topics discussed, candidate responses, and any notable points. If action items or follow-ups exist, list them separately.';
          userPrompt = `Interview transcript:\n${historyText}\n\nProvide a concise summary of this interview.`;
          break;
        case 'insights':
          systemPrompt =
            'You are HearNow, an interview assistant. Analyze the interview transcript and provide key insights about the candidate. Focus on strengths, areas of concern, communication style, technical knowledge, cultural fit, and overall assessment. Be objective and specific.';
          userPrompt = `Interview transcript:\n${historyText}\n\nProvide key insights about this interview and candidate.`;
          break;
        case 'questions':
          systemPrompt =
            'You are HearNow, an interview assistant. Based on the interview transcript so far, suggest 3-5 relevant follow-up questions the interviewer should ask. Consider what has been discussed, what gaps exist, and what would help make a better hiring decision. Format as a numbered list.';
          userPrompt = `Interview transcript:\n${historyText}\n\nSuggest relevant follow-up questions for this interview.`;
          break;
        default:
          systemPrompt =
            'You are HearNow, an interview assistant. Reply helpfully and concisely to what was said. If the user asks a question, answer it. If the transcript is incomplete, ask one clarifying question.';
          userPrompt = `Conversation transcript (most recent last):\n${historyText}\n\nUser question (optional): ${questionText || '(none)'}\n\nWrite your assistant reply.`;
          break;
      }

      const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
      const maxTokens = requestMode === 'insights' ? 600 : requestMode === 'questions' ? 300 : 400;

      send({ type: 'ai_start', requestId });

      let fullText = '';
      try {
        const stream = await openai.chat.completions.create({
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          max_tokens: maxTokens,
          temperature: 0.2,
          stream: true,
        });

        for await (const part of stream) {
          if (cancelled || currentRequestId !== requestId) break;
          const delta = part?.choices?.[0]?.delta?.content ?? '';
          if (delta) {
            fullText += delta;
            send({ type: 'ai_delta', requestId, delta });
          }
        }

        if (cancelled || currentRequestId !== requestId) {
          return send({ type: 'ai_done', requestId, cancelled: true, text: fullText });
        }

        return send({ type: 'ai_done', requestId, cancelled: false, text: fullText });
      } catch (error) {
        console.error('AI WS error:', error);
        const status = typeof error?.status === 'number' ? error.status : 500;
        const msg = error?.error?.message || error?.message || 'Failed to generate AI response';
        return send({ type: 'ai_error', requestId, status, message: msg });
      }
    } catch (error) {
      console.error('AI WS message error:', error);
      try {
        ws.send(JSON.stringify({ type: 'ai_error', requestId: null, status: 500, message: 'Internal error' }));
      } catch (_) {}
    }
  });

  ws.on('close', () => {
    console.log('AI client disconnected');
  });

  ws.on('error', (error) => {
    console.error('AI WebSocket error:', error);
  });
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`WebSocket endpoint: ws://localhost:${PORT}/listen`);
  console.log(`AI WebSocket endpoint: ws://localhost:${PORT}/ai`);
  if (!process.env.DEEPGRAM_API_KEY) {
    console.warn('WARNING: DEEPGRAM_API_KEY environment variable not set!');
  }
  if (!process.env.OPENAI_API_KEY) {
    console.warn('WARNING: OPENAI_API_KEY environment variable not set!');
  }
});

