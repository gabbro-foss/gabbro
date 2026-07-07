# Is Gabbro "vibe-coded"? — Notes on the AI development process

## Why this document exists

Gabbro is a cryptography project whose code was, to date, written entirely by
AI (various Claude instances — initially Sonnet, now Opus — via claude.ai and
Claude Code). It is fair, and healthy, to ask whether that makes Gabbro the kind
of thing a security-conscious distribution would refuse to ship. This document
answers that honestly, including where the answer is uncomfortable.

The prompt is a line from a Gentoo developer (mgorny), *Why Gentoo?*,
28 May 2026 (`blogs.gentoo.org/mgorny/2026/05/28/why-gentoo/`):

> "we try to keep the worst offenders (like copywashed chardet or vibe-coded
> cryptography software) at bay."

The post doesn't elaborate on the phrase, but the surrounding argument is clear
and worth taking seriously: Gentoo restricts LLM contributions because it values
code that is **human-written, reviewable, and trustworthy** — and cryptographic
software demands more scrutiny than AI-generated code can be assumed to carry.

That is a legitimate concern, not FUD. The right response is to be precise about
what "vibe-coded" means and then measure Gabbro against it without flinching.

---

## What "vibe coding" actually means

The term comes from Andrej Karpathy (February 2025). His own description is the
useful definition: *"fully give in to the vibes… forget that the code even
exists,"* accept what the model emits, paste errors back without reading them,
and never review the diff. The defining trait is the **abdication of
understanding and review** — the human stops being an engineer and becomes a
conduit. Karpathy was explicit that this is fine for a throwaway weekend project
and not how you build something people depend on.

So "AI wrote the code" and "the code was vibe-coded" are not the same claim.
Vibe coding is defined by the *absence of two things*:

1. **Human design and direction** — was there a human making genuine
   architectural and engineering decisions, or did the objective get handed to a
   model wholesale?
2. **Human understanding and review** — is the output read, challenged, tested,
   and verified, or accepted on faith?

A project can fail either test. Let's take them separately, because Gabbro's
honest answer differs between the two.

---

## Test 1 — human design and direction: Gabbro passes clearly

This is not close. The architect (Rob) drove every consequential design decision
*before* the code existed, and the repository proves it. The same evidence
catalogued in `AI_AUTHORSHIP_AND_IP.md` applies here:

- the security boundary — secrets never cross the Flutter/Rust bridge in
  plaintext, Rust owns all decrypted material in memory;
- the crypto stack and the hybrid-PQC "belt and suspenders" rationale
  (Argon2id → X25519 + ML-KEM-1024 → HKDF → AES-256-GCM);
- the FIDO2/YubiKey-only authentication model, and the deliberate decision *not*
  to ship TOTP;
- the vault file format, the session model, the importer scope (three, not N);
- GPL-3.0-only and the reasoning behind it.

These are recorded in the ADRs, `ARCHITECTURE.md`, and the commit
history — documentation that predates the generated code. That is the opposite of
"forgetting the code exists." The architect specifies structure; the model fills
it in. The direction is unambiguously human.

---

## Test 2 — understanding and review: this is where honesty is required

Here the answer is more nuanced, and pretending otherwise would defeat the point
of the document.

The architect is a competent Python practitioner but a self-described beginner in
the languages Gabbro is actually written in — Rust, Dart/Flutter, and Kotlin. He
did not hand-write the implementation and cannot, today, line-by-line audit a
Rust constant-time comparison or a Kotlin CTAP2 session the way a specialist
could. If "reviewable by the author, unaided" were the bar, Gabbro would not
clear it for every file.

What stands in for that, deliberately and not by accident, is a stack of process
controls that make the code reviewable and falsifiable *by something other than
one expert's eyes*:

- **TDD from day one.** Tests are written first and serve as executable
  specifications. Code that "looks plausible" but is wrong fails a test. This is
  precisely the check vibe coding throws away.
- **Tests as the safety net for non-experts.** The backward-compatibility
  fixture harness exists *because* a real incident occurred: in June 2026 a model
  change bricked the live vault (data loss). The response was not "trust harder"
  but to freeze golden vaults from each format version and prove every future
  build can still read them — a release gate that does not depend on anyone
  reading the diff correctly.
- **An explicit AI security audit** (`AI_SECURITY_AUDIT.md`) with per-finding
  tracking. Every tracked finding is now addressed or by-design.
- **A standing rule that the cryptography is treated as unverified until it is
  either fixed in-house with tests or reviewed by a human expert.** The one
  finding that needed design judgment — the hybrid combiner (F-03) — was hardened
  in-house at VERSION 8 (transcript binding), proven by the backward-compat gate
  and hardware migration tests before shipping; external cryptographer review
  remains welcome as defence-in-depth but is no longer a blocking gate. That is
  the inverse of vibe coding: the project verifies before it ships.
- **Honest alpha labelling.** Releases ship with: *"The cryptographic
  implementation has not undergone external review. Do not store passwords you
  cannot afford to lose."* No false confidence is sold to users.

So the fair statement is: Gabbro is **AI-written but not vibe-coded**, because the
two things vibe coding discards — design direction and review — are both present.
Direction is fully human; review is real but *mediated* — through tests, an audit
process, incident-driven safety nets, and a standing invitation to external
cryptographer review — rather than resting on the author's unaided mastery of four
languages.

---

## On the specific worry about cryptography

Gentoo's concern is sharpest for crypto, and rightly. Two things matter here:

1. **Gabbro does not roll its own primitives.** It composes vetted,
   widely-reviewed implementations (the RustCrypto family and equivalents:
   Argon2, ML-KEM, AES-GCM, X25519, HKDF). The dangerous failure mode for an
   AI-assisted project would be a hand-rolled cipher or a homemade constant-time
   routine. Gabbro's novel surface is *composition* — how vetted pieces are wired
   together — not primitive implementation.

2. **The composition is exactly what the audit scrutinised most.** The combiner
   construction, transcript binding, and KDF wiring are the things the security
   audit targeted; the one open design question (F-03) was hardened in-house and
   pinned by the backward-compat gate + hardware tests. The project's posture is
   to verify its own crypto wiring with frozen-fixture and migration gates and to
   keep external specialist review open — which is the responsible reading of
   Gentoo's warning, not a contradiction of it.

A reasonable critic could still say: "until that external review happens, I
wouldn't ship it." That is a defensible position, and it is *the same position
Gabbro takes about itself* — hence the alpha disclaimer and the pre-v1 security
gates in the Bikeshed. The disagreement, if any, is about timing, not principle.

---

## The honest bottom line

- By the meaningful definition of the term, Gabbro is **not vibe-coded**: it has
  genuine human architecture and a review/verification process that vibe coding
  by definition lacks.
- It *is* a project whose code was AI-written and whose architect cannot
  personally audit every line — and the right answer to that is not to hide it
  but to lean on tests, audits, incident-driven safety nets, and a human-expert
  crypto gate before v1. All of which exist and are documented.
- The crypto-specific worry is mitigated by not inventing primitives and by
  explicitly treating the composition as unreviewed until a specialist confirms
  it.

The most durable answer to "is this trustworthy?" is the same as the answer to
the IP question in `AI_AUTHORSHIP_AND_IP.md`: thorough, honest documentation of
human decisions and known limits, maintained as good engineering practice rather
than as a marketing claim.

---

*This document was written collaboratively by Rob (project owner and architect)
and Claude (Opus 4.8, AI development partner) on 8 June 2026.*
