#!/usr/bin/env python3
"""Einheitentests für die Chrome-Richtlinie system/chrome/policies/zenos.json.

Geprüft wird die Datei selbst (gültiges JSON-Objekt ohne doppelte Schlüssel), das Format von AutofillSettings nach
dem Schema aus Googles Richtlinienliste (https://chromeenterprise.google/policies/#AutofillSettings), dass
Kreditkarten im Autofill auf beiden Wegen aus sind (AutofillCreditCardEnabled für Chrome vor 154, AutofillSettings
ab 154) und dass docs/sicherheit.md, ANLEITUNG.md und docs/module/m11.md dieselben Richtlinien nennen wie die Datei.

Ohne Netz, ohne Chrome und ohne das System anzufassen; läuft als root und als Benutzer gleich.
  python3 test/einheiten/chrome-richtlinie.test.py
"""

import json
import os
import re
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RICHTLINIE = os.path.join(WURZEL, "system", "chrome", "policies", "zenos.json")
SICHERHEIT = os.path.join(WURZEL, "docs", "sicherheit.md")
ANLEITUNG = os.path.join(WURZEL, "ANLEITUNG.md")
M11 = os.path.join(WURZEL, "docs", "module", "m11.md")

# Erlaubte Werte für blocked_types laut Googles Richtlinienliste (Stand 07.10.2026)
AUTOFILL_TYPES = {"contact_info", "payments", "identity_docs", "travel", "shopping", "all"}


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_policy():
    """Lädt die Richtlinie; doppelte Schlüssel sind ein Fehler (Chrome nähme stillschweigend den letzten)."""

    def without_duplicates(pairs):
        keys = [k for k, _ in pairs]
        duplicates = sorted({k for k in keys if keys.count(k) > 1})
        if duplicates:
            raise ValueError(f"doppelte Schlüssel: {', '.join(duplicates)}")
        return dict(pairs)

    with open(RICHTLINIE, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=without_duplicates)


def chrome_section(text):
    """Der Abschnitt «Chrome-Richtlinien» aus docs/sicherheit.md bis zur nächsten Überschrift zweiter Ebene."""
    match = re.search(r"^## Chrome-Richtlinien\n(.*?)(?=^## )", text, re.S | re.M)
    if not match:
        raise AssertionError("Abschnitt «## Chrome-Richtlinien» fehlt in docs/sicherheit.md")
    return match.group(1)


class PolicyFileTest(unittest.TestCase):
    def setUp(self):
        self.policy = load_policy()

    def test_is_object(self):
        self.assertIsInstance(self.policy, dict)

    def test_autofill_settings_format(self):
        # Schema aus Googles Liste: Liste von Objekten mit url_pattern (Text) und blocked_types (Liste aus der Aufzählung)
        entries = self.policy.get("AutofillSettings")
        self.assertIsInstance(entries, list)
        self.assertTrue(entries, "AutofillSettings ist leer")
        for entry in entries:
            self.assertIsInstance(entry, dict)
            self.assertEqual(set(entry), {"url_pattern", "blocked_types"})
            self.assertIsInstance(entry["url_pattern"], str)
            self.assertTrue(entry["url_pattern"])
            self.assertIsInstance(entry["blocked_types"], list)
            self.assertTrue(entry["blocked_types"])
            for kind in entry["blocked_types"]:
                self.assertIn(kind, AUTOFILL_TYPES)
            self.assertEqual(len(entry["blocked_types"]), len(set(entry["blocked_types"])))

    def test_credit_cards_blocked_everywhere(self):
        # Ab Chrome 154: payments (oder all) für das Muster «*», das auf jede Adresse passt
        entries = self.policy.get("AutofillSettings", [])
        everywhere = [e for e in entries if isinstance(e, dict) and e.get("url_pattern") == "*"]
        self.assertTrue(
            any({"payments", "all"} & set(e.get("blocked_types", [])) for e in everywhere),
            "AutofillSettings sperrt payments nicht für «*»",
        )

    def test_old_policy_kept_for_older_chrome(self):
        # Chrome vor 154 kennt AutofillSettings nicht; Google wertet die alte Richtlinie noch aus (chrome.*:63-).
        # Fliegt erst raus, wenn Googles Liste eine letzte Version nennt (docs/sicherheit.md).
        self.assertIs(self.policy.get("AutofillCreditCardEnabled"), False)


class DocumentationTest(unittest.TestCase):
    def setUp(self):
        self.policy = load_policy()
        self.section = chrome_section(read_text(SICHERHEIT))

    def test_block_matches_file(self):
        match = re.search(r"```json\n(.*?)\n```", self.section, re.S)
        self.assertIsNotNone(match, "JSON-Block fehlt im Abschnitt Chrome-Richtlinien")
        documented = json.loads(match.group(1))
        for key, value in documented.items():
            self.assertIn(key, self.policy, f"{key} steht in docs/sicherheit.md, aber nicht in zenos.json")
            self.assertEqual(self.policy[key], value, f"{key} weicht von docs/sicherheit.md ab")

    def test_rest_is_documented_telemetry(self):
        # Was nicht im Block steht, sind genau die genannten Abschaltungen von Telemetrie, alle false
        documented = json.loads(re.search(r"```json\n(.*?)\n```", self.section, re.S).group(1))
        match = re.search(r"Abschaltungen von Telemetrie:(.*?)alle `false`", self.section, re.S)
        self.assertIsNotNone(match, "Satz zu den Abschaltungen von Telemetrie fehlt")
        telemetry = set(re.findall(r"`([A-Za-z]+)`", match.group(1)))
        self.assertEqual(set(self.policy) - set(documented), telemetry)
        for key in telemetry:
            self.assertIs(self.policy[key], False, key)

    def test_counts_in_checklists(self):
        # Die Prüflisten nennen die Zahl, die chrome://policy zeigen soll
        count = len(self.policy)
        pattern = r"chrome://policy`(?: zeigt)? (\d+) (?:zenOS-)?Richtlinien"
        anleitung = re.findall(pattern, read_text(ANLEITUNG))
        m11 = re.findall(pattern, read_text(M11))
        self.assertTrue(anleitung, "Zahl der Richtlinien fehlt in ANLEITUNG.md")
        self.assertTrue(m11, "Zahl der Richtlinien fehlt in docs/module/m11.md")
        for found in anleitung + m11:
            self.assertEqual(int(found), count)


if __name__ == "__main__":
    unittest.main(verbosity=2)
