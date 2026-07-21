"""AI signature field detection — locate signature areas in a document.

Uses heuristics + optional AI vision to identify where signatures should be
placed on a form/contract. Detects:
- Explicit signature lines (______ or "Unterschrift" / "Signature" labels)
- Date+signature pairs ("Datum, Unterschrift")
- Witness/notary signature blocks
- "Sign here" markers

This runs as part of the field detection pipeline and produces DetectedField
entries with type=signature positioned at the identified locations.
"""

import re


class SignatureDetector:
    """Detect signature fields from OCR text and line positions."""

    # Labels that indicate a signature field (multilingual).
    _SIGNATURE_LABELS = {
        "en": ["signature", "sign here", "signed", "authorized signature",
               "witness", "notary"],
        "de": ["unterschrift", "unterschriften", "ort, datum, unterschrift",
               "datum, unterschrift", "hier unterschreiben", "unterzeichner"],
        "fr": ["signature", "signer ici", "signataire"],
        "ar": ["التوقيع", "توقيع"],
        "ku": ["واژۆ", "ئیمزا"],
    }

    # Patterns that look like signature lines.
    _LINE_PATTERNS = [
        re.compile(r'_{5,}'),           # _____ (5+ underscores)
        re.compile(r'\.{5,}'),          # ..... (5+ dots)
        re.compile(r'-{5,}'),           # ----- (5+ dashes)
        re.compile(r'x{3,}', re.I),    # xxx (sign-here marker)
    ]

    def detect_from_ocr_lines(
        self,
        lines: list[dict],  # [{text, x, y, w, h}] normalised
    ) -> list[dict]:
        """Detect signature fields from OCR-extracted text lines.

        Args:
            lines: OCR text lines with normalised bounding boxes.

        Returns:
            List of detected signature positions [{x, y, w, h, label, confidence}].
        """
        results = []
        all_labels = set()
        for lang_labels in self._SIGNATURE_LABELS.values():
            all_labels.update(lang_labels)

        for line in lines:
            text = line.get("text", "").strip().lower()
            x = line.get("x", 0.0)
            y = line.get("y", 0.0)
            w = line.get("w", 0.0)
            h = line.get("h", 0.0)

            confidence = 0.0

            # Check for signature labels.
            for label in all_labels:
                if label in text:
                    confidence = max(confidence, 0.9)
                    break

            # Check for signature line patterns.
            if confidence < 0.5:
                for pattern in self._LINE_PATTERNS:
                    if pattern.search(text):
                        confidence = max(confidence, 0.7)
                        break

            # Check for "Datum" (date) near the line — often paired with signature.
            if confidence < 0.5 and any(
                d in text for d in ["datum", "date", "ort,", "place,"]
            ):
                confidence = max(confidence, 0.5)

            if confidence >= 0.5:
                results.append({
                    "x": x,
                    "y": y + h,  # signature goes BELOW the label/line
                    "w": max(w, 0.2),  # minimum width for a signature
                    "h": 0.04,  # standard signature height
                    "label": text[:50],
                    "confidence": confidence,
                    "type": "signature",
                })

        return results

    def is_signature_label(self, text: str) -> bool:
        """Quick check if a text string is a signature-related label."""
        lower = text.strip().lower()
        all_labels = set()
        for lang_labels in self._SIGNATURE_LABELS.values():
            all_labels.update(lang_labels)
        return any(label in lower for label in all_labels)


# Singleton
signature_detector = SignatureDetector()
