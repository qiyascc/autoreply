package cc.ubermensch.ctm

/**
 * Normalises the many shapes a caller ID arrives in down to bare E.164 digits, so that
 * "0532 111 22 33", "+90 532 111 22 33" and "00905321112233" all count as the same person
 * when we tally how many times they have called.
 */
object PhoneNumbers {

    /** Returns digits-only E.164 (no leading +), or null if the number is unusable. */
    fun toE164(raw: String?, defaultCountryCode: String): String? {
        if (raw.isNullOrBlank()) return null

        val trimmed = raw.trim()
        // Withheld / unknown caller IDs arrive as these sentinels on many networks.
        if (trimmed.equals("unknown", true) ||
            trimmed.equals("private", true) ||
            trimmed.equals("restricted", true) ||
            trimmed == "-1" || trimmed == "-2" || trimmed == "-3"
        ) return null

        val hasPlus = trimmed.startsWith("+")
        var digits = trimmed.filter { it.isDigit() }
        if (digits.isEmpty()) return null

        // Short codes (banks, operators) are not people; never try to expand them.
        if (!hasPlus && digits.length <= 6) return digits

        if (!hasPlus) {
            when {
                digits.startsWith("00") -> digits = digits.removePrefix("00")
                // A single leading zero is the national trunk prefix.
                digits.startsWith("0") -> digits = defaultCountryCode + digits.removePrefix("0")
                // A bare subscriber number, e.g. 5321112233 in Turkey.
                digits.length <= 10 -> digits = defaultCountryCode + digits
            }
        }

        if (digits.length < 7 || digits.length > 15) return null
        return digits
    }

    /** Human-facing form: "+90 532 111 22 33" for TR mobiles, "+<digits>" otherwise. */
    fun pretty(e164: String?): String {
        if (e164.isNullOrBlank()) return "Unknown"
        if (e164.length <= 6) return e164
        if (e164.startsWith("90") && e164.length == 12) {
            val n = e164.substring(2)
            return "+90 ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6, 8)} ${n.substring(8)}"
        }
        return "+$e164"
    }

    /** True when the two numbers refer to the same subscriber. */
    fun sameNumber(a: String?, b: String?): Boolean {
        if (a.isNullOrBlank() || b.isNullOrBlank()) return false
        if (a == b) return true
        // Fall back to comparing the last 9 digits, which survives country-code guesswork.
        val tailA = a.takeLast(9)
        val tailB = b.takeLast(9)
        return tailA.length == 9 && tailA == tailB
    }
}
