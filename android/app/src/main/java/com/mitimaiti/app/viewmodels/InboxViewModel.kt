package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.*
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.utils.AppNotificationManager
import com.mitimaiti.app.utils.NotificationType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class InboxViewModel : ViewModel() {
    private val _likes = MutableStateFlow<List<LikedYouCard>>(emptyList())
    val likes: StateFlow<List<LikedYouCard>> = _likes.asStateFlow()
    private val _matches = MutableStateFlow<List<Match>>(emptyList())
    val matches: StateFlow<List<Match>> = _matches.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    val totalLikes: Int get() = _likes.value.size
    val totalMatches: Int get() = _matches.value.size
    val unreadMessages: Int get() = _matches.value.sumOf { it.unreadCount }

    private var hasLoadedOnce = false

    fun loadInbox() {
        // Always refetch from the server (the source of truth for matches +
        // their activation state), so a new match from a Discover like appears
        // on the next inbox open. Matches iOS, which has no reload guard.
        viewModelScope.launch {
            _isLoading.value = true
            APIService.fetchInbox().onSuccess { (likes, matches) ->
                val prev = _likes.value.size
                _likes.value = likes
                _matches.value = matches
                hasLoadedOnce = true
                if (likes.size > prev && prev > 0) {
                    AppNotificationManager.shared.addNotification(
                        type = NotificationType.LIKE,
                        title = "New likes!",
                        body = "${likes.size - prev} people liked your profile"
                    )
                }
            }.onFailure { _error.value = "Failed to load inbox" }
            _isLoading.value = false
        }
    }

    fun likeBack(likeId: String) {
        val like = _likes.value.firstOrNull { it.id == likeId } ?: return; _likes.value = _likes.value.filter { it.id != likeId }
        _matches.value = listOf(Match(otherUser = like.user, status = MatchStatus.PENDING_FIRST_MESSAGE, matchedAt = System.currentTimeMillis(), expiresAt = System.currentTimeMillis() + 24 * 60 * 60 * 1000L)) + _matches.value
        AppNotificationManager.shared.addNotification(type = NotificationType.MATCH, title = "It's a Match!", body = "You and ${like.user.displayName} liked each other!")
        // Persist the like so the match is actually created server-side (they
        // already liked us → mutual match). Without this the match is cosmetic
        // and vanishes on the next inbox refetch.
        viewModelScope.launch { APIService.performAction(like.user.id, "like") }
    }

    fun passLike(likeId: String) { _likes.value = _likes.value.filter { it.id != likeId } }
    fun unmatch(matchId: String) { _matches.value = _matches.value.filter { it.id != matchId } }

    /**
     * Called when a reply is received after the ice breaker.
     * Transitions match from PENDING → ACTIVE, removes expiry (chat saved permanently).
     */
    fun activateMatch(matchId: String, lastMessage: String = "") {
        _matches.value = _matches.value.map { match ->
            if (match.id == matchId) {
                match.copy(
                    status = MatchStatus.ACTIVE,
                    expiresAt = null,
                    firstMsgLocked = false,
                    lastMessage = lastMessage.ifEmpty { match.lastMessage },
                    unreadCount = match.unreadCount + 1
                )
            } else match
        }
        val match = _matches.value.firstOrNull { it.id == matchId }
        if (match != null) {
            AppNotificationManager.shared.addNotification(
                type = NotificationType.MESSAGE,
                title = match.otherUser.displayName,
                body = lastMessage
            )
        }
    }
}
