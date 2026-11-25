# Local-Harness User Manual

> **This program does not include any GGUF model weights.** You must download and import a model yourself.

Local-Harness is a graphical harness for llama.cpp. It puts model loading, parameter settings and multi-turn chat into a single window, so no terminal commands are needed.

---

## 1. Install and launch

1. Download the release (portable zip or single-file exe) and extract it to any folder (non-ASCII paths are fine).
2. Double-click `local-harness.exe`.
3. On first start the model loads; a loading indicator appears in the centre for a few seconds.
4. Type your question in the box at the bottom and press Enter.

Portable folder layout:

```
local-harness.exe      main program
_internal\             runtime libraries (do not rename or delete)
llama\                 llama.cpp binaries (llama-cli.exe and its DLLs)
model\                 your own .gguf models
chats\                 chat history (created on first run)
config.json            UI and parameter settings (created on first run)
```

## 2. Prepare a model

No model is bundled. Download a GGUF file (name ends with `.gguf`) — for example a quantised build from Hugging Face or ModelScope.

Two ways to import:

- **Copy into the folder**: put the `.gguf` file into `model\`, restart the program, and it appears in the model drop-down.
- **Import in the UI**: click **Import** at the top and pick a folder that contains models; the path is remembered.

Notes:

- For split models only the first part (`xxx-00001-of-00002.gguf`) is needed; keep the other parts in the same folder.
- mmproj files, vision projectors, embedding and reranker models, and files smaller than 20 MB are ignored automatically.
- Model weights are licensed by their publishers (Qwen models are Apache-2.0, for example). Follow the respective licence.

Choosing a model by memory:

| Model size | File size (reference) | Suggested RAM |
| --- | --- | --- |
| 0.4B – 1B | 300MB – 900MB | 4GB+ |
| 1.5B – 2B | 1GB – 2GB | 8GB |
| 3B – 4B | 2GB – 3GB | 16GB |

## 3. Interface

- **Top bar**: model drop-down, Import button, parameters (temperature / context / reply limit), thinking mode switch, About, Settings, theme toggle.
- **Sidebar**: conversation list. Hover to reveal delete, right-click to rename or delete.
- **Centre**: message area. Answers stream token by token.
- **Bottom**: input box and Send button; while generating it becomes **Stop**.
- **Status bar**: current model, context usage and the model's native limit on the left; token share of this chat on the right.

## 4. Parameters

| Parameter | Range | Notes |
| --- | --- | --- |
| Temperature | 0 – 2 | Lower is more deterministic, higher is more creative. Code 0.2–0.6, general Q&A 0.7, writing 0.9–1.2 |
| Context | 512 – model native limit | Tokens kept for one conversation. The slider maximum comes from the model itself; the status bar shows "native xxxx" |
| Reply limit | 64 – 8192 | Maximum tokens per answer. Increase it if answers get cut off |
| Thinking mode | on / off | For reasoning-capable models (e.g. Qwen3): think first, then answer. The reasoning is not shown in the reply |

Values can be typed directly or changed with the slider. Changes apply immediately and are saved to `config.json`.

## 5. Context compression

Long chats eventually exceed the context window. With automatic compression enabled, once the conversation reaches the trigger threshold, older history is summarised into a single message before the next question, keeping the most recent turns verbatim.

- Where: **Settings → Context compression**.
- Trigger threshold is adjustable in 1024-token steps: **1024 / 2048 / 3072 / 4096**, default **2048**.
- You can choose how many recent turns stay verbatim (default 4).
- Compression starts a temporary model process and takes a few seconds; you cannot send while it runs.
- Turn it off in Settings if you prefer to start a new chat manually when the context is full.

## 6. Keyboard shortcuts

| Key | Action |
| --- | --- |
| Enter | Send |
| Shift + Enter | New line |
| Ctrl + Enter | Send |
| Esc | Stop generating |
| Ctrl + L | Clear input |

## 7. Data and backup

- Conversations are stored in `chats\`, one `.json` per conversation; deleting the file deletes the conversation.
- UI state, parameters and imported model folders live in `config.json`; delete it to reset to defaults.
- The program does not access the network and needs no account; nothing is uploaded.
- Moving to another PC: copy the whole program folder (including `model\`).

## 8. Troubleshooting

**It flashes and exits immediately**
`_internal\` or `llama\` was moved or quarantined by antivirus. Extract a fresh copy of the release.

**It says there is no model file**
`model\` is empty. Put a `.gguf` there, or use Import and pick a folder, then restart.

**My model does not show up**
Make sure it is a `.gguf` file larger than 20 MB, not an mmproj or embedding model. For split models, keep the first part only.

**Answers are slow**
Use a smaller model; set the thread count to your CPU core count in Settings; plug in the laptop and disable power saving.

**Answers get cut off**
Raise the reply limit (e.g. 2048).

**Slow after a long chat, or a context warning**
Automatic compression is on by default; check the threshold in Settings, or start a new conversation.

**Model names look like "Qwen3 0.6B · Q8_0"**
That is expected: the name and quantisation are read from the GGUF metadata.

## 9. Licence

This project is released under GPLv3. You may distribute packaged binaries, but whenever you distribute the program (source or binary) you must also provide the complete corresponding source code, and modified versions must remain open source under the same licence.

Model weights are not part of this project and follow their publishers' licences.
