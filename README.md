# Friday

Friday is an Android agent that runs Sir's phone. She reads the screen and taps, types and swipes through Android's accessibility service. She talks to **Jarvis**, the assistant on Sir's laptop, over a private bus. Without a network she can still run on a model downloaded to the phone.

She is built for one owner, one phone (an OPPO F21s Pro on ColorOS) and one laptop, joined over Tailscale. Nothing here is a hosted service.

## What she does

- **Drives apps.** Friday works in an observe → think → act loop: she reads the accessibility tree, the model picks the next action, and she taps, types, scrolls, swipes, presses keys or takes a screenshot. A task is capped at the step limit set in Settings. Steps that worked are remembered as skills and replayed.
- **Asks before acting.** Reading the screen and opening apps happen freely. Seven kinds of act always need Sir's **yes** on the phone:
  - sending or posting
  - calling
  - paying
  - deleting
  - changing a setting
  - installing
  - restarting, powering off or signing out

  Paying, deleting and power acts also need his **fingerprint or screen lock** after the yes. Without a screen lock they are refused. The rules are in `lib/services/risk_gate.dart` and `risk_approval.dart`.
- **Talks to Jarvis both ways.**
  - Jarvis can ask Friday for something, such as the battery level or to open an app. Anything that counts as an act still goes through Sir's approval on the phone; a refusal reaches Jarvis as "declined by Sir".
  - In the middle of a task, Friday can ask Jarvis (`ask_jarvis`) about mail, the calendar, files or the laptop, up to twice per task. His answer reaches her as data, not as instructions.
