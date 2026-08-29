package app.gabbro.gabbro

import android.content.Context

/**
 * publicsuffix.org matcher, so unrelated sites under a shared suffix never
 * collide (bbc.co.uk vs hsbc.co.uk, audit F-10). Refresh procedure for the
 * vendored list: docs/MAINTENANCE.md.
 */
class PublicSuffixList private constructor(
    private val rules: Set<String>,
    private val exceptions: Set<String>,
) {

    /** [host] must already be a clean lowercase hostname. */
    fun registrableDomain(host: String): String? {
        if (host.isBlank()) return null
        val labels = host.split(".")
        if (labels.any { it.isEmpty() }) return null
        val suffixLabelCount = publicSuffixLabelCount(labels)
        if (labels.size <= suffixLabelCount) return null
        return labels.subList(labels.size - suffixLabelCount - 1, labels.size).joinToString(".")
    }

    /** A real listed rule only, not the implicit "*". */
    fun isListedSuffix(host: String): Boolean = rules.contains(host.lowercase())

    private fun publicSuffixLabelCount(labels: List<String>): Int {
        // Exception rules win outright.
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
            if (i + 1 < labels.size) {
                val wildcard = "*." + labels.subList(i + 1, labels.size).joinToString(".")
                if (rules.contains(wildcard)) best = maxOf(best, suffixLabels.size)
            }
        }
        // The implicit "*" rule: the last label is the suffix.
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
