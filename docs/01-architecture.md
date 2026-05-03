# System Architecture

> Complete technical architecture of the Claude Discord bot.

---

## 1. High-Level Architecture

```
Discord User
     |
     v
Discord Thread / @mention
     |
     v
+----------------------------------+
| discord-claude-code-bot          |
| (Node.js, discord.js)            |
| - SQLite session persistence     |
| - Stale session auto-cleanup     |
| - Duplicate instance prevention  |
+----------------------------------+
     |
     v
spawns: claude -p --resume <uuid>
     |
     v
+----------------------------------+
| Claude Code CLI Session          |
| - Executes commands              |
| - Writes responses               |
+----------------------------------+
     |
     v
+----------------------------------+
| Discord Thread                   |
| - Bot sends response             |
| - User continues conversation    |
+----------------------------------+
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
- `threads.db` — SQLite database with WAL mode

**Environment Variables:**
```bash
DISCORD_TOKEN=<token>              # Discord bot application token
DEFAULT_CWD=/path/to/workdir       # Default working directory
CLAUDE_BIN=claude                  # Claude CLI command (default: claude)
GUILD_ID=<guild-id>                # Optional: restrict slash commands to guild
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
  model TEXT NOT NULL,
  createdAt INTEGER NOT NULL,
  started INTEGER NOT NULL DEFAULT 0,
  lastBotMessageId TEXT,
  isLocalResume INTEGER NOT NULL DEFAULT 0
);
```

**Operations:**
- `getOrCreate(threadId)` — Returns existing or creates new mapping
- `updateLastMessage(threadId, messageId)` — Tracks last bot message
- `saveEntry(threadId, entry)` — Persists mapping
- `loadMap()` — Loads all mappings into memory

### 2.4 Claude Code CLI Sessions

**Spawn Command:**
```bash
claude -p --resume <sessionId> --model <model> --cwd <workingDir>
```

**Session File Location:**
```
~/.claude/projects/<sanitized-cwd>/
  <sessionId>.jsonl          # Conversation history
```

**Lifecycle:**
1. Bot receives message in thread
2. Looks up or creates session UUID
3. Spawns `claude -p --resume <uuid>`
4. Claude processes message, writes response to stdout
5. Bot captures stdout and sends to Discord
6. Process exits (normal) or gets stuck (abnormal)

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
    |---> If found: return existing
    |---> If new: generate UUID, insert into DB
    |
    v
Spawn: claude -p --resume <sessionId> --cwd <dir>
    |
    v
Claude processes message
    |
    v
Bot captures stdout (streaming)
    |
    v
Send message to Discord thread
```

### 3.2 System Restart Recovery

```
Bot startup (Events.ClientReady)
    |
    v
getOrCreate() detects missing session file
    |---> Validate session file exists
    |---> If missing: create fresh UUID
    |---> Update database
    |
    v
Bot ready, accepts messages
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
| Database | File permissions 600 |
| Process Spawn | Sanitized cwd, no shell injection |

**Input Sanitization:**
- Working directory validated against filesystem
- No shell metacharacters passed to spawn
- Thread IDs validated as Discord snowflakes
