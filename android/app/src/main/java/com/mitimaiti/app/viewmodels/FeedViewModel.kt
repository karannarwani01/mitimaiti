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
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _showScoreBreakdown = MutableStateFlow(false)
    val showScoreBreakdown: StateFlow<Boolean> = _showScoreBreakdown.asStateFlow()
    private val _selectedCard = MutableStateFlow<FeedCard?>(null)
    val selectedCard: StateFlow<FeedCard?> = _selectedCard.asStateFlow()
    private val passedCards = mutableListOf<FeedCard>()
    val likesRemaining: Int get() = MAX_DAILY_LIKES - _dailyLikesUsed.value
    val rewindsRemaining: Int get() = MAX_DAILY_REWINDS - _dailyRewindsUsed.value

    fun loadFeed() { viewModelScope.launch { _isLoading.value = true; APIService.fetchFeed().onSuccess { _cards.value = it }.onFailure { _error.value = "Failed to load profiles" }; _isLoading.value = false } }

    fun likeUser() {
        val cur = _cards.value.toMutableList(); if (cur.isEmpty() || _dailyLikesUsed.value >= MAX_DAILY_LIKES) return
        val card = cur.removeAt(0); _cards.value = cur; _dailyLikesUsed.value++
        viewModelScope.launch { APIService.performAction(card.user.id, "like").onSuccess { match -> if (match != null) { _matchedUser.value = card.user; _showMatchAlert.value = true; AppNotificationManager.shared.addNotification(type = NotificationType.MATCH, title = "It's a Match!", body = "You and ${card.user.displayName} liked each other!") } }; prefetchIfNeeded() }
    }

    fun passUser() { val cur = _cards.value.toMutableList(); if (cur.isEmpty()) return; val card = cur.removeAt(0); passedCards.add(card); _cards.value = cur; viewModelScope.launch { APIService.performAction(card.user.id, "pass"); prefetchIfNeeded() } }
    fun rewind() { if (passedCards.isEmpty() || _dailyRewindsUsed.value >= MAX_DAILY_REWINDS) return; val card = passedCards.removeAt(passedCards.size - 1); _cards.value = listOf(card) + _cards.value; _dailyRewindsUsed.value++; viewModelScope.launch { APIService.rewind() } }
    fun dismissMatchAlert() { _showMatchAlert.value = false; _matchedUser.value = null }
    fun showScoreBreakdown(card: FeedCard) { _selectedCard.value = card; _showScoreBreakdown.value = true }
    fun hideScoreBreakdown() { _showScoreBreakdown.value = false; _selectedCard.value = null }
    private suspend fun prefetchIfNeeded() { if (_cards.value.size < 5) { APIService.fetchFeed().onSuccess { new -> val ids = _cards.value.map { it.id }.toSet(); _cards.value = _cards.value + new.filter { it.id !in ids } } } }
}
