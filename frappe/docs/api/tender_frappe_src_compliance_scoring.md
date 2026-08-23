# API Reference: scoring

Source file: `tender/frappe/src/compliance/scoring.py`

## Module Description

Deterministic 80/20 - 90/10 preference-point arithmetic.

Constants live in the SCORE-SYSTEM / SCORE-PRICE-FORMULA fixture records
(Tender Compliance Rule.params), so procurement-threshold changes are data
edits, not code changes. Formulas (PPPFA regulations, guide section 4.3/6.3):

        Ps = X * (1 - (Pt - Pmin) / Pmin)   with X in {80, 90}

and, for disposal/leasing/income-generating tenders where the highest
acceptable offer scores full points, the inverted form:

        Ps = X * (1 + (Pt - Pmax) / Pmax)

Where functionality is scored it is an elimination gate applied before
price/preference; its threshold is per-tender data recorded on the bid
(corpus range roughly 40-83%), never a code constant.

## Documented Module Functions

### `def preference_system_for_value(estimated_value, params=None)`

Classifies a bid value as '80/20', '90/10' or 'Straddling'.

Empty value -> "" (not classified). Values within the configured straddle
band around the threshold return 'Straddling' - some buyers fix the system
only after opening, so a straddling price must survive both systems.

### `def price_points(bid_price, lowest_price, points_base)`

Ps = X * (1 - (Pt - Pmin) / Pmin), clamped at >= 0. Pure arithmetic.

### `def price_points_inverted(bid_price, highest_price, points_base)`

Ps = X * (1 + (Pt - Pmax) / Pmax), clamped at >= 0. Pure arithmetic.

The disposal/leasing/income-generating variant: the highest acceptable
offer takes the full base and lower offers score proportionally less.

### `def passes_functionality(self_score, threshold)`

Elimination gate: True when no threshold is recorded, or score >= it.
