# Xcode Project Setup — MultiSpeakerApp

Follow these steps once to create the Xcode project and wire it to the source
files in this repo. You only need to do this once.

---

## 1. Create the Xcode project

1. Open Xcode → **File › New › Project**
2. Choose **macOS › App**
3. Fill in:
   | Field | Value |
   |---|---|
   | Product Name | `MultiSpeakerApp` |
   | Team | Your Apple ID / team |
   | Organization Identifier | anything (e.g. `com.yourname`) |
   | Bundle Identifier | `com.yourname.MultiSpeakerApp` |
   | Interface | **SwiftUI** |
   | Language | **Swift** |
4. **Save into** the repo root: `ClaudeCode1/MultiSpeakerApp/`
   Xcode will create `MultiSpeakerApp.xcodeproj` alongside the existing
   `MultiSpeakerApp/` source folder.

---

## 2. Replace the generated source files

Xcode creates a default `ContentView.swift` and app entry point. Delete them
and add the files from this repo instead:

1. In the Project Navigator, select the `MultiSpeakerApp` group (yellow folder).
2. Delete `ContentView.swift` and `MultiSpeakerAppApp.swift` — choose
   **Move to Trash**.
3. Right-click the group → **Add Files to "MultiSpeakerApp"…**
4. Navigate to `MultiSpeakerApp/` in the repo and add **all subfolders**:
   - `App/` (contains `MultiSpeakerAppApp.swift`, `AppState.swift`)
   - `Audio/` (contains `AudioCaptureEngine.swift`, `AudioFileWriter.swift`)
   - `Models/` (contains `AppConfig.swift`)
   - `Views/` (contains `ContentView.swift`)

   Make sure **"Add to target: MultiSpeakerApp"** is checked, and
   **"Create groups"** is selected (not folder references).

---

## 3. Configure the deployment target

1. Select the project in the navigator → select the **MultiSpeakerApp** target.
2. Under **General › Deployment Info**, set:
   - **macOS 14.0**

---

## 4. Add entitlements

1. Select the target → **Signing & Capabilities** tab.
2. Click **+ Capability** and add:
   - **App Sandbox**
   - Under App Sandbox, tick **Audio Input** and **Outgoing Connections (Client)**
3. Xcode will generate a `.entitlements` file. Replace its contents with the
   one already in the repo at `MultiSpeakerApp/MultiSpeakerApp.entitlements`,
   or verify the keys match:
   ```
   com.apple.security.app-sandbox        = YES
   com.apple.security.device.audio-input = YES
   com.apple.security.network.client     = YES
   ```

---

## 5. Add NSMicrophoneUsageDescription to Info.plist

In Xcode 15+, Info.plist keys are set in the target's **Info** tab:

1. Select the target → **Info** tab.
2. Hover over any row → click **+** to add a new key.
3. Add:
   | Key | Value |
   |---|---|
   | Privacy - Microphone Usage Description | `MultiSpeakerApp needs the microphone to transcribe conversations.` |

---

## 6. Add the .env file to the bundle

1. Copy `.env.example` to `.env` in the repo root:
   ```
   cp .env.example .env
   ```
2. Edit `.env` and paste your AssemblyAI API key.
3. In Xcode, drag `.env` into the Project Navigator under the
   `MultiSpeakerApp` group.
4. When prompted, make sure **"Add to target: MultiSpeakerApp"** is checked.
5. Verify it appears in: Target → **Build Phases › Copy Bundle Resources**.

> **.env is gitignored** — it will never be committed.

---

## 7. Build and run (Phase a verification)

Press **⌘R**. When macOS asks for microphone permission, click **OK**.

Click **Start Recording** in the app window, speak a few words, then click
**Stop Recording**. You should see output in the Xcode console like:

```
[AppState] API key loaded ✓
[AppState] Recording started
[Audio] chunk 1 — 3200 bytes (1600 samples) | total: 0.1s
[Audio] chunk 2 — 3200 bytes (1600 samples) | total: 0.2s
...
[AppState] Recording stopped — 30 chunks, 3.0s of audio
```

If you see this, Phase (a) is complete. ✓
