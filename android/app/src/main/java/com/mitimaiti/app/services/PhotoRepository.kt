package com.mitimaiti.app.services

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A profile photo as the client tracks it: the display URI plus the server
 * photo id. The id is null only for a local pick that hasn't been uploaded
 * yet (onboarding) — server-backed operations (delete / set-primary /
 * reorder) are skipped for those.
 */
data class ProfilePhoto(
    val id: String? = null,
    val uri: Uri,
)

/**
 * Singleton repository for the current user's photos. Index 0 is the primary
 * photo. Hydrated from GET /v1/me on profile load; mutations are pushed to
 * the backend by ProfileViewModel (this object only holds local state).
 */
object PhotoRepository {
    private val _photos = MutableStateFlow<List<ProfilePhoto>>(emptyList())
    val photos: StateFlow<List<ProfilePhoto>> = _photos.asStateFlow()

    val primaryPhotoUri: Uri?
        get() = _photos.value.firstOrNull()?.uri

    /** Replace the whole set (server hydration on profile load). */
    fun setPhotos(photos: List<ProfilePhoto>) {
        _photos.value = photos
    }

    fun addPhoto(photo: ProfilePhoto) {
        if (_photos.value.size < 6) {
            _photos.value = _photos.value + photo
        }
    }

    fun addPhoto(uri: Uri) = addPhoto(ProfilePhoto(uri = uri))

    fun photoAt(index: Int): ProfilePhoto? = _photos.value.getOrNull(index)

    fun removePhoto(index: Int) {
        val list = _photos.value.toMutableList()
        if (index in list.indices) {
            list.removeAt(index)
            _photos.value = list
        }
    }

    /** Remove by identity (safe against index shifts while a delete call is in flight). */
    fun removePhoto(photo: ProfilePhoto) {
        _photos.value = _photos.value.filterNot { it === photo || (photo.id != null && it.id == photo.id) }
    }

    fun setPrimaryPhoto(index: Int) {
        val list = _photos.value.toMutableList()
        if (index in list.indices && index != 0) {
            val photo = list.removeAt(index)
            list.add(0, photo)
            _photos.value = list
        }
    }

    fun clear() {
        _photos.value = emptyList()
    }
}
