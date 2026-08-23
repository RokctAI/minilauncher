# API Reference: __init__

Source file: `tender/frappe/src/compliance/__init__.py`

## Module Description

Deterministic SA-tender compliance layer.

Every check in this package is a field comparison, a date window, or a set
membership test. The rules themselves ship as Tender Compliance Rule /
Tender Form Regime fixture records (tender/frappe/fixtures/), mapped from
tender/SA-Tender-Completion-Guide.md - updating a rule means editing a
fixture JSON (or the record in desk), never code. There is no AI anywhere
in this pipeline.
