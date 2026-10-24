package com.helix.remote

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * The door Android's notification service reads a call's ringtone through.
 *
 * A channel's sound is opened by the system's own process, without a per-URI
 * grant, so this provider has to be exported. It can only open one file name
 * directly inside `getExternalFilesDir("ringtones")`, the folder
 * `core/sounds/orbit_ringtones.dart` writes the chosen ringtone into, and it is
 * read-only. No other part of the app is reachable.
 *
 * androidx's FileProvider cannot do this job: it throws
 * "Provider must not be exported" while the app starts, which is why this is a
 * provider of its own rather than a manifest entry over FileProvider.
 */
class RingtoneProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("ringtone copies are read only")
        val directory = context?.getExternalFilesDir(RINGTONE_DIR)
            ?: throw FileNotFoundException("no external files folder")
        val name = nameOf(uri) ?: throw FileNotFoundException(uri.toString())
        val file = File(directory, name)
        // Refuses anything that resolves outside the ringtones folder: a
        // symlink, a traversal, or a nested path.
        if (file.canonicalFile.parentFile != directory.canonicalFile || !file.isFile) {
            throw FileNotFoundException(uri.toString())
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? {
        val name = nameOf(uri) ?: return null
        return when (File(name).extension.lowercase()) {
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/mp4"
            "ogg", "opus" -> "audio/ogg"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            else -> null
        }
    }

    /** `ringtones/<one file name>`, and nothing else. */
    private fun nameOf(uri: Uri): String? {
        val segments = uri.pathSegments
        if (segments.size != 2 || segments[0] != RINGTONE_DIR) return null
        val name = segments[1]
        if (name.isEmpty() || name.startsWith('.') || name != File(name).name) return null
        return name
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private companion object {
        const val RINGTONE_DIR = "ringtones"
    }
}
