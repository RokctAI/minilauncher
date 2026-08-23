# API Reference: quotation_link

Source file: `tender/frappe/src/quotation_link.py`

## Module Description

SOFT integration between Tender Bid and the erp module's Quotation.

The erp module (forked ERPNext living in the pay repo) is OPTIONAL at compose
time, so every touchpoint here is guarded by ``frappe.db.exists("DocType",
"Quotation")`` and no erp file is ever modified:

- ``ensure_quotation_tender_field`` adds a ``tender_bid`` Custom Field to
  Quotation in guarded code (after_install hook + weekly sweep), NOT as a
  custom-field fixture - a fixture would break install on benches without
  the erp module. Idempotent; a no-op wherever Quotation does not exist.
- ``sync_quotation_link`` is a Quotation doc_event registered
  unconditionally in the manifest (hooks cannot be conditional; frappe
  consults doc_events by doctype name at runtime, so an entry for an absent
  doctype simply never fires). It keeps Tender Bid.quotation - the CANONICAL
  side of the link - in sync when a user picks a bid on the Quotation form
  in ERP, so the pack generator always finds pricing from the bid.

Deterministic and additive only. No AI.

## Documented Module Functions

### `def quotation_doctype_available()`

True when the erp module's Quotation doctype exists on this bench.

### `def ensure_quotation_tender_field()`

Creates the Quotation.tender_bid Custom Field where erp is composed.

Guarded, idempotent, additive: runs from after_install and the weekly
scheduler so a bench that gains the erp module later still picks the
field up without a reinstall. Never touches the erp module's own files.

### `def sync_quotation_link(doc, method=None)`

Quotation validate doc_event: Quotation.tender_bid -> Tender Bid.quotation.

No-ops when the erp module is absent (the event then never fires anyway),
when the custom field has not been created yet, or when the named bid
does not exist. Latest linked quotation wins on the bid.
