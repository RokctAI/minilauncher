# SOP: Start a New Session

**Trigger**: You start working on a project and see a `.rokct/` folder already exists.

## Procedure

0.  **Sync Protocol (Always First)**:
    *   Check if `The-Rokct-Protocol/` directory exists.
    *   If NOT found → skip this entire step. You are running inside the protocol repo itself.
    *   If NOT a registered submodule → skip. You are in the monorepo.
    *   If registered → run `git submodule update --remote The-Rokct-Protocol`
    *   Now `The-Rokct-Protocol/version.json` reflects the latest remote version.
    *   Compare `The-Rokct-Protocol/version.json` vs `.rokct/protocol_version.json`.
    *   If different → read and follow `The-Rokct-Protocol/workflows/update_protocol.md`.
    *   If same → skip.

1.  **Read Memory**:
    *   Read `.rokct/memory.md` in full.
    *   Note the user's name, Safe ID, preferences, Agent Delegation Framework, and all Lessons Learned.
    *   Do **NOT** ask questions already answered in memory.

2.  **Read Project Map**:
    *   Read `.rokct/project_map.md`.
    *   Understand where things are before touching anything.

3.  **Check Active Session**:
    *   Read `.rokct/active_session.txt`.
    *   If empty or no active session → proceed to step 4.
    *   If an active session exists → read it and ask the user:
        *   *"I see an active session: [Session Name] — Status: [Status]. Resume it or start a new one?"*
        *   If **resume** → read the session file, pick up from **Log** and **Objectives**, skip to step 8.
        *   If **new** → proceed to step 4.

4.  **Ask for Session Name and Mode**:
    *   Ask: *"What are we working on today?"* (e.g. "Offline Robustness Audit", "Jules Delegation")
    *   Determine **Mode** based on the task:
        *   `Planning` — architecture, research, design decisions
        *   `Building` — implementation, code changes
        *   `Delegation` — dispatching work to Jules or another agent
        *   `Audit` — reviewing, debugging, investigating

5.  **Determine Agent and Workspace**:
    *   **Agent**: Identify who is running this session (e.g. Antigravity, Jules, sinyage).
    *   **Workspace**: Is this session touching multiple repos? → Set `Workspace: TRUE`, otherwise `FALSE`.
    *   Use the **Agent Delegation Decision Framework** in `memory.md` to confirm the right agent for this task.

6.  **Determine Branch Strategy**:
    *   **Local Agent** → Create and switch to branch `users/[SafeID]/[SessionName]`.
    *   **Web Agent (Jules/Antigravity)** → Stay on current branch. Do **NOT** create branches.

7.  **Create Session File**:
    *   Create `.rokct/sessions/[YYYY-MM-DD]_@[Agent]_[SessionName].md` with the following header:

    ```markdown
    # Session: [SessionName]
    **Branch**: users/[SafeID]/[SessionName] (or current branch for Web Agents)
    **Date**: [YYYY-MM-DD]
    **User**: [Name from memory.md]
    **ID**: [SafeID from memory.md]
    **Mode**: [Planning | Building | Delegation | Audit]
    **Status**: Active
    **Workspace**: [TRUE | FALSE]
    **Repos Touched**: [List repos as they are touched]

    ## Objectives
    - [ ] [Primary goal]

    ## Log
    *   **[[YYYY-MM-DD]]**: **[START]**: [Session goal in one line.]
    ```

8.  **Update Active Session Pointer**:
    *   Overwrite `.rokct/active_session.txt` with:

```text
# Active Session: [SessionName]
    Mission: [One line goal]
    Status: IN PROGRESS
    Last Action: [To be updated as work progresses]
    Agent: [Agent Name]
    ```

9.  **Apply Checkpoint Policy**:
    *   Read **Checkpoint Policy** from `.rokct/memory.md`.
    *   If `Frequent` → commit progress after every major task automatically.
    *   If `Manual` → only commit when the user asks.

10. **Begin Work**:
    *   Confirm session is active to the user.
    *   Example: *"Session started: Offline Robustness Audit. Let's go, Ray."*
    *   Proceed with the task.
