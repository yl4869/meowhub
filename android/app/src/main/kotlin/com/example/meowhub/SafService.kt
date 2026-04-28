package com.example.meowhub

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class SafService(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.example.meowhub/saf"

        private val POSTER_NAMES = setOf(
            "poster.jpg", "poster.png", "folder.jpg", "folder.png",
            "cover.jpg", "cover.png"
        )
        private val BACKDROP_NAMES = setOf(
            "fanart.jpg", "fanart.png", "backdrop.jpg", "backdrop.png",
            "background.jpg", "background.png"
        )

        fun register(engine: FlutterEngine, context: Context) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(SafService(context.applicationContext))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanTree" -> handleScanTree(call, result)
            "generateThumbnail" -> handleGenerateThumbnail(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleScanTree(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
            if (treeUri == null) {
                result.error("INVALID_ARG", "treeUri is required", null)
                return
            }
            val videoExtensions = call.argument<List<String>>("videoExtensions")
                ?.toSet() ?: setOf(
                    ".mp4", ".mkv", ".avi", ".mov", ".wmv",
                    ".flv", ".webm", ".ts", ".m4v"
                )

            val rootDoc = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
            if (rootDoc == null) {
                result.error("INVALID_URI", "Cannot resolve tree URI: $treeUri", null)
                return
            }

            val files = mutableListOf<Map<String, Any?>>()
            val dirCache = mutableMapOf<String, List<DocumentFile>>()

            walkTree(rootDoc, videoExtensions, files, dirCache)

            result.success(mapOf(
                "files" to files,
                "totalFound" to files.size
            ))
        } catch (e: Exception) {
            result.error("SCAN_ERROR", e.message ?: "Unknown error", null)
        }
    }

    private fun walkTree(
        doc: DocumentFile,
        videoExtensions: Set<String>,
        files: MutableList<Map<String, Any?>>,
        dirCache: MutableMap<String, List<DocumentFile>>
    ) {
        val children = try {
            doc.listFiles().toList()
        } catch (e: Exception) {
            return
        }

        val parentUri = doc.uri.toString()
        dirCache[parentUri] = children

        val hasTvshowNfo = children.any {
            it.name?.equals("tvshow.nfo", ignoreCase = true) == true
        }
        val seasonFolderName = detectSeasonFolder(doc.name)

        for (child in children) {
            val name = child.name ?: continue
            if (child.isDirectory && !name.startsWith(".")) {
                walkTree(child, videoExtensions, files, dirCache)
            } else if (child.isFile) {
                val ext = name.substringAfterLast('.', "").lowercase()
                if (".$ext" in videoExtensions) {
                    val baseName = name.substringBeforeLast('.')
                    val nfoFile = children.find { s ->
                        val sn = s.name ?: return@find false
                        sn.equals("$baseName.nfo", ignoreCase = true) ||
                            sn.equals("movie.nfo", ignoreCase = true)
                    }
                    val nfoContent = if (nfoFile != null) {
                        readFileContent(nfoFile.uri)
                    } else null

                    val posterUri = findImage(children, baseName, POSTER_NAMES)
                    val backdropUri = findImage(children, baseName, BACKDROP_NAMES)

                    files.add(mapOf(
                        "uri" to child.uri.toString(),
                        "name" to name,
                        "size" to child.length(),
                        "mtime" to child.lastModified(),
                        "parentUri" to parentUri,
                        "nfoContent" to nfoContent,
                        "posterUri" to posterUri,
                        "backdropUri" to backdropUri,
                        "dirHasTvshowNfo" to hasTvshowNfo,
                        "seasonFolderName" to seasonFolderName
                    ))
                }
            }
        }
    }

    private fun readFileContent(uri: Uri): String? {
        return try {
            context.contentResolver.openInputStream(uri)
                ?.bufferedReader()
                ?.readText()
        } catch (e: Exception) {
            null
        }
    }

    private fun findImage(
        siblings: List<DocumentFile>,
        baseName: String,
        names: Set<String>
    ): String? {
        // Same-name images first: "video-poster.jpg", "video.poster.jpg"
        for (sibling in siblings) {
            val sName = sibling.name ?: continue
            if (!sibling.isFile) continue
            for (imgName in names) {
                if (sName.equals("$baseName-$imgName", ignoreCase = true) ||
                    sName.equals("$baseName.$imgName", ignoreCase = true)
                ) {
                    return sibling.uri.toString()
                }
            }
        }
        // Generic folder images: "poster.jpg", "folder.jpg", etc.
        for (sibling in siblings) {
            val sName = sibling.name ?: continue
            if (!sibling.isFile) continue
            if (names.any { sName.equals(it, ignoreCase = true) }) {
                return sibling.uri.toString()
            }
        }
        return null
    }

    private fun detectSeasonFolder(name: String?): String? {
        if (name == null) return null
        val regex = Regex("^[Ss](?:eason)?[_\\s.-]*(\\d{1,2})$")
        return if (regex.matches(name.trim())) name.trim() else null
    }

    private fun handleGenerateThumbnail(call: MethodCall, result: MethodChannel.Result) {
        try {
            val uri = call.argument<String>("uri")
            val outputPath = call.argument<String>("outputPath")
            if (uri == null || outputPath == null) {
                result.error("INVALID_ARG", "uri and outputPath are required", null)
                return
            }

            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, Uri.parse(uri))
                // Seek to 1 second to avoid black frames
                val bitmap = retriever.getFrameAtTime(1_000_000)
                if (bitmap != null) {
                    val outFile = java.io.File(outputPath)
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { fos ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, fos)
                    }
                    result.success(outputPath)
                } else {
                    result.success(null)
                }
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            result.success(null)
        }
    }
}
