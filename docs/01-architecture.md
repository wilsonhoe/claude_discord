# System Architecture

> Complete technical architecture of the Claude Discord multi-agent system.

---

## 1. High-Level Architecture

```
+-------------------------------------------------------------+
|                       DISCORD PLATFORM                       |
|  +------------------+  +------------------+  +----------+  |
|  | #command_center  |  | Thread: task-123 |  | DM User  |  |
|  +------------------+  +------------------+  +----------+  |
+-------------------------------------------------------------+
                           |
                           v
+-------------------------------------------------------------+
|                  DISCORD GATEWAY (WebSocket)                 |
|              Events: MESSAGE_CREATE, THREAD_CREATE           |
+-------------------------------------------------------------+
                           |
           +---------------+---------------+
           |                               |
           v                               v
+------------------------+      +------------------------+
| discord-claude-code-bot|      | MCP Discord Plugin     |
| (Standalone Node.js)   |      | (In-process tools)     |
| - Listens to gateway   |      | - mcp_discord_reply    |
| - Spawns claude -p     |      | - mcp_discord_fetch    |
| - Auto-responds        |      | - Passive / no auto    |
+------------------------+      +------------------------+
           |
           v
+-------------------------------------------------------------+
|                 THREAD DATABASE (SQLite)                     |
|  Table: threads                                             |
|  Columns: threadId, sessionId, cwd, model, createdAt, ...   |
|  - Maps Discord thread → Claude session UUID                 |
|  - Auto-cleans stale mappings on startup                     |
|  - Per-agent isolation: claude-threads.db, lisa-threads.db  |
+-------------------------------------------------------------+
                           |
           +---------------+---------------+
           |                               |
           v                               v
+------------------------+      +------------------------+
| Claude Code CLI        |      | OpenClaw Agents        |
| - Executed via `claude |      | - Lisa (executor)      |
|   -p --resume <uuid>`  |      | - Nyx (growth)         |
| - Working dir: project |      | - Kael (executor)      |
|   folder               |      | - William (coder)      |
| - Writes bridge files  |      |                        |
+------------------------+      +------------------------+
           |
           v
+-------------------------------------------------------------+
|                    COORDINATION LAYER                        |
|  +------------------+  +------------------+  +----------+    |
|  | BRIDGE_LISA.md   |  | Telegram INBOX   |  | GitHub   |  |
|  | (file bridge)    |  | (message queue)  |  | LiveChat |  |
|  +------------------+  +------------------+  +----------+  |
+-------------------------------------------------------------+
```

---

## 2. Component Details

### 2.1 discord-claude-code-bot (User-Facing Bot)

**Purpose:** The primary interface between Discord users and Claude Code CLI.

**Responsibilities:**
- Listen to Discord gateway events (messages, thread creation)
- Filter for @mentions and thread replies
- Maintain thread-to-session mapping in SQLite
- Spawn `claude -p --resume <sessionId>` subprocesses
- Send thinking indicators and final responses back to Discord
- Auto-detect and cleanup stale session mappings

**Key Files:**
- `src/index.ts` — Main bot logic, event handlers, message processing
- `src/threads.ts` — SQLite database operations, session mapping
- `src/commands.ts` — Slash command definitions (/help, /new, /model, etc.)
- `threads.db` — SQLite database with WAL mode

**Environment Variables:**
```bash
DISCORD_BOT_TOKEN=<token>          # Discord bot application token
CLAUDE_HOME=/home/user/.claude     # Claude Code config directory
THREADS_DB_PATH=threads.db         # SQLite file path (per-agent override)
AGENT_SYSTEM_PROMPT=<prompt>       # Agent identity override
```

### 2.2 MCP Discord Plugin (In-Process Tools)

**Purpose:** Provides Discord tools to the *current* Claude session (not auto-response).

**Responsibilities:**
- Expose `mcp_discord_reply`, `mcp_discord_fetch_messages`, `mcp_discord_react`
- Only works when Claude session is actively running
- Does NOT spawn new processes or auto-respond

**Key Difference:**
- The MCP plugin is for Claude to *use* Discord as a tool
- The standalone bot is for Discord users to *talk to* Claude

### 2.3 Thread Database (SQLite)

**Schema:**
```sql
CREATE TABLE threads (
  threadId TEXT PRIMARY KEY,
  sessionId TEXT NOT NULL,
  cwd TEXT NOT NULL,
  model TEXT,
  createdAt INTEGER,
  started INTEGER DEFAULT 0,
  lastBotMessageId TEXT,
  isLocalResume INTEGER DEFAULT 0
);
```

**Operations:**
- `getOrCreate(threadId)` — Returns existing or creates new mapping
- `updateLastMessage(threadId, messageId)` — Tracks last bot message
- `cleanupStaleSessions()` — Removes entries with missing session files
- `delete(threadId)` — Removes mapping (used in stale cleanup)

