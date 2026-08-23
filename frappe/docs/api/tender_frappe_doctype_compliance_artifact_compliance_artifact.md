# API Reference: compliance_artifact

Source file: `tender/frappe/doctype/compliance_artifact/compliance_artifact.py`

## Classes

### class `ComplianceArtifact`

#### Documented Internal Methods

##### `compute_status(self)`

Deterministic traffic light from valid_until vs today.

Expired: valid_until is in the past.
Amber:   valid_until falls inside the renewal window.
Green:   everything else (including artifacts with no expiry date).
