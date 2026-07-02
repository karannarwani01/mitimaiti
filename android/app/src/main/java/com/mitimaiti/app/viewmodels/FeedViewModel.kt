package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.*
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.utils.AppNotificationManager
import com.mitimaiti.app.utils.AppNotification
import com.mitimaiti.app.utils.NotificationType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class FeedViewModel : ViewModel() {
    companion object { const val MAX_DAILY_LIKES = 50; const val MAX_DAILY_REWINDS = 10 }

    private val _cards = MutableStateFlow<List<FeedCard>>(emptyList())
    val cards: StateFlow<List<FeedCard>> = _cards.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _dailyLikesUsed = MutableStateFlow(0)
    val dailyLikesUsed: StateFlow<Int> = _dailyLikesUsed.asStateFlow()
    private val _dailyRewindsUsed = MutableStateFlow(0)
    val dailyRewindsUsed: StateFlow<Int> = _dailyRewindsUsed.asStateFlow()
    private val _showMatchAlert = MutableStateFlow(false)
    val showMatchAlert: StateFlow<Boolean> = _showMatchAlert.asStateFlow()
    private val _matchedUser = MutableStateFlow<User?>(null)
    val matchedUser: StateFlow<User?> = _matchedUser.asStateFlow()
    private val _matchedMatchId = MutableStateFlow<String?>(null)
    val matchedMatchId: StateFlow<String?> = _matchedMatchId.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _showScoreBreakdown = MutableStateFlow(false)
    val showScoreBreakdown: StateFlow<Boolean> = _showScoreBreakdown.asStateFlow()
    private val _selectedCard = MutableStateFlow<FeedCard?>(null)
    val selectedCard: StateFlow<FeedCard?> = _selectedCard.asStateFlow()

    /** Last swipes in order (card + kind), so rewind undoes likes AND passes
     *  — matching the backend, which deletes the most recent swipe of either
     *  kind (previously undoing after a like restored the wrong profile). */
    private data class Swipe(val card: FeedCard, val kind: String)
    private val swipeHistory = mutableListOf<Swipe>()

    val likesRemaining: Int get() = MAX_DAILY_LIKES - _dailyLikesUsed.value
    val rewindsRemaining: Int get() = MAX_DAILY_REWINDS - _dailyRewindsUsed.value

    private fun applyFeedPage(page: APIService.FeedPage, replace: Boolean) {
        if (replace) _cards.value = page.cards
        // Seed daily counters from the server so they survive relaunch
        page.likesUsedToday?.let { _dailyLikesUsed.value = it }
        page.rewindsUsedToday?.let { _dailyRewindsUsed.value = it }
    }

    // ── "Most Compatible" daily pick (Hinge Standouts-style) ──
    private val _dailyPick = MutableStateFlow<FeedCard?>(null)
    val dailyPick: StateFlow<FeedCard?> = _dailyPick.asStateFlow()

    private fun loadDailyPick() {
        viewModelScope.launch {
            APIService.fetchDailyPick().onSuccess { _dailyPick.value = it }
        }
    }

    /** Bring today's pick to the front of the deck so the user can swipe on it. */
    fun bringPickToFront() {
        val pick = _dailyPick.value ?: return
        val existing = _cards.value.firstOrNull { it.id == pick.id }
        _cards.value = listOf(existing ?: pick) + _cards.value.filterNot { it.id == pick.id }
    }

    /** Hide the pick banner once the user has swiped on that person. */
    private fun clearPickIfActedOn(cardId: String) {
        if (_dailyPick.value?.id == cardId) _dailyPick.value = null
    }

    fun loadFeed() { loadDailyPick(); viewModelScope.launch { _isLoading.value = true; APIService.fetchFeed().onSuccess { applyFeedPage(it, replace = true) }.onFailure { _error.value = "Failed to load profiles" }; _isLoading.value = false } }

    /**
     * Persist the Discover filter sheet to the backend (user_settings drives
     * the feed query server-side), then reload the deck. Previously "Show
     * Results" only mutated local state and the feed never changed.
     */
    fun applyFilters(state: com.mitimaiti.app.ui.components.FilterState) {
        viewModelScope.launch {
            val settings = mutableMapOf<String, Any?>(
                "age_min" to state.ageMin,
                "age_max" to state.ageMax,
                "height_min" to state.heightMin,
                "height_max" to state.heightMax,
                "gender_preference" to when (state.genderPreference) {
                    ShowMe.MEN -> "men"; ShowMe.WOMEN -> "women"; ShowMe.EVERYONE -> "everyone"
                },
                "verified_only" to state.verifiedOnly,
                "intent_filter" to state.intentFilter?.name?.lowercase(),
                "religion_filter" to state.religionFilter,
                "fluency_filter" to state.fluencyFilter?.name?.lowercase(),
                "gotra_filter" to state.gotraFilter,
                "dietary_filter" to state.dietaryFilter?.name?.lowercase(),
                "education_filter" to state.educationFilter,
                "smoking_filter" to state.smokingFilter,
                "drinking_filter" to state.drinkingFilter,
            )
            APIService.updateProfile(mapOf("settings" to settings))
            // Refetch with the new filters applied server-side
            _isLoading.value = true
            APIService.fetchFeed()
                .onSuccess { applyFeedPage(it, replace = true) }
                .onFailure { _error.value = "Failed to load profiles" }
            _isLoading.value = false
        }
    }

    fun likeUser() {
        val cur = _cards.value.toMutableList(); if (cur.isEmpty()) return
        if (_dailyLikesUsed.value >= MAX_DAILY_LIKES) {
            _error.value = "You've used all $MAX_DAILY_LIKES likes for today. Come back tomorrow!"
            return
        }
        val card = cur.removeAt(0); _cards.value = cur; _dailyLikesUsed.value++
        swipeHistory.add(Swipe(card, "like"))
        clearPickIfActedOn(card.id)
        viewModelScope.launch {
            APIService.performAction(card.user.id, "like").onSuccess { result ->
                result.likesUsedToday?.let { _dailyLikesUsed.value = it }
                if (result.isMatch) {
                    // A matched like can't be rewound — drop it from the undo stack
                    swipeHistory.removeAll { it.card.id == card.id }
                    _matchedUser.value = card.user; _matchedMatchId.value = result.matchId; _showMatchAlert.value = true
                    AppNotificationManager.shared.addNotification(type = NotificationType.MATCH, title = "It's a Match!", body = "You and ${card.user.displayName} liked each other!")
                }
            }.onFailure { err ->
                if (err is com.mitimaiti.app.services.APIError.DailyLimitReached) {
                    _dailyLikesUsed.value = MAX_DAILY_LIKES
                    _error.value = "You've used all $MAX_DAILY_LIKES likes for today. Come back tomorrow!"
                }
            }
            prefetchIfNeeded()
        }
    }

    fun passUser() { val cur = _cards.value.toMutableList(); if (cur.isEmpty()) return; val card = cur.removeAt(0); swipeHistory.add(Swipe(card, "pass")); clearPickIfActedOn(card.id); _cards.value = cur; viewModelScope.launch { APIService.performAction(card.user.id, "pass"); prefetchIfNeeded() } }

    fun rewind() {
        if (swipeHistory.isEmpty()) { _error.value = "Nothing to rewind!"; return }
        if (_dailyRewindsUsed.value >= MAX_DAILY_REWINDS) {
            _error.value = "You've used all $MAX_DAILY_REWINDS rewinds for today."
            return
        }
        val swipe = swipeHistory.removeAt(swipeHistory.size - 1)
        _cards.value = listOf(swipe.card) + _cards.value
        _dailyRewindsUsed.value++
        if (swipe.kind == "like" && _dailyLikesUsed.value > 0) _dailyLikesUsed.value--
        viewModelScope.launch {
            APIService.rewind().onFailure { err ->
                if (err is com.mitimaiti.app.services.APIError.CannotRewindMatched) {
                    // The like became a match server-side — put the card back off the deck
                    _cards.value = _cards.value.filterNot { it.id == swipe.card.id }
                    _error.value = "It's already a match! Unmatch from the chat instead."
                }
            }
        }
    }
    fun dismissMatchAlert() { _showMatchAlert.value = false; _matchedUser.value = null; _matchedMatchId.value = null }
    fun showScoreBreakdown(card: FeedCard) { _selectedCard.value = card; _showScoreBreakdown.value = true }
    fun hideScoreBreakdown() { _showScoreBreakdown.value = false; _selectedCard.value = null }
    private suspend fun prefetchIfNeeded() { if (_cards.value.size < 5) { APIService.fetchFeed().onSuccess { page -> val ids = _cards.value.map { it.id }.toSet(); _cards.value = _cards.value + page.cards.filter { it.id !in ids }; applyFeedPage(page, replace = false) } } }
}
