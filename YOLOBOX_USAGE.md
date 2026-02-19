# YoloBox Usage Guide

A quick-start guide for Windows users connecting to and working on a remote Linux box.

## Prerequisites

Before you begin, you should have received three pieces of connection information:

| Parameter | Description | Example used in this guide |
|---|---|---|
| **Hostname / IP address** | The address of the Linux box | `192.168.54.79` |
| **Port** | The SSH port (not always the default 22) | `22228` |
| **Username** | Your user account on the Linux box | `analyst` |

All examples in this document use the values above. Replace them with whatever you were given if yours differ.

## Table of Contents

- [1. SSH from PowerShell](#1-ssh-from-powershell)
- [2. tmux (Terminal Multiplexer)](#2-tmux-terminal-multiplexer)
  - [2.1 Why tmux?](#21-why-tmux)
  - [2.2 Session States](#22-session-states)
  - [2.3 Common Commands](#23-common-commands)
  - [2.4 Scrolling in tmux](#24-scrolling-in-tmux)
- [3. Navigating Directories](#3-navigating-directories)
  - [3.1 What "Being in a Directory" Means](#31-what-being-in-a-directory-means)
  - [3.2 Essential Commands](#32-essential-commands)
- [4. Surprises for Windows Users](#4-surprises-for-windows-users)
  - [4.1 Ctrl+C Does Not Copy](#41-ctrlc-does-not-copy)
  - [4.2 Copy and Paste in PowerShell / Windows Terminal](#42-copy-and-paste-in-powershell--windows-terminal)
  - [4.3 Paths Use Forward Slashes](#43-paths-use-forward-slashes)
  - [4.4 Everything Is Case-Sensitive](#44-everything-is-case-sensitive)
  - [4.5 No File Extensions Required](#45-no-file-extensions-required)
  - [4.6 Line Endings](#46-line-endings)
  - [4.7 Ctrl+Z vs Ctrl+C](#47-ctrlz-vs-ctrlc)
  - [4.8 Ctrl+S Freezes the Terminal](#48-ctrls-freezes-the-terminal)
  - [4.9 Tab Completion](#49-tab-completion)
- [5. End-to-End Walkthrough: Running Claude](#5-end-to-end-walkthrough-running-claude)
- [6. Long-Running Tasks: Launch, Disconnect, Resume](#6-long-running-tasks-launch-disconnect-resume)

---

## 1. SSH from PowerShell

Windows 10/11 ships with an SSH client built into PowerShell. Open PowerShell and run:

```powershell
ssh -p 22228 analyst@192.168.54.79
```

The default user account is `analyst`. The `-p 22228` flag specifies the non-standard port.

**Using an existing SSH key:** If your key is in the default location (`C:\Users\<you>\.ssh\id_rsa` or `id_ed25519`), SSH will find it automatically. If the key is elsewhere, point to it explicitly:

```powershell
ssh -p 22228 -i C:\Users\<you>\.ssh\my_key analyst@192.168.54.79
```

**First connection:** You will see a fingerprint prompt like this:

```
The authenticity of host '[192.168.54.79]:22228' can't be established.
ED25519 key fingerprint is SHA256:xxxxx.
Are you sure you want to continue connecting (yes/no)?
```

Type `yes` and press Enter. This only happens once per host; the fingerprint is saved to your `known_hosts` file.

**If something goes wrong:**

| Symptom | Likely cause |
|---|---|
| `Connection refused` | Wrong port, or SSH server not running |
| `Permission denied (publickey)` | Wrong key, wrong username, or key not authorized on the server |
| `Connection timed out` | Firewall blocking the port, or wrong IP |

Add `-v` for verbose output to help debug: `ssh -v -p 22228 analyst@192.168.54.79`

**Disconnecting from SSH:**

When you are done and want to close the connection, type:

```bash
exit
```

Or press `Ctrl+d`. Either one closes the remote shell and drops you back into your local PowerShell. If you are inside tmux, `exit` will close the tmux window first (see [section 2](#2-tmux-terminal-multiplexer)); you need to exit tmux *and then* exit the SSH shell, or simply detach from tmux first and then `exit`.

---

## 2. tmux (Terminal Multiplexer)

### 2.1 Why tmux?

If your SSH connection drops (laptop closes, Wi-Fi blips), any running process dies with it. tmux keeps your session alive on the server so you can reconnect and pick up exactly where you left off.

### 2.2 Session States

A tmux session is always in one of these states:

| State | What it means |
|---|---|
| **No session exists** | Nothing is running. You need to create one. |
| **Attached** | You are connected to the session and can see/interact with it. |
| **Detached (unattached)** | The session is still running on the server, but no one is looking at it. Programs inside it keep running. |

Think of it like a TV: detaching is turning off the screen, not unplugging the console. Everything keeps running; you just aren't watching.

### 2.3 Common Commands

**Create a new session:**

```bash
tmux new -s work
```

This creates a session named `work` and attaches you to it. You can name it anything.

**Detach from a session (leave it running):**

Press `Ctrl+b`, then release both keys, then press `d`.

This is the standard tmux "prefix" pattern: `Ctrl+b` is a prefix chord, followed by a command key. You will be dropped back to your normal shell. The session keeps running.

**List existing sessions:**

```bash
tmux ls
```

Output looks like: `work: 1 windows (created Thu Feb 19 10:00:00 2026)`

**Attach to an existing session:**

```bash
tmux attach -t work
```

Or if there's only one session:

```bash
tmux attach
```

**Kill a session you no longer need:**

```bash
tmux kill-session -t work
```

**Quick reference for inside tmux:**

| Keys | Action |
|---|---|
| `Ctrl+b`, then `d` | Detach from session |
| `Ctrl+b`, then `c` | Create a new window (tab) inside the session |
| `Ctrl+b`, then `n` | Switch to next window |
| `Ctrl+b`, then `p` | Switch to previous window |
| `Ctrl+b`, then `0`-`9` | Switch to window by number |

### 2.4 Scrolling in tmux

If you try to scroll up with your mouse wheel or `Page Up` in tmux, it won't work the way you expect. tmux intercepts your input, so normal scrolling doesn't reach the scrollback buffer.

**The document analogy:** Think of your terminal as reading a long document through a small window (the **viewport**). The document itself (the **content**) is everything that has been printed to the terminal -- all command output, all of Claude's responses, everything. The viewport only shows the last screenful. Normally you are stuck staring at the bottom of the document. Scroll mode lets you slide the viewport up to read earlier content.

```
    +------------------------------------------+
    |  earlier output (scrolled off screen)    |  ^
    |  ...                                     |  |  content above
    |  ...                                     |  |  (scroll up to see)
    +==========================================+
    |                                          |  <-- viewport
    |  what you currently see on screen        |      (your terminal window)
    |                                          |
    +==========================================+
    |  (new output appears here)               |  <-- bottom (live)
    +------------------------------------------+
```

**To enter scroll mode:** Press `Ctrl+b`, then `[`.

You are now in **copy mode**. The top-right corner of the terminal will show a line position indicator (e.g., `[0/1542]`). You can now navigate:

| Keys | Action |
|---|---|
| `Up` / `Down` arrows | Scroll one line at a time |
| `Page Up` / `Page Down` | Scroll one screenful at a time |
| `g` | Jump to the top of the scrollback (beginning of history) |
| `G` | Jump to the bottom (most recent output) |
| `q` or `Esc` | **Exit scroll mode** and return to the live terminal |

**Important:** While in scroll mode, you cannot type commands. The terminal looks frozen because you are viewing history, not the live session. Press `q` or `Esc` to exit scroll mode and get back to normal.

This is a common source of confusion: you enter scroll mode accidentally, and then the terminal appears to ignore your typing. If your tmux session stops responding to keyboard input but you see a position indicator in the corner, you are in scroll mode -- press `q` to get out.

---

## 3. Navigating Directories

### 3.1 What "Being in a Directory" Means

Every shell session has a **current working directory** (cwd). It is the folder that commands operate on by default. When you run `ls`, it lists files *in your current directory*. When you run `python script.py`, it looks for `script.py` *in your current directory*.

This is identical in concept to having a folder open in File Explorer -- you are "in" that folder.

To see where you are right now:

```bash
pwd
```

This prints the full path, e.g. `/home/user/projects`.

### 3.2 Essential Commands

```bash
# Go to a directory
cd /home/user/projects

# Go up one level
cd ..

# Go to your home directory (shortcut)
cd ~
# or just:
cd

# List files in current directory
ls

# List files with details (permissions, size, date)
ls -la

# List files in some other directory without going there
ls /var/log
```

**Absolute vs relative paths:**

- `/home/user/projects` -- absolute (starts with `/`, the root). Always works regardless of where you are.
- `projects/subfolder` -- relative (no leading `/`). Interpreted relative to your current directory.

---

## 4. Surprises for Windows Users

### 4.1 Ctrl+C Does Not Copy

In a Linux terminal, `Ctrl+C` sends an **interrupt signal** to the running program, which usually kills it. It does *not* copy text.

This is the single most common source of confusion. If you reflexively hit `Ctrl+C` to copy, you will kill whatever is running.

### 4.2 Copy and Paste in PowerShell / Windows Terminal

How to copy and paste depends on your terminal:

| Terminal | Copy | Paste |
|---|---|---|
| **Windows Terminal** | Select text with mouse (auto-copies) | Right-click, or `Ctrl+Shift+V` |
| **PowerShell (legacy)** | Select text, press `Enter` | Right-click |

Inside an SSH session, these host-side shortcuts still apply since your terminal handles it locally before sending keystrokes to the remote machine.

### 4.3 Paths Use Forward Slashes

Windows: `C:\Users\me\Documents`
Linux: `/home/me/documents`

Linux uses `/` (forward slash) as the path separator. There are no drive letters. Everything lives under a single root `/`.

### 4.4 Everything Is Case-Sensitive

`File.txt`, `file.txt`, and `FILE.TXT` are three different files. This applies to commands, file names, directory names, and environment variables.

```bash
cd /home/User    # WRONG if the directory is actually /home/user
```

### 4.5 No File Extensions Required

Linux doesn't rely on file extensions to determine file type. A script is executable because of its *permissions*, not because it ends in `.exe`. You may encounter files with no extension that are perfectly runnable programs.

### 4.6 Line Endings

Windows uses `\r\n` (CRLF) for line endings. Linux uses `\n` (LF). If you edit a file on Windows and transfer it to Linux, scripts may break with obscure errors like `/bin/bash^M: bad interpreter`. Fix with:

```bash
sed -i 's/\r$//' filename
```

Or configure your editor (VS Code, etc.) to use LF line endings for files destined for Linux.

### 4.7 Ctrl+Z vs Ctrl+C

- `Ctrl+C` -- interrupt (kill) the running process.
- `Ctrl+Z` -- **suspend** the process (pause it and return to your shell). The process is *not* killed; it is stopped in the background. This can be confusing if you think you exited something but it is still sitting there paused. Type `fg` to bring it back to the foreground, or `kill %1` to kill it.

### 4.8 Ctrl+S Freezes the Terminal

On Windows, `Ctrl+S` means "Save". In a Linux terminal, `Ctrl+S` triggers **XON/XOFF flow control** -- it freezes all terminal output. Your session will appear completely stuck: no text appears, no prompt, nothing. The terminal is not broken and your processes are still running; the screen is simply paused.

To unfreeze, press `Ctrl+Q`.

This is one of the most panic-inducing gotchas for Windows users, because there is zero visual feedback that flow control is active. If your terminal suddenly stops responding but the SSH connection is still alive, try `Ctrl+Q` before anything else.

### 4.9 Tab Completion

Press `Tab` to auto-complete commands, file names, and paths. Press `Tab` twice to see all possible completions if there are multiple matches. This is your best friend for avoiding typos and navigating faster.

---

## 5. End-to-End Walkthrough: Running Claude

This section walks through a complete session from start to finish.

### Step 1: Connect via SSH

Open PowerShell on your Windows machine:

```powershell
ssh -p 22228 analyst@192.168.54.79
```

You are now on the Linux box.

### Step 2: Start or resume a tmux session

Check if a session already exists:

```bash
tmux ls
```

If you see an existing session (e.g. `work`), attach to it:

```bash
tmux attach -t work
```

If there are no sessions (or you see `no server running`), create a new one:

```bash
tmux new -s work
```

### Step 3: Navigate to the project directory

```bash
cd /workspace/sql
```

Verify you are in the right place:

```bash
pwd
# /workspace/sql
```

### Step 4: Run Claude

```bash
claude --dangerously-skip-permissions
```

The `--dangerously-skip-permissions` flag lets Claude execute tools (shell commands, file edits, etc.) without asking for confirmation on each action. This is required for autonomous operation but means Claude can modify files, run commands, and make changes without prompting you first -- hence "dangerously".

Claude will start an interactive session. Type your prompt or instructions and let it work.

### Step 5: Quit Claude

When you are done working with Claude, type:

```
/exit
```

at the Claude prompt. You can also press `Ctrl+c` multiple times to interrupt Claude's current action and return to the Claude prompt, and then `/exit`. This brings you back to the normal bash shell.

### Step 6: Detach from tmux

Press `Ctrl+b`, then `d`.

You are now back at the bare SSH shell. The tmux session (and anything running inside it) continues in the background. Next time you connect, you can pick up where you left off with `tmux attach -t work`.

### Step 7: Disconnect from SSH

```bash
exit
```

You are back in your local PowerShell. The tmux session on the server is still alive and will be there when you reconnect.

### Quick reference: the full sequence

```
[PowerShell] ssh -p 22228 analyst@192.168.54.79
[SSH]        tmux attach -t work  (or: tmux new -s work)
[tmux]       cd /workspace/sql
[tmux]       claude --dangerously-skip-permissions
             ... do your work ...
[claude]     /exit
[tmux]       Ctrl+b, d             (detach from tmux)
[SSH]        exit                   (disconnect SSH)
[PowerShell] you're back home
```

---

## 6. Long-Running Tasks: Launch, Disconnect, Resume

This is the real power of tmux + SSH: you can give Claude a big task, walk away (or close your laptop, change Wi-Fi networks, move to a different location), and come back later to check on progress. Claude keeps running inside the tmux session regardless of your SSH connection.

### Part A: Launch the task

**1. Connect and attach to tmux:**

```powershell
ssh -p 22228 analyst@192.168.54.79
```

```bash
tmux attach -t work
# or if no session exists:
tmux new -s work
```

**2. Navigate and start Claude:**

```bash
cd /workspace/sql
claude --dangerously-skip-permissions
```

**3. Give Claude a large task:**

Type your prompt, e.g.:

```
Refactor all the SQL views in the /workspace/sql/views directory to use CTEs instead
of nested subqueries. Update the corresponding tests.
```

Claude begins working. You will see it reading files, making edits, running commands.

**4. Detach from tmux (without stopping Claude):**

Press `Ctrl+b`, then `d`.

Claude is still running inside the tmux session. You are back at the bare SSH shell.

**5. Disconnect from SSH:**

```bash
exit
```

Close your laptop, go get coffee, drive home -- whatever you like. The tmux session and Claude inside it are completely unaffected.

### Part B: Resume later

You are now at a different location, different Wi-Fi, maybe a different computer (as long as it has your SSH key).

**1. Reconnect via SSH:**

```powershell
ssh -p 22228 analyst@192.168.54.79
```

**2. Reattach to the tmux session:**

```bash
tmux attach -t work
```

You are now looking at exactly the same terminal you left. There are two possible states:

- **Claude is still working** -- you will see its output scrolling as it continues the task. You can watch, or scroll up to review what it has done so far.
- **Claude has finished** -- you will see its final output and the Claude prompt waiting for your next instruction. Review the results and continue working, give it another task, or `/exit`.

### Quick reference: launch and resume

```
=== LAUNCH (e.g., at the office) ===

[PowerShell] ssh -p 22228 analyst@192.168.54.79
[SSH]        tmux new -s work        (or: tmux attach -t work)
[tmux]       cd /workspace/sql
[tmux]       claude --dangerously-skip-permissions
[claude]     <give it a big task>
             Ctrl+b, d               (detach -- Claude keeps running)
[SSH]        exit                    (disconnect SSH)
[PowerShell] close laptop, go home

=== RESUME (e.g., at home) ===

[PowerShell] ssh -p 22228 analyst@192.168.54.79
[SSH]        tmux attach -t work     (pick up where you left off)
[tmux]       <Claude is either still working or finished -- review results>
```

### What if my SSH connection drops unexpectedly?

Nothing bad happens. The tmux session survives connection drops, network outages, and laptop suspends. Simply reconnect and `tmux attach -t work`. Everything is exactly as you left it (or further along, if Claude was still working).
