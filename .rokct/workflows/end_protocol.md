# SOP: End Rokct Protocol Session

**Trigger**: You are finishing work on a project and want to clean up the scaffold files before archiving or switching contexts.

## Procedure

1.  **Run End Protocol Script**:
    ```bash
    python profiles/local/end_protocol.py
    ```
    This will:
*   Delete `skills/` if it matches the protocol template exactly (pristine).
*   Delete `workflows/` if it matches the protocol template exactly (pristine).
*   Keep `.gitignore` as-is.
    *   Keep any working files that the agent modified (e.g. `memory.md` with new content).