- **Knows Jarvis, and is known by him.** Each builds a profile of itself from its own code and state and sends it to the other. Friday posts hers whenever she connects and whenever it changes, and she keeps Jarvis's in her system prompt.
- **Runs offline.** Friday can download a GGUF model from the catalogue and answer with it through [llamadart](https://pub.dev/packages/llamadart) (llama.cpp). When the laptop cannot be reached, she switches to it on her own and says she is in offline mode.

## The brain

| Provider | When it is used |
|---|---|
| **Jarvis laptop (FreeLLMAPI)** | Default. Requests go through the laptop's phone server, so the API key never leaves the laptop. |
| **On-phone model** | Takes over when the laptop is unreachable or the server fails. A refused key does not trigger it, and neither does a request that includes an image. |
| Other OpenAI-compatible providers | Can still be chosen in Settings. Their keys are kept in Android Keystore-backed secure storage. |

### On-phone models

Choose them in **Settings → On-phone models**. Every file comes from Hugging Face and is checked against a pinned SHA-256 hash.

| Model | Download |
|---|---|
| Qwen 2.5 0.5B | 0.49 GB |
| Gemma 3 1B | 0.81 GB |
| Llama 3.2 1B | 0.81 GB |
| Qwen 3 1.7B | 1.11 GB |
| Qwen 2.5 1.5B | 1.12 GB |
| Llama 3.2 3B | 2.02 GB |
| Qwen 3 4B Instruct | 2.50 GB |

Download behaviour:
- An interrupted download resumes where it stopped.
- A file that fails its hash is deleted.
- Friday checks that there is enough free space before starting.
- Downloads use Wi-Fi only unless that setting is turned off.

A 1B model is fine for chat and simple commands, but weak at driving apps. Long conversations are trimmed from the oldest turn so they fit the model's context.

## The bus

```
 Phone (Friday)                                   Laptop (Jarvis)
 ┌──────────────────────────┐   HTTPS over       ┌───────────────────────────────┐
 │ BusService               │   Tailscale only   │ phone/server.py   /api/bus/*  │
 │  GET  /api/bus/events  ◄─┼────────────────────┤  guard: tailnet login +       │
 │  POST /api/bus/send   ───┼───────────────────►│         Friday's own token    │
 │  POST /api/bus/ack       │                    │  backtalk ◄─► Jarvis          │
 │  POST /api/bus/status    │                    │  ask_friday / friday_status / │
 │  POST /api/bus/friday-profile                 │  friday_profile tools         │
 │  GET  /api/bus/profile   │                    │                               │
 │  /api/bus/llm  ──────────┼───────────────────►│  proxy → FreeLLMAPI           │
 └──────────────────────────┘                    └───────────────────────────────┘
```

- **Jarvis → Friday:** Friday holds a server-sent-events stream open from a foreground service, so the phone never listens on a port and no Firebase is involved.
- **Friday → Jarvis:** plain POSTs. Messages that cannot be sent wait in a local outbox until the phone is back online.
- **Delivery:** every message has an id, a time-to-live and a hop count, and is delivered at least once with duplicates dropped. A reply never starts a new request, so the two cannot loop.
- **Off switches:**
  - the **Jarvis Link** toggle in Friday;
  - revoking her token on the laptop, which is separate from the phone web app's token.
- **Log:** the laptop records one line per message, each way, in `~/my-agent/logs/friday-bus.log`: delivered, refused, dropped as a resend, or expired unsent. A late reply, one that arrives after Jarvis has stopped waiting, is passed to him as a message from Friday. Friday keeps no log of her own yet.

## Install

1. Download `friday-<version>.apk` from [Releases](https://github.com/Dhiraj0192/Friday/releases) and install it. It is arm64 only, signed with Friday's own release key.
2. Turn on Friday's accessibility service. On Android 13 and later a sideloaded app's accessibility switch is greyed out as a "restricted setting". To allow it:
   1. Tap the greyed-out switch once.
   2. Go to **App info → Friday → ⋮ → Allow restricted settings**.
   3. Turn the switch on.
3. Grant notifications and microphone access. On ColorOS, also turn on **auto launch** and **allow background activity** for Friday, or the system will stop her in the background.
4. Have Tailscale running on the phone, in the same tailnet as the laptop.
5. To pair:
   1. On the laptop, run `server.py pair-friday` from the Jarvis phone server. It prints a `friday1:…` code and a QR code of it.
   2. Copy the code onto the phone; scanning the QR with the camera is the easiest way.
   3. Paste it into **Settings → Jarvis Link**.

   The code contains a secret token, so keep it out of chats and notes.

## Build

The CI workflow is `.github/workflows/build.yml`, pinned to Flutter 3.44.9 and Java 17.

- On every push to `master` and every pull request, it runs `flutter analyze` and `flutter test`, and builds the arm64 release APK as a workflow artifact.
- Pushing a tag `v*` publishes the APK as a GitHub Release.
- The release key comes from the repository secrets `FRIDAY_KEYSTORE_B64` and `FRIDAY_KEYSTORE_PASSWORD`. Without them, the build falls back to the debug key and prints a warning.

To build locally:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

## Where things are

| Path | What it does |
|---|---|
| `lib/services/task_executor.dart` | The agent loop, including `ask_jarvis` |
| `lib/services/risk_gate.dart`, `risk_approval.dart` | Sorts reads from acts, then asks for approval and the fingerprint |
| `lib/services/bus_service.dart` | The Jarvis link: stream, outbox, acks, pairing |
| `lib/services/brain_router.dart`, `on_device_llm.dart` | Chooses the laptop or the phone model; runs llama.cpp |
| `lib/services/model_store.dart` | Model catalogue, downloads, checksums |
| `lib/services/friday_profile.dart` | Friday's self-description |
| `lib/services/ai_service.dart` | Prompts and providers |
| `android/app/src/main/kotlin/.../AgentAccessibilityService.kt` | Reads the screen and performs gestures |
| `test/` | Tests for the risk gate, bus, on-device models, storage paths and secure storage, plus a check that Telegram is gone |

## Known limits

- **Speech is not offline yet.** Listening uses Google's recogniser, and speaking defaults to Microsoft Edge TTS, with Android's own TTS as the fallback.
- **Several inherited features are demos rather than working features:**
  - the smart-home devices
  - the network-audit numbers
  - the vision fallback text
  - the co-pilot's status line
  - Code Black's "biometrics"
  - Sentry's "coordinates"

  Friday's self-profile leaves them out so that neither agent relies on them.
- **Approvals are on screen only.** Friday cannot be approved by voice while she is in the middle of a task.
- **Apps can block her.** An app that sets `FLAG_SECURE` (most banking apps) keeps its screen hidden from accessibility.

## Licence

MIT. Friday began as a fork of [AbuZar-Ansarii/Jarvis](https://github.com/AbuZar-Ansarii/Jarvis), and its copyright notice is kept in [LICENSE](LICENSE). The bus, the risk gate, the on-phone models, the hardening and the removal of Telegram are new in this fork.
