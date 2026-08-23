# API Reference: artifact_expiry

Source file: `tender/frappe/src/compliance/artifact_expiry.py`

## Documented Module Functions

### `def sweep_compliance_artifacts()`

cron hook
Weekly scheduled task (module manifest): recomputes every Compliance
Artifact's Green/Amber/Expired status from its dates and emails the
owning user about artifacts that changed to Amber or Expired - but only
users who opted in via User.receive_tender_notifications. Runs on the
control hub only. Date arithmetic only, no AI.
