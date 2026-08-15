package cc.ubermensch.ctm

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.util.Log

/** Resolves a number to a contact name, and tells rules whether the caller is known at all. */
object Contacts {

    private const val TAG = "Contacts"

    private fun canRead(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    fun displayName(context: Context, e164: String?): String? {
        if (e164.isNullOrBlank() || !canRead(context)) return null
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(e164),
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null,
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            Log.w(TAG, "contact lookup failed", e)
            null
        }
    }

    fun isKnown(context: Context, e164: String?): Boolean = displayName(context, e164) != null
}
