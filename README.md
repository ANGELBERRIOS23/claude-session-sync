# Claude Session Sync

<p align="center">
  <img src="icon_1024.png" width="128" alt="Claude Session Sync icon">
</p>

<p align="center">
  <strong>Sync your Claude Code sessions across accounts.</strong><br>
  <em>Never lose your session history when switching between Personal and Bedrock accounts.</em>
</p>

<p align="center">
  <a href="#the-problem--el-problema">Problem</a> •
  <a href="#the-solution--la-solución">Solution</a> •
  <a href="#macos">macOS</a> •
  <a href="#windows">Windows</a> •
  <a href="#how-it-works--cómo-funciona">How it works</a>
</p>

---

## The Problem / El Problema

**EN:** Claude Desktop stores Code session indexes in separate directories per account. When you switch between Personal and Bedrock (or between multiple personal accounts), your sessions disappear from the sidebar. The actual conversation transcripts are shared on disk -- but the index files are siloed per account.

**ES:** Claude Desktop guarda los indices de sesiones de Code en directorios separados por cuenta. Al cambiar entre Personal y Bedrock (o entre varias cuentas personales), las sesiones desaparecen del sidebar. Las transcripciones reales se comparten en disco, pero los archivos de indice estan aislados por cuenta.

**Related issues / Issues relacionados:**
- [#92825](https://github.com/anthropics/claude-code/issues/92825) -- Sessions lost after account switch
- [#92813](https://github.com/anthropics/claude-code/issues/92813) -- Account switch pauses running tasks
- [#90647](https://github.com/anthropics/claude-code/issues/90647) -- Account switch discards MCP OAuth grants
- [#92517](https://github.com/anthropics/claude-code/issues/92517) -- Feature request: cross-account session sharing

## The Solution / La Solución

**EN:** This tool copies the lightweight session index JSON files (~1-5KB each) between account directories, making all your sessions visible regardless of which account is active. It does NOT copy conversations or credentials -- just the metadata that tells the sidebar "this session exists."

**ES:** Esta herramienta copia los archivos JSON de indice de sesion (~1-5KB cada uno) entre los directorios de cuentas, haciendo que todas tus sesiones sean visibles sin importar que cuenta este activa. NO copia conversaciones ni credenciales, solo los metadatos que le dicen al sidebar "esta sesion existe."

<p align="center">
  <img src="screenshots/app-macos.png" width="520" alt="Claude Session Sync - macOS menubar app">
</p>

## macOS

Native SwiftUI menubar app. No background processes, no Electron, just a lightweight binary.

App nativa de SwiftUI en la barra de menu. Sin procesos en segundo plano, sin Electron, solo un binario ligero.

### Features / Funcionalidades

| Feature | Description |
|---------|-------------|
| Session list | View all sessions from all accounts grouped by source |
| Selective sync | Choose which sessions to sync with checkboxes |
| Sync all | One-click bidirectional sync |
| Unsync | Remove a synced session from the other account |
| Restart Claude | Restart Claude Desktop so synced sessions appear immediately |
| Launch at login | Toggle to start automatically when you log in |
| EN/ES toggle | Switch between English and Spanish in-app |
| Multi-account | Syncs between Claude (Personal), Claude-3p (Bedrock), and multiple accounts within the same app |

### Install / Instalar

**Requirements:** macOS 14+ and Swift 6.0+ (comes with Xcode Command Line Tools).

```bash
git clone https://github.com/ANGELBERRIOS23/claude-session-sync.git
cd claude-session-sync
./install.sh
```

This builds the binary and creates `Claude Session Sync.app` in `/Applications/`. Find it in Launchpad or Spotlight.

### Build manually / Compilar manualmente

```bash
swift build -c release
.build/release/ClaudeSessionSync
```

## Windows

PowerShell script with an interactive menu. No installation required.

Script de PowerShell con menu interactivo. No requiere instalacion.

### Run / Ejecutar

```powershell
powershell -ExecutionPolicy Bypass -File windows\claude-session-sync.ps1
```

### Flags

```powershell
.\claude-session-sync.ps1 -List      # List all sessions / Listar sesiones
.\claude-session-sync.ps1 -SyncAll   # Sync everything / Sincronizar todo
.\claude-session-sync.ps1 -Help      # Show help / Mostrar ayuda
```

### Interactive menu / Menu interactivo

```
--- Claude Session Sync ---
1. List sessions
2. Sync all sessions
3. Restart Claude (Personal)
4. Restart Claude-3p (Bedrock)
5. Quit
```

## How it works / Cómo funciona

### Session storage / Almacenamiento de sesiones

| Platform | App | Path |
|----------|-----|------|
| macOS | Claude (Personal) | `~/Library/Application Support/Claude/claude-code-sessions/{accountUUID}/{orgUUID}/` |
| macOS | Claude-3p (Bedrock) | `~/Library/Application Support/Claude-3p/claude-code-sessions/{accountUUID}/{orgUUID}/` |
| Windows | Claude (Personal) | `%APPDATA%\Claude\claude-code-sessions\{accountUUID}\{orgUUID}\` |
| Windows | Claude-3p (Bedrock) | `%APPDATA%\Claude-3p\claude-code-sessions\{accountUUID}\{orgUUID}\` |

### What gets copied / Qué se copia

**EN:** Only `local_*.json` index files. These are small (~1-5KB) and contain session metadata: title, model used, working directory, and timestamps. No conversation content. No credentials. No API keys.

**ES:** Solo los archivos de indice `local_*.json`. Son pequenos (~1-5KB) y contienen metadatos de sesion: titulo, modelo usado, directorio de trabajo, y timestamps. Sin contenido de conversaciones. Sin credenciales. Sin API keys.

The actual conversation transcripts live in `~/.claude/projects/` and are already shared across all accounts.

### Important note / Nota importante

Synced sessions are **read-only** in terms of continuing the conversation -- you can see and read them, but generating new responses requires the original account's API credentials. The session appears in the sidebar and you can review the full transcript.

Las sesiones sincronizadas son de **solo lectura** en terminos de continuar la conversacion -- puedes verlas y leerlas, pero generar nuevas respuestas requiere las credenciales API de la cuenta original. La sesion aparece en el sidebar y puedes revisar la transcripcion completa.

## FAQ

**Q: Is this safe? / Es seguro?**
A: Yes. It only copies tiny JSON metadata files. No passwords, tokens, or conversation data is touched.

**Q: Do I need to restart Claude after syncing?**
A: Usually yes. Use the "Restart Claude" button in the app, or press Cmd+Q and reopen.

**Q: Will this break anything? / Puede romper algo?**
A: No. The worst case is a session appearing that you can't continue (because it belongs to another account). You can always unsync it.

**Q: Does it work with multiple personal accounts?**
A: Yes. It scans all account UUID directories and syncs between all of them.

## License

MIT

## Contributing

PRs welcome. If you find a bug or want a feature, open an issue.
