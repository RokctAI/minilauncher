# SOP: Self-Correction

**Trigger**: A tool fails, an error occurs, or the user corrects the agent.

## Procedure
1.  **Stop**: Do not rush to the next step.
2.  **Analyze**:
    *   What went wrong?
    *   Did I ignore a rule?
3.  **Record**:
    *   Update `system/memory.md` if this is a new lesson.
4.  **Retry**:
    *   Try a different approach (do not repeat the exact same failure).
5.  **Ask**:
    *   Only if 3 retries fail, ASK the user with a specific context.
