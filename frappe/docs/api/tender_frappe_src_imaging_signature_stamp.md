# API Reference: signature_stamp

Source file: `tender/frappe/src/imaging/signature_stamp.py`

## Module Description

Deterministic signature/initials background stripping (Pillow only, no AI).

A signature scan arrives as dark ink strokes on a solid background - white
paper is the recommended path, but any solid color works. Stamping that scan
onto a form as-is prints a solid box over the form's own lines, so the SDK
strips the background once at upload:

1. the background color is detected as the per-channel median of the four
   corner pixels (a signature never reaches all four corners of a sensible
   scan);
2. each pixel's distance from the background is the maximum per-channel
   difference;
3. pixels within ``tolerance`` of the background go fully transparent, pixels
   beyond ``2 * tolerance`` stay fully opaque, and the band between ramps
   linearly so anti-aliased stroke edges keep a soft edge.

Everything is pure arithmetic on pixel values - the same input bytes always
produce the same output bytes.

## Documented Module Functions

### `def strip_background(image_bytes, tolerance=DEFAULT_TOLERANCE)`

Returns the image as transparent-background PNG bytes.

Ink strokes keep their original color; near-background pixels become
transparent. Existing transparency in the source is preserved (the
computed alpha never exceeds the original alpha).
