#!/usr/bin/env python3
"""
Generate passphrase wordlists for Gabbro.

Aspell-sourced (GPL-compatible): sv, da, nb, fi, sl, pl, ru, hu, cs
Licensed downloads:
  pt  — thoughtworks/dadoware          (plain words, MIT-ish)
  et  — agreinhold/Diceware-word-lists (tab NNNNN\tword, CC-BY-4.0)
  sk  — jtomori/diceware_slovak        (space NNNNN word, MIT)
  bg  — assenv/diceware-wordlist-bg    (space NNNNN word, CC-BY-4.0)
  el  — kalpetros/greek-dictionary     (space NNNNN word, MIT, Greek only)
  uk  — agreinhold/Diceware-word-lists (tab NNNNN\tword\tRomanized, MIT, skip header)
Frequency corpora (CC-BY-SA 4.0, hermitdave/FrequencyWords):
  hr  — hr_50k.txt  (7776 words, freq_word0 format)
  lt  — lt_50k.txt  (7776 words, freq_word0 format)
  lv  — lv_50k.txt  (7776 words, freq_word0 format)
  kk  — kk_full.txt (4311 words — full corpus; freq_word0 format)

Run from the repo root: python3 rust/scripts/gen_wordlists.py
"""

import re
import random
import subprocess
import sys
import urllib.request
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
TARGET = 7776
SEED = 42

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def aspell_candidates(lang: str, pattern: str) -> list[str]:
    result = subprocess.run(
        ["aspell", "-d", lang, "dump", "master"],
        capture_output=True, text=True, errors="ignore",
    )
    words: set[str] = set()
    for line in result.stdout.splitlines():
        word = line.split("/")[0].lower().strip()
        if re.fullmatch(pattern, word):
            words.add(word)
    return sorted(words)


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode("utf-8-sig")   # utf-8-sig strips BOM


def sample(candidates: list[str], n: int = TARGET) -> list[str]:
    if len(candidates) < n:
        print(f"    WARNING: only {len(candidates)} candidates, using all", file=sys.stderr)
        return sorted(candidates)
    rng = random.Random(SEED)
    return sorted(rng.sample(candidates, n))


def save(lang: str, words: list[str]) -> None:
    path = ASSETS / f"wordlist_{lang}.txt"
    path.write_text("\n".join(words) + "\n", encoding="utf-8")
    print(f"  {lang}: {len(words)} words  →  {path.name}")


# ---------------------------------------------------------------------------
# Aspell languages
# ---------------------------------------------------------------------------

ASPELL = {
    # lang : regex pattern (after lowercase, stripped flags)
    "sv": r"[a-zåäö]{4,12}",
    "da": r"[a-zæøå]{4,12}",
    "nb": r"[a-zæøå]{4,12}",
    "fi": r"[a-zäöå]{4,12}",
    "sl": r"[abcčdefghijklmnoprsštuvzž]{4,12}",  # explicit — excludes q w x y
    "pl": r"[a-ząćęłńóśźż]{4,12}",
    "ru": r"[а-яё]{4,12}",
    "hu": r"[a-záéíóöőúüű]{4,12}",
    "cs": r"[a-záčďéěíňóřšťúůýž]{4,12}",
    "el": r"[α-ωάέήίόύώΐΰϊϋ]{4,12}",  # Modern Greek lowercase
}


def gen_aspell() -> None:
    print("Generating from Aspell:")
    for lang, pat in ASPELL.items():
        candidates = aspell_candidates(lang, pat)
        words = sample(candidates)
        save(lang, words)


# ---------------------------------------------------------------------------
# Downloaded languages
# ---------------------------------------------------------------------------

BASE_AGREINHOLD = "https://raw.githubusercontent.com/agreinhold/Diceware-word-lists/master"