**Isolation Strategy:**
Each agent has its own database file:
- `claude-threads.db` — Claude_ubuntu bot
- `lisa-threads.db` — Lisa bot
- `nyx-threads.db` — Nyx bot
- `kael-threads.db` — Kael bot

This prevents session collisions between agents.

### 2.4 Claude Code CLI Sessions

**Spawn Command:**
```bash
claude -p --resume <sessionId> --cwd <workingDir>
```

**Session File Location:**
```
~/.claude/projects/<sanitized-cwd>/
  <sessionId>.jsonl          # Conversation history
  <sessionId>.lock           # Lock file
```

**Lifecycle:**
1. Bot receives message in thread
2. Looks up or creates session UUID
3. Spawns `claude -p --resume <uuid>`
4. Claude processes message, writes response to stdout
5. Bot captures stdout and sends to Discord
6. Process exits (normal) or gets stuck (abnormal)

### 2.5 Coordination Layer

**Bridge Files:**
- Canonical path: `~/.openclaw/workspace-<agent>/BRIDGE_<AGENT>.md`
- Format: Markdown with headers for sender, timestamp, message
- Protocol: Write-only, read by other agent's bridge monitor

**Telegram INBOX/OUTBOX:**
- Files: `telegram-inbox.md`, `telegram-outbox.md`
- Used when Discord is unavailable or for mobile notifications

**GitHub Live Chat:**
- Repo: `beautiful-talking`
- File: `chat/LIVE-CHAT.md`
- Trigger files: `sync/trigger-claude.md`, `sync/trigger-lisa.md`
- Cron syncs every minute

---

## 3. Data Flow Scenarios

### 3.1 User Sends Message in Thread

```
Discord Thread
    |
    v
Bot: onMessageCreate()
    |
    v
getOrCreate(threadId)
    |---> Check SQLite for existing mapping
    |---> If found: validate session file exists (isSessionValid)
    |---> If stale: delete mapping, create new UUID
    |---> If new: generate UUID, insert into DB
    |
    v
Spawn: claude -p --resume <sessionId> --cwd <dir>
    |
    v
Claude processes message
    |
    v
Bot captures stdout
    |
    v
Send message to Discord thread
```

### 3.2 System Restart Recovery

```
Bot startup (Events.ClientReady)
    |
    v
cleanupStaleSessions()
    |---> SELECT * FROM threads
    |---> For each entry: check if session file exists
    |---> If missing: DELETE FROM threads WHERE threadId = ?
    |---> Log: "removed N stale session mapping(s)"
    |
    v
Bot ready, accepts messages
    |
    v
Message arrives in thread with stale mapping
    |
    v
getOrCreate() detects missing file
    |
    v
Auto-creates fresh session, logs action
```

### 3.3 Multi-Agent Command Routing

```
User: @Claude_ubuntu "Lisa, check GitHub bounties"
    |
    v
Claude receives message
    |
    v
Claude writes to BRIDGE_LISA.md:
    "Mission: Check GitHub bounties. Priority: HIGH"
    |
    v
Lisa's bridge monitor detects file change
    |
    v
Lisa reads bridge, executes task
    |
    v
Lisa writes result back to bridge
    |
    v
Claude reads result, summarizes for user in Discord
```

---

## 4. Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Bot Runtime | Node.js | >=18 |
| Language | TypeScript | 5.x |
| Execution | tsx (TypeScript Execute) | Latest |
| Discord SDK | discord.js | 14.x |
| Database | SQLite | 3.x |
| ORM/Wrapper | Better-sqlite3 | Latest |
| CLI Wrapper | Claude Code CLI | Latest |
| Process Mgmt | systemd (user services) | - |
| Monitoring | Cron + journalctl | - |

---

## 5. Scaling Considerations

### Current Limits
- **Discord Rate Limits:** 5 messages/5 seconds per channel
- **Claude API Limits:** Dependent on tier
- **Concurrent Sessions:** Limited by `claude -p` process count
- **SQLite:** Single-writer, sufficient for thread metadata

### Future Scaling Paths
1. **Redis** for distributed session state (if multi-node)
2. **PostgreSQL** for thread database (if >100k threads)
3. **Queue System** (Bull/BullMQ) for `claude -p` job scheduling
4. **Shard Bot** across multiple Discord gateway connections

---

## 6. Security Boundaries

| Boundary | Protection |
|----------|-----------|
| Discord Token | `.env` file, not committed |
| Claude API Key | Environment variable |
| Session Files | `~/.claude/projects/` (user home) |
| Bridge Files | `~/.openclaw/workspace-<agent>/` (restricted) |
| Database | File permissions 600 |
| Process Spawn | Sanitized cwd, no shell injection |

**Input Sanitization:**
- Working directory validated against whitelist
- No shell metacharacters passed to spawn
- Thread IDs validated as Discord snowflakes
