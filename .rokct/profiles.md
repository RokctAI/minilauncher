# Profile: Web Agent (Restricted)

**Context**: You are running in a Cloud/Web Environment (e.g., Codespaces, Agent UI).
**Capabilities**:

* Can run complex shell commands? **MAYBE** (Assume Restricted).
* Can run `git` commands? **NO** (Do not push manually).
* Can edit files freely? **YES**

**Rules**:

1. **No Git Pushes**: Do not try to `git push`. Trust the Platform to handle sync.
2. **Safety**: Verify edits by reading the file back.
