# SOP: Session Management

**Rule**: Use `sessions/` to log detailed work. Keep `memory.md` for high-level lessons only.

## 0. Housekeeping (Auto-Cleanup)
*   **Trigger**: Start of a new session.
*   **Check**: Read `Session Retention` in `.rokct/memory.md`.
*   **Action**: If NOT "Forever":
    1.  Scan `sessions/` for files marked `Status: [CLOSED]`.
    2.  Check the Date in the filename/header.
    3.  **DELETE** files older than the limit.
*   *Goal*: Manage repo clutter automatically.

## 1. Start a Session
*   **0. Update Rules**: Run `git submodule update --remote`.
    *   *If updated*: Copy `The-Rokct-Protocol/.cursorrules` -> `./.cursorrules`.
    *   **Action (Environment Check)**:
        1.  **Determine Type**: Are you in a **Local Terminal** (Unrestricted) or a **Cloud/Web Agent** (Restricted/Jules)?
        2.  **Select Mode**: Ask: *"Is this session for [Planning] (Read-Only/No Edits) or [Building] (Full Edits)?"*
        3.  **Load Rules**: Copy `The-Rokct-Protocol/modes/[selection].md` -> `.rokct/mode_rules.md`.
        4.  **If Cloud/Web**: **SKIP** all branching. Work on the current branch assigned to you. Do not switch.
        5.  **If Local & Building**:
            *   *If New*: `git checkout -b users/[Name]/[Task]`.
            *   *If Exists*: `git checkout users/[Name]/[Task]`.
            *   `git push -u origin users/[Name]/[Task]` (Ignore errors).
    *   *Why*: Prevents you from accidentally overwriting code on the wrong branch.
*   **Filename**: `sessions/YYYY-MM-DD_@<SafeID>_TaskName.md`
    *   **ID Construction**: Read `Safe ID` from `.rokct/memory.md`. (e.g., `ray.dev.9ac2b1`).
*   **Header**:
    ```markdown
    # Session: [Task Name]
    **Branch**: users/[Name]/[Task]
    **Date**: 2026-05-21
    **User**: [Preferred Name] (e.g. Ray)
    **ID**: [Safe ID] (e.g. ray.dev.9ac2b1)
    **Mode**: [Planning / Building]
    **Status**: [Active]
    ```
*   **Log**: Record your steps, thoughts, and partial decisions there.

## 2. Resume a Session (Wake Up)
*   **Trigger**: You are assigned a task but no session is explicitly active (or you woke up from a checkpoint).
*   **Action**:
    1.  **Grounding**: **READ `.cursorrules`** immediately. Do NOT assume you know the protocol.
    2.  **Context**: Read `.rokct/memory.md` for recent lessons.
    3.  **Locate**: Read `.rokct/active_session.txt` to find the last active session.
    4.  **Resume**: Open that session file and append a new log entry: `* **[WAKE UP]**: Resuming session...`.
*   **Why**: Prevents "Protocol Drift" where agents forget rules after a checkpoint restore.

## 3. During the Session
*   **Switching Modes (Plan -> Build)**:
    *   **Trigger**: User approves the Plan and says "Proceed".
    *   **Action**:
        1.  **Update Rules**: Copy `The-Rokct-Protocol/modes/building.md` -> `.rokct/mode_rules.md`.
        2.  **Update Log**: Change Header to `**Mode**: Building`.
        3.  **Log**: "Switched to Building Mode. Full access enabled."
*   **Focus**: Stay on the user's current focus.
*   **Detours (Minor)**: If the user makes a small request (e.g., "Fix .github first") related to the project but not the specific task, **stay in the current session**. Log it as a detour.
*   **Context Switch (Major)**: If the user requests a *completely unrelated* task:
    1.  **Ask**: "Is this a new session or related to the current task?" (If ambiguous).
    2.  **PAUSE/SWITCH**: Only if user confirms it is separate.
    3.  **Full Stack Exception**: If moving from Backend -> Frontend for the *same feature*, **STAY** in the current session. Context is needed.
*   **Do NOT mix contexts**: Truly unrelated tasks (e.g., "Fixing Billing" vs "Designing Chat") must remain separate.

## 4. Persistence (Anti-Hang)
*   **Context**: Critical for Cloud Agents (Jules).
*   **Trigger**: Completion of a significant step.
*   **Action**:
    1.  **Read**: Check `Checkpoint Policy` in `.rokct/memory.md`.
    2.  **If 'Frequent'**: **AUTO-COMMIT** (without asking). `git commit -am "Checkpoint: [Action]"` (or Platform Submit).
    3.  **If 'Manual'**: Do nothing (Wait for user).
    4.  *Why*: Keeps you safe without nagging.

## 4. Maintenance (Anti-Conflict)
*   **Trigger**: User says "Update Base" or you are about to Merge.
*   **Action**: `git pull --rebase origin main`.
*   **Why**: This "swaps the base" of your branch to the latest code, resolving conflicts locally before you push.

## 4. Long Sessions (The "Rolling" Strategy)
*   **Trigger**: If the session log exceeds ~200 lines (or feels too large).
*   **Action**:
    1.  **Summarize**: Create a "Context Anchor". **CRITICAL**: This must be a *Cumulative Summary* of the entire mission (Part 1-X), not just the last file. Don't lose the original goal!
    2.  **Archive**: Rename the file to `TaskName_Part1.md`.
    3.  **Continue**: Create `TaskName_Part2.md`. Paste the "Context Anchor" at the top.
*   **Deep Retrieval**: The archived parts (`Part1`, `Part2`) are **NOT DEAD**. They are "Reference Library".
    *   If you need a specific detail from weeks ago, **READ** the archived file.
    *   Do not guess. Go back and check the logs.

## 5. End a Session (Critical)
*   **Trigger**: You believe the task is complete.
*   **ACTION**: **ASK THE USER**: "Are we done with this session? Shall I archive it and update Memory?"
*   **PROHIBITED**: Do **NOT** close a session or assume the user is ready to move on without explicit permission.
*   **Reason**: The user may have unvoiced concerns, side-tasks, or just want to "hang out" in the current context longer.

## 6. Closing (Only after Approval)
*   **Extract**: Copy *only* reusable lessons to `.rokct/memory.md`.
*   **Cleanup Decision**:
    *   Ask: *"Shall I keep the session logs (`sessions/*.md`) for history, or delete them to keep the repo clean?"*
    *   **Keep**: Rename file to `[CLOSED]_...`.
    *   **Delete**: Remove the file.
    *   *Default*: Keep (History is valuable).
