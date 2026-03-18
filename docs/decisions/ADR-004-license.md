# ADR-004 — Project Licence: GPL-3.0-only

**Date:** 2026-03-18
**Status:** Accepted

---

## Context

Gabbro needs a licence before its first public commit. The choice
carries long-term consequences for the project's openness, the
author's protections, and the monetisation model. The following
requirements were identified:

1. The project must be Free and Open Source Software (FOSS)
2. The author's work must be protected — attribution is mandatory
3. Copyleft must be enforced — anyone distributing modified versions
   must share their changes under the same terms
4. The licence must provide standard liability protection
5. Commercial use and monetisation by the author must remain possible

---

## Decision

Gabbro is licensed under the **GNU General Public License v3.0 only**,
identified by the SPDX identifier `GPL-3.0-only`.

The SPDX identifier `GPL-3.0-only` (as opposed to `GPL-3.0-or-later`)
means the project is licensed under GPL-3.0 and **only** GPL-3.0.
Future GPL versions do not automatically apply. This is a conscious
choice to retain full control over the project's licensing future.

---

## Why not LGPL?

LGPL (Lesser GPL) was the original working assumption, carried over
from the author's prior open source work (wellpathpy, a Python
library). On reflection, LGPL is designed for **libraries** — code
that other developers link against. Its specific mechanics (allowing
proprietary applications to link against the library without
triggering copyleft) are not relevant to Gabbro, which is a
standalone **application**.

GPL-3.0 is the appropriate copyleft licence for an application. It is
what comparable security-focused FOSS projects use, including
KeePassXC.

---

## Why GPL-3.0 satisfies all requirements

| Requirement | How GPL-3.0 satisfies it |
|---|---|
| FOSS | GPL-3.0 is OSI-approved and FSF-endorsed |
| Attribution | All distributions must preserve copyright notices |
| Copyleft / share-alike | Modified versions must be released under GPL-3.0 |
| Liability protection | Standard no-warranty and limitation-of-liability clauses |
| Monetisation | Selling GPL software is explicitly permitted; the author retains copyright |

### On monetisation

GPL-3.0 does not prevent commercial use or charging for the software.
It prevents recipients from being denied the freedoms the licence
grants — including the right to redistribute. The freemium model
planned for Gabbro (free core, premium features) is compatible with
GPL-3.0, provided premium features are structured carefully:

- Premium features delivered as a **service** (not distributed
  software) are not subject to GPL copyleft at all
- Premium features distributed as a **separate proprietary layer**
  that does not incorporate GPL code require legal care and are best
  reviewed with a lawyer before implementation

This is noted here as a flag for future design decisions, not a
blocker for the current licence choice.

### On regulatory liability (e.g. California age verification)

No open source licence insulates a distributor from regulatory
obligations in jurisdictions where they choose to distribute.
GPL-3.0's no-warranty clause provides the strongest standard
protection available, but jurisdiction-specific legal compliance
remains the responsibility of anyone distributing the software.
This is a distribution decision, not a licence decision.

---

## Why GPL-3.0-only and not GPL-3.0-or-later

`GPL-3.0-or-later` would allow future versions of the GPL (should
the FSF publish them) to automatically apply to this code. This
cedes some control over the project's licensing future to the FSF.

`GPL-3.0-only` retains full control with the author. If a future
GPL version is published and its terms are desirable, the author
can choose to relicence at that point. This is the more conservative
and deliberate choice.

---

## Alternatives Considered

| Licence | Reason rejected |
|---|---|
| LGPL-3.0 | Designed for libraries, not applications; copyleft weaker than needed |
| MIT / Apache 2.0 | Permissive — no copyleft, no share-alike requirement |
| AGPL-3.0 | Stronger than GPL (covers network use); may complicate monetisation; worth revisiting if a sync server is ever built |
| Proprietary | Contradicts FOSS intent |

---

## Note on legal advice

This ADR documents the author's reasoning and intent. It is not
legal advice. Licence choice for a security application with
monetisation intent is worth reviewing with a qualified lawyer,
particularly before the first public release or any commercial
activity.

---

## References

- GNU GPL-3.0: https://www.gnu.org/licenses/gpl-3.0.en.html
- GPL FAQ (monetisation): https://www.gnu.org/licenses/gpl-faq.html
- SPDX identifier reference: https://spdx.org/licenses/GPL-3.0-only.html
- KeePassXC licence (GPL-3.0): https://github.com/keepassxreboot/keepassxc
