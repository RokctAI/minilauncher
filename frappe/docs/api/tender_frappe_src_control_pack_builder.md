# API Reference: pack_builder

Source file: `tender/frappe/src/control/pack_builder.py`

## Module Description

Deterministic bid-pack builder - the document half of the tender module.

Given a Tender Bid's form regime, the fixture-shipped Tender Form Template
records, the bidder's Tender Business Profile and the bid's cached tender
data, this module assembles a ready-to-print preparation pack:

- every field that CAN be pre-filled is filled from the profile or the bid;
- tender-specific fields render as clearly marked USER INPUT blanks with
  kill-note-derived guidance;
- signature/initials slots render as "Sign here" / "Initial here" markers,
  or - ONLY when the caller explicitly requests a signed pack - are stamped
  with the profile's background-stripped signature images (commissioner-of-
  oaths slots are never stamped: a commissioner must sign in person);
- the pack opens with a manifest cover (fill coverage, unresolved fields)
  and, when the bid still has open fatal compliance gates, a prominent
  warning page - never a silent pass.

Everything here is pure data transformation: dict/list in, dict/HTML out.
No frappe import, no AI, no network. Database access lives in the endpoint
(api/tenders/generate_bid_pack.py), which feeds this module plain dicts, so
the builder is unit-testable standalone.

Rendering choice: clean printable HTML (A4 print CSS, one form per page)
rather than server-side PDF - wkhtmltopdf availability on composed benches
is not verifiable at compose time, and browsers print this HTML to PDF
losslessly. The output is a single self-contained HTML document.

IMPORTANT product framing baked into the output: SA tender rules forbid
retyped/substituted forms at about a third of buyers, so the pack is a
preparation worksheet mirroring each official form field-for-field - the
user transcribes onto (or checks against) the OFFICIAL issued forms. Every
page carries that warning.

## Documented Module Functions

### `def is_filled(value)`

True when an auto-fill value is actually usable on a form.

### `def resolve_field(field, profile, bid_ctx)`

Resolves one template field row against the profile and bid context.

Returns the row dict extended with ``value`` and ``filled``. Signature
rows never carry a value - stamping is a rendering concern.

### `def build_form(requirement, template, profile, bid_ctx)`

Builds one form entry: resolved fields plus per-form fill accounting.

``requirement`` is the regime's Tender Form Requirement row (form_code,
form_name, mandatory, kill_note); ``template`` is the matching Tender
Form Template as a dict with a ``fields_table`` list, or None when no
template exists for the code (the form still gets a guided worksheet
page driven by the requirement's kill note alone).

### `def build_pack`

```python
def build_pack(
  regime,
  templates_by_code,
  profile,
  bid_ctx,
  gate_failures,
  signing=None
)
```

Assembles the full pack: ordered forms + manifest. Pure data in/out.

### `def render_pack_html(pack, bid_ctx, signing=None)`

Renders the assembled pack as one self-contained printable HTML doc.