DOWNLOADS: dict[str, tuple[str, str, str | None]] = {
    # lang: (url, format-key, post-filter regex or None)
    "pt": (
        "https://raw.githubusercontent.com/thoughtworks/dadoware/master/7776palavras.txt",
        "plain",
        None,
    ),
    "et": (
        f"{BASE_AGREINHOLD}/diceware_%20estonian.txt",
        "tab_field1",          # NNNNN\tword
        r"[a-zäöüõšž]{3,12}", # strips multi-word phrases, digits, symbols
    ),
    "sk": (
        "https://raw.githubusercontent.com/jtomori/diceware_slovak/master/diceware_sk_5_rolls",
        "space_field1",        # NNNNN word
        None,
    ),
    "bg": (
        "https://raw.githubusercontent.com/assenv/diceware-wordlist-bg/main/wordlist_utf_bg.asc",
        "space_field1",        # NNNNN word  (Cyrillic)
        r"[а-я]{3,12}",        # strips symbols and numbers, Cyrillic only
    ),
    # el is generated from aspell-el (see ASPELL dict above)
    # Frequency corpora (CC-BY-SA 4.0, hermitdave/FrequencyWords)
    "hr": (
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/hr/hr_50k.txt",
        "freq_word0",
        # Explicit Croatian alphabet — excludes q w x y which are not Croatian letters
        r"[abcčćđefghijklmnoprsštuvzž]{4,12}",
    ),
    "lt": (
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/lt/lt_50k.txt",
        "freq_word0",
        # Explicit Lithuanian alphabet — y IS a valid Lithuanian letter; excludes q w x
        r"[aąbcčdeęėfghiįyjklmnoprsštuųūvzž]{4,12}",
    ),
    "lv": (
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/lv/lv_50k.txt",
        "freq_word0",
        # Explicit Latvian alphabet — excludes q w x y which are not Latvian letters
        r"[aābcčdeēfgģhiījkķlļmnņoprsštuūvzž]{4,12}",
    ),
    "kk": (
        # Only ~4311 words available; full corpus used (no sampling needed)
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/kk/kk_full.txt",
        "freq_word0",
        r"[а-яёәғқңөұүһі]{4,12}",
    ),
    "uk": (
        f"{BASE_AGREINHOLD}/diceware_ua_uk_long.txt",
        "tab_field1_uk",       # header + NNNNN\tword\tRomanized
        None,
    ),
}

GREEK_RE = re.compile(r"[Ͱ-Ͽἀ-῿]+")


def parse(content: str, fmt: str) -> list[str]:
    words: list[str] = []
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if fmt == "plain":
            words.append(line)
        elif fmt == "tab_field1":
            parts = line.split("\t")
            if len(parts) >= 2:
                words.append(parts[1].strip())
        elif fmt == "space_field1":
            parts = line.split()
            if len(parts) >= 2:
                words.append(parts[1])
        elif fmt == "space_field1_greek":
            parts = line.split()
            if len(parts) >= 2:
                word = parts[1].lower()
                if GREEK_RE.fullmatch(word):
                    words.append(word)
        elif fmt == "tab_field1_uk":
            parts = line.split("\t")
            # skip header row (first field is "index")
            if len(parts) >= 2 and parts[0].strip() != "index":
                words.append(parts[1].strip())
        elif fmt == "freq_word0":
            # hermitdave/FrequencyWords: "word count" — word is first field
            parts = line.split()
            if parts:
                words.append(parts[0].lower())
    return [w for w in words if w]


def gen_downloads() -> None:
    print("Downloading licensed wordlists:")
    for lang, (url, fmt, post_filter) in DOWNLOADS.items():
        content = fetch(url)
        words = parse(content, fmt)
        if post_filter:
            pat = re.compile(post_filter)
            words = [w for w in words if pat.fullmatch(w)]
        if len(words) != TARGET:
            words = sample(words)
        save(lang, words)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    ASSETS.mkdir(exist_ok=True)
    gen_aspell()
    gen_downloads()
    print("Done.")
