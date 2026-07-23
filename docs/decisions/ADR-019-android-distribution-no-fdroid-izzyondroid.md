# ADR-019: F-Droid and IzzyOnDroid Are Out for Android Distribution

## Status
Accepted

## Date
2026-07-23

## Context

Gabbro needs an Android distribution channel. Two F-Droid-family options were
evaluated; both are rejected.

**Main F-Droid.** F-Droid rebuilds each app from source on its own infrastructure
and re-signs the APK with F-Droid's key, not the developer's. For a password
manager this inserts F-Droid as a man-in-the-middle in the trust chain: the user
trusts F-Droid's build and key rather than a signature coming directly from us.
Updates are also slower (source rebuild plus publish queue). Keeping our own
signing key is a hard requirement, so this is a non-starter.

**IzzyOnDroid.** IzzyOnDroid is F-Droid-compatible but serves the developer's own
signed APKs from GitHub Releases (no rebuild, no re-sign), which solved the F-Droid
problem. Work began: fastlane metadata and 9 phone screenshots were prepared. It
was then found that IzzyOnDroid's App Inclusion Policy states they are "strongly
opposed to apps which are fully or in part created by generative AI tools." Gabbro
is substantially authored with generative AI, so an accurate inclusion request is
declined by that policy. Misrepresenting authorship to pass was rejected on
principle, and is impractical anyway since they review and ask. The submission was
abandoned.

## Decision

1. Do not pursue main F-Droid or IzzyOnDroid. Do not retry either.
2. Android distribution is:
   - Direct install of our own signed per-ABI APKs from GitHub Releases (baseline;
     signature-verification steps documented in the README).
   - Obtainium as the auto-update path: users point it at the GitHub repo and get
     updates built and signed by us, with no third-party curation. Documented in
     the README Android section. Releases are alpha (marked pre-release on GitHub),
     so users enable "Include prereleases" and set an ABI filter.
3. Accrescent is the only remaining store worth evaluating later (developer-signed,
   GrapheneOS-aligned, no known objection to AI-assisted apps, but small and
   selective). Not yet pursued.
4. The prepared `fastlane/metadata/` folder is kept for now (harmless, reusable if
   another store is adopted). The IzzyOnDroid-specific planning doc was deleted.

## References

- IzzyOnDroid App Inclusion Policy: https://izzyondroid.org/docs/general/AppInclusionPolicy/
- Obtainium: https://github.com/ImranR98/Obtainium
- Accrescent: https://accrescent.app/
