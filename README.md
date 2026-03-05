# MultiSpeakerApp

Real-Time Multi-Speaker Transcription App — macOS prototype, iOS-portable.

## Architecture

### Data Flow
```
Mic
 │
 ▼
AudioCaptureEngine
 │  (16kHz, PCM Int16, mono, ~100ms chunks)
 ├──────────────────────────────────┐
 ▼                                  ▼
StreamingClient                AudioFileWriter
 │  (binary WebSocket frames)       │  (accumulates .wav)
 ▼                                  │
AssemblyAI v3/ws                   │  ← on recording stop
 │  (Turn JSON — raw text)          ▼
 ▼                           DiarizationClient
TranscriptStore ◄──── TranscriptMerger ◄──── LeMURClient
 │                                               │
 ▼                                       async API: upload
TranscriptView (SwiftUI)                 → diarize → name-guess
```

### Speaker Identification Strategy
AssemblyAI's real-time WebSocket API does not support speaker diarization.
The app uses a **hybrid model**:

1. **During recording** — raw transcript turns appear in real time via the
   streaming WebSocket. Turns are labelled "Turn 1", "Turn 2", etc.
2. **After recording stops** — the buffered audio is submitted to AssemblyAI's
   async API with `speaker_labels: true`. Results arrive in ~15–30 s.
3. **Name guessing** — the diarized transcript is passed to AssemblyAI's
   LeMUR endpoint with a prompt asking it to infer real speaker names from
   conversational context (direct address, self-introduction, etc.).
4. **Rename UI** — LeMUR suggestions are shown as pre-filled but editable
   labels. The user confirms or corrects them before exporting.

### Implementation Phases
| Phase | Feature |
|-------|---------|
| (a) | Audio capture — AVAudioEngine → 16 kHz PCM Int16 chunks |
| (b) | WebSocket streaming — live transcript turns |
| (c) | Transcript UI — scrolling, colour-coded speaker rows |
| (d) | Diarization + LeMUR name guessing + speaker renaming |
| (e) | Export as plain-text file |

## Setup
See `SETUP.md` for Xcode project configuration instructions.

## API Key
Copy `.env.example` to `.env` and add your AssemblyAI API key.
The `.env` file is gitignored and must be added to the Xcode target's
"Copy Bundle Resources" build phase.
