# WinSCP Usage Guide

A quick-start guide for Windows users who want to browse, edit, and transfer files on a remote Linux box using a graphical interface.

## Prerequisites

Before you begin, you should have received three pieces of connection information:

| Parameter | Description | Example used in this guide |
|---|---|---|
| **Hostname / IP address** | The address of the Linux box | `192.168.54.79` |
| **Port** | The SSH port (not always the default 22) | `22228` |
| **Username** | Your user account on the Linux box | `analyst` |

All examples in this document use the values above. Replace them with whatever you were given if yours differ.

You also need WinSCP installed on your Windows machine. Download it from [winscp.net](https://winscp.net/eng/download.php). The installer is straightforward -- accept the defaults.

## Table of Contents

- [1. What WinSCP Is](#1-what-winscp-is)
- [2. Connecting to the Remote Machine](#2-connecting-to-the-remote-machine)
  - [2.1 First-Time Login](#21-first-time-login)
  - [2.2 Saving the Session for Next Time](#22-saving-the-session-for-next-time)
  - [2.3 Reconnecting Later](#23-reconnecting-later)
- [3. The WinSCP Interface](#3-the-winscp-interface)
  - [3.1 Two-Panel Layout](#31-two-panel-layout)
  - [3.2 Navigating to /workspace/sql](#32-navigating-to-workspacesql)
  - [3.3 Browsing Files and Directories](#33-browsing-files-and-directories)
- [4. Transferring Files](#4-transferring-files)
  - [4.1 Downloading Files (Remote to Local)](#41-downloading-files-remote-to-local)
  - [4.2 Uploading Files (Local to Remote)](#42-uploading-files-local-to-remote)
  - [4.3 Drag and Drop](#43-drag-and-drop)
- [5. Editing Remote Files](#5-editing-remote-files)
- [6. Gotchas and Tips](#6-gotchas-and-tips)
  - [6.1 Line Endings](#61-line-endings)
  - [6.2 Case Sensitivity](#62-case-sensitivity)
  - [6.3 Hidden Files](#63-hidden-files)
  - [6.4 Permissions](#64-permissions)
- [7. End-to-End Walkthrough](#7-end-to-end-walkthrough)

---

## 1. What WinSCP Is

WinSCP is a free, graphical file manager for Windows that connects to remote Linux machines over SSH (the same protocol used by the `ssh` command in PowerShell). It gives you a familiar Explorer-like view of the remote file system so you can browse directories, drag-and-drop files, and edit text files without learning command-line tools.

Under the hood it uses SFTP (SSH File Transfer Protocol), so it uses the same credentials and port as your SSH connection -- no additional server software is needed.

---

## 2. Connecting to the Remote Machine

### 2.1 First-Time Login

1. Launch WinSCP. The **Login** dialog appears automatically.

2. Fill in the connection fields:

   | Field | Value |
   |---|---|
   | File protocol | `SFTP` (the default) |
   | Host name | `192.168.54.79` |
   | Port number | `22228` |
   | User name | `analyst` |
   | Password | *(leave blank if using a key -- see below)* |

3. **If you are using an SSH key** (the same key you use with `ssh -i`):
   - Click **Advanced...** > **SSH** > **Authentication**.
   - In the **Private key file** field, browse to your key file.
   - WinSCP accepts `.ppk` (PuTTY format) natively. If your key is in OpenSSH format (`id_rsa`, `id_ed25519`), WinSCP will offer to convert it to `.ppk` for you -- click **OK** when prompted.

4. Click **Login**.

5. **First connection:** You will see a host key warning:

   ```
   The server's host key was not found in the cache. You have no guarantee
   that the server is the computer you think it is.
   The server's ED25519 key fingerprint is: ssh-ed25519 256 SHA256:xxxxx
   Do you want to continue connecting and add the host key to the cache?
   ```

   This is normal and equivalent to the fingerprint prompt you see with command-line SSH. Click **Yes**. This only happens once per host.

6. You are now connected. The remote file system appears in the right panel.

### 2.2 Saving the Session for Next Time

Before or after logging in, you can save the connection so you don't have to re-type everything:

1. In the **Login** dialog, fill in the fields as above.
2. Click **Save**.
3. Give it a name, e.g. `YoloBox`.
4. Click **OK**.

The saved session appears in the left-hand tree of the Login dialog for future use.

### 2.3 Reconnecting Later

1. Launch WinSCP.
2. In the Login dialog, select your saved session (`YoloBox`).
3. Click **Login**.

That's it. You are back in.

---

## 3. The WinSCP Interface

### 3.1 Two-Panel Layout

WinSCP defaults to a **Commander** interface with two panels side by side:

```
+---------------------------+---------------------------+
|     LOCAL (your PC)       |     REMOTE (Linux box)    |
|                           |                           |
|  C:\Users\you\Documents   |  /home/analyst            |
|                           |                           |
|  file1.txt                |  .bashrc                  |
|  file2.sql                |  .claude/                 |
|  notes/                   |  projects/                |
|                           |                           |
+---------------------------+---------------------------+
```

- **Left panel** = your local Windows file system.
- **Right panel** = the remote Linux file system.

You can navigate each panel independently, just like two Explorer windows.

### 3.2 Navigating to /workspace/sql

When you first connect, WinSCP drops you into the home directory (`/home/analyst`). To navigate to the project directory:

1. Click in the **path bar** at the top of the remote (right) panel. It shows something like `/home/analyst`.
2. Clear it and type: `/workspace/sql`
3. Press **Enter**.

You are now looking at the project files. Alternatively, use the directory tree on the left side of the remote panel to click through `/` > `workspace` > `sql`.

**Tip:** To make WinSCP always open this directory, edit your saved session: Login dialog > select the session > **Edit** > **Directories** > set **Remote directory** to `/workspace/sql`.

### 3.3 Browsing Files and Directories

- **Double-click** a directory to enter it.
- **Double-click** a file to open it in the built-in editor (see [section 5](#5-editing-remote-files)).
- Click the `..` entry at the top of the file list to go up one level.
- **Right-click** any file or directory for a context menu with rename, delete, copy, properties, etc.

---

## 4. Transferring Files

### 4.1 Downloading Files (Remote to Local)

1. In the **remote panel** (right), navigate to the file or directory you want.
2. Select it (click once).
3. Press **F5** (or click the **Download** button in the toolbar).
4. A dialog appears showing the destination path on your local machine. Adjust if needed.
5. Click **OK**.

The file is copied to your local machine.

### 4.2 Uploading Files (Local to Remote)

1. In the **local panel** (left), navigate to the file you want to upload.
2. Select it.
3. Press **F5** (or click the **Upload** button).
4. Confirm the remote destination path.
5. Click **OK**.

### 4.3 Drag and Drop

You can also drag files between the two panels, or drag files from Windows Explorer directly into the WinSCP remote panel. This works in both directions.

---

## 5. Editing Remote Files

WinSCP includes a built-in text editor for quick edits to remote files:

1. Navigate to the file in the remote panel.
2. **Double-click** the file, or select it and press **F4**.
3. The file opens in WinSCP's internal editor.
4. Make your changes.
5. Press **Ctrl+S** to save. WinSCP automatically uploads the modified file back to the server.
6. Close the editor tab when done.

**Using an external editor (e.g., VS Code, Notepad++):**

1. Go to **Options** > **Preferences** > **Editors**.
2. Click **Add...** > **External editor**.
3. Browse to the editor executable (e.g., `C:\Users\you\AppData\Local\Programs\Microsoft VS Code\Code.exe`).
4. Move it above the internal editor in the list so it becomes the default.
5. Now when you press **F4** or double-click a file, it opens in your preferred editor. Saving in the editor triggers WinSCP to upload the change automatically.

---

## 6. Gotchas and Tips

### 6.1 Line Endings

WinSCP transfers files in **binary mode** by default, which preserves line endings exactly as they are. This is usually what you want. Do not switch to "text mode" unless you have a specific reason -- text mode converts line endings during transfer and can corrupt non-text files.

If you edit a file on Windows and save it with Windows line endings (`\r\n`), the remote Linux machine may not handle it well. Configure your editor to use **LF** (Unix) line endings:

- **VS Code:** Bottom-right status bar shows `CRLF` or `LF`. Click it to toggle.
- **Notepad++:** Edit > EOL Conversion > Unix (LF).

### 6.2 Case Sensitivity

Linux file systems are case-sensitive. `Report.sql` and `report.sql` are two different files. Windows is not case-sensitive, so if you download both to the same Windows folder, one will overwrite the other. Be careful when transferring directories that contain files differing only by case.

### 6.3 Hidden Files

On Linux, files and directories starting with a dot (`.bashrc`, `.claude/`) are hidden by default. WinSCP shows them, but they can be easy to overlook. To toggle visibility: **Options** > **Preferences** > **Panels** > check or uncheck **Show hidden files**.

### 6.4 Permissions

Linux files have permissions (read/write/execute) that Windows does not. You can view and change them in WinSCP by right-clicking a file and selecting **Properties**. Generally you should not need to change permissions on files in `/workspace/sql` -- the defaults are fine.

---

## 7. End-to-End Walkthrough

This section walks through a complete session: connect, browse to the project, download a file, edit it, and upload it back.

### Step 1: Launch WinSCP and connect

Open WinSCP. In the Login dialog:

- Host name: `192.168.54.79`
- Port: `22228`
- User name: `analyst`
- (Configure your SSH key under Advanced > SSH > Authentication if applicable)

Click **Login**. Accept the host key if prompted.

### Step 2: Navigate to the project directory

In the remote panel path bar, type `/workspace/sql` and press Enter.

You now see the project files.

### Step 3: Download a file to review locally

Select a file (e.g., `example_query.sql`), press **F5**, confirm the local destination, click **OK**. The file is now on your Windows machine.

### Step 4: Edit a file directly on the server

Double-click a `.sql` file in the remote panel. It opens in the WinSCP editor (or your configured external editor). Make your changes, press **Ctrl+S**. WinSCP uploads the saved file automatically.

### Step 5: Upload a file from your local machine

In the local panel (left), navigate to the file you want to upload. Select it, press **F5**, confirm the remote destination (`/workspace/sql/`), click **OK**. The file is now on the server.

### Step 6: Disconnect

Close WinSCP, or go to **Session** > **Disconnect**. No cleanup is needed -- SFTP connections are stateless, so there is nothing to "detach" from (unlike tmux).

### Quick reference: the full sequence

```
[Windows]  Launch WinSCP
[Login]    Host: 192.168.54.79, Port: 22228, User: analyst -> Login
[WinSCP]   Navigate remote panel to /workspace/sql
[WinSCP]   Browse, download (F5), upload (F5), or edit (F4/double-click) files
[WinSCP]   Close WinSCP when done
```
