package app.gabbro.gabbro

import android.content.Context

/**
 * Public Suffix List matcher (publicsuffix.org). Computes the registrable domain
 * (eTLD+1) of a host so unrelated sites under a shared suffix never collide
 * (bbc.co.uk vs hsbc.co.uk). Replaces the old naive "last two labels" rule that
 * collapsed both to co.uk (audit F-10). The list is vendored at
 * assets/public_suffix_list.dat — see docs/MAINTENANCE.md for the refresh procedure.
 */
class PublicSuffixList private constructor(
    private val rules: Set<String>,      // normal + wildcard (e.g. "co.uk", "*.ck")
    private val exceptions: Set<String>, // exception rules, '!' stripped (e.g. "www.ck")
) {

    /**
     * Registrable domain (public suffix + one label) of [host], or null when [host]
     * is itself a public suffix (no registrable label) or blank/malformed.
     * [host] must already be a clean lowercase hostname (no scheme, port, or path).
     */
    fun registrableDomain(host: String): String? {
        if (host.isBlank()) return null
        val labels = host.split(".")
        if (labels.any { it.isEmpty() }) return null
        val suffixLabelCount = publicSuffixLabelCount(labels)
        if (labels.size <= suffixLabelCount) return null
        return labels.subList(labels.size - suffixLabelCount - 1, labels.size).joinToString(".")
    }

    /** True only for a host that matches a real listed rule (not the implicit "*"). */
    fun isListedSuffix(host: String): Boolean = rules.contains(host.lowercase())

    /** Label count of the prevailing public suffix; implicit "*" yields 1. */
    private fun publicSuffixLabelCount(labels: List<String>): Int {
        // Exception rules win outright; the longest (leftmost start) matches first.
        for (i in labels.indices) {
            val suffix = labels.subList(i, labels.size).joinToString(".")
            if (exceptions.contains(suffix)) return labels.size - i - 1
        }
        var best = -1
        for (i in labels.indices) {
            val suffixLabels = labels.subList(i, labels.size)
            if (rules.contains(suffixLabels.joinToString("."))) {
                best = maxOf(best, suffixLabels.size)
            }
            // Wildcard "*.<rest>" consumes labels[i]; <rest> is labels after it.
            if (i + 1 < labels.size) {
                val wildcard = "*." + labels.subList(i + 1, labels.size).joinToString(".")
                if (rules.contains(wildcard)) best = maxOf(best, suffixLabels.size)
            }
        }
        // No rule matched: the implicit "*" rule makes the last label the suffix.
        return if (best == -1) 1 else best
    }

    companion object {
        private const val ASSET_NAME = "public_suffix_list.dat"

        fun fromAsset(context: Context): PublicSuffixList =
            context.assets.open(ASSET_NAME).bufferedReader().use { parse(it.readLines()) }

        fun parse(lines: List<String>): PublicSuffixList {
            val rules = HashSet<String>()
            val exceptions = HashSet<String>()
            for (raw in lines) {
                val line = raw.trim()
                if (line.isEmpty() || line.startsWith("//")) continue
                val rule = line.substringBefore(' ').lowercase()
                if (rule.startsWith("!")) exceptions.add(rule.substring(1)) else rules.add(rule)
            }
            return PublicSuffixList(rules, exceptions)
        }
    }
}
