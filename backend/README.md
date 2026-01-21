# HearNow Backend

Node.js backend server for the HearNow speech-to-text application using Deepgram Nova 3 and WebSocket.

## Prerequisites

- Node.js (v18 or higher)
- Deepgram API key (get one at https://deepgram.com)

## Setup

1. Install dependencies:
```bash
npm install
```

2. Create a `.env` file from the example:
```bash
cp .env.example .env
```

3. Add your Deepgram API key to the `.env` file:
```
DEEPGRAM_API_KEY=your_actual_api_key_here
```

4. (Optional) Enable AI responses by adding your OpenAI API key:
```
OPENAI_API_KEY=your_actual_api_key_here
# Optional
# OPENAI_MODEL=gpt-4o-mini
```

## Running the Server

Development mode (with auto-reload):
```bash
npm run dev
```

Production mode:
```bash
npm start
```

The server will start on port 3000 by default.

## API Endpoints

- **GET /health** - Health check endpoint
- **WebSocket /listen** - WebSocket endpoint for audio streaming
- **POST /ai/respond** - Generate an AI reply from transcript turns

### POST /ai/respond

Request body:
```json
{
  "mode": "reply",
  "turns": [
    {"source": "mic", "text": "Hello"},
    {"source": "system", "text": "Hi there"}
  ]
}
```

Response:
```json
{ "text": "..." }
```

## WebSocket Protocol

### Client to Server Messages

1. Start streaming:
```json
{
  "type": "start"
}
```

2. Send audio data:
```json
{
  "type": "audio",
  "audio": "<base64-encoded-audio>"
}
```

3. Stop streaming:
```json
{
  "type": "stop"
}
```

### Server to Client Messages

1. Status updates:
```json
{
  "type": "status",
  "message": "ready|stopped"
}
```

2. Transcription results:
```json
{
  "type": "transcript",
  "text": "transcribed text",
  "is_final": true|false,
  "confidence": 0.95
}
```

3. Error messages:
```json
{
  "type": "error",
  "message": "error description"
}
```
