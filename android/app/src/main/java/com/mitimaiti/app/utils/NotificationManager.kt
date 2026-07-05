package com.mitimaiti.app.utils

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.ui.graphics.Color
import com.mitimaiti.app.ui.theme.AppColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Calendar
import java.util.UUID

enum class NotificationType(val iconName: String, val destinationTab: Int?) {
    MATCH("heart.circle.fill", 2),
    LIKE("heart.fill", 1),
    MESSAGE("message.fill", 2),
    FAMILY("person.3.fill", null),
    FAMILY_SUGGESTION("lightbulb.fill", null),
    EXPIRY("clock.fill", 2),
    SYSTEM("bell.fill", null),
    PROFILE_VIEW("eye.fill", 3),
    ICEBREAKER("sparkles", 2),
    FEATURE("star.fill", null);

    val color: Color get() = when (this) {
        MATCH, LIKE -> AppColors.Rose
        MESSAGE, PROFILE_VIEW -> AppColors.Info
        FAMILY, FAMILY_SUGGESTION, ICEBREAKER -> AppColors.Gold
        EXPIRY -> AppColors.Warning
        SYSTEM -> AppColors.DarkTextSecondary
        FEATURE -> AppColors.Success
    }

    val settingsKey: String get() = when (this) {
        MATCH -> "matches"
        LIKE, PROFILE_VIEW -> "likes"
        MESSAGE -> "messages"
        FAMILY, FAMILY_SUGGESTION -> "family"
        EXPIRY -> "expiry"
        SYSTEM -> "safety"
        ICEBREAKER -> "dailyPrompt"
        FEATURE -> "newFeatures"
    }
}

data class AppNotification(
    val id: String = UUID.randomUUID().toString(),
    val type: NotificationType,
    val title: String,
    val body: String,
    val createdAt: Long = System.currentTimeMillis(),
    val isRead: Boolean = false,
    val actionData: String? = null
)

data class NotificationSettings(
    var matches: Boolean = true,
    var messages: Boolean = true,
    var likes: Boolean = true,
    var family: Boolean = true,
    var expiry: Boolean = true,
    var dailyPrompt: Boolean = true,
    var newFeatures: Boolean = false,
    var safety: Boolean = true
) {
    fun isEnabled(type: NotificationType): Boolean = when (type) {
        NotificationType.MATCH -> matches
        NotificationType.LIKE, NotificationType.PROFILE_VIEW -> likes
        NotificationType.MESSAGE -> messages
        NotificationType.FAMILY, NotificationType.FAMILY_SUGGESTION -> family
        NotificationType.EXPIRY -> expiry
        NotificationType.SYSTEM -> safety
        NotificationType.ICEBREAKER -> dailyPrompt
        NotificationType.FEATURE -> newFeatures
    }
}

class AppNotificationManager {
    private val _notifications = MutableStateFlow<List<AppNotification>>(emptyList())
    val notifications: StateFlow<List<AppNotification>> = _notifications.asStateFlow()

    private val _selectedTab = MutableStateFlow(0)
    val selectedTab: StateFlow<Int> = _selectedTab.asStateFlow()

    private val _settings = MutableStateFlow(NotificationSettings())
    val settings: StateFlow<NotificationSettings> = _settings.asStateFlow()

    val unreadCount: Int
        get() = _notifications.value.count { !it.isRead }

    fun unreadCountForTypes(types: List<NotificationType>): Int {
        return _notifications.value.count { !it.isRead && it.type in types }
    }

    val todayNotifications: List<AppNotification>
        get() {
            val today = Calendar.getInstance()
            return _notifications.value.filter { n ->
                val cal = Calendar.getInstance().apply { timeInMillis = n.createdAt }
                cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    cal.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
            }
        }

    val earlierNotifications: List<AppNotification>
        get() {
            val today = Calendar.getInstance()
            return _notifications.value.filter { n ->
                val cal = Calendar.getInstance().apply { timeInMillis = n.createdAt }
                !(cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    cal.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR))
            }
        }

    // CRUD Operations

    fun addNotification(
        type: NotificationType,
        title: String,
        body: String,
        actionData: String? = null
    ) {
        if (!_settings.value.isEnabled(type)) return

        val notification = AppNotification(
            type = type,
            title = title,
            body = body,
            actionData = actionData
        )
        _notifications.value = listOf(notification) + _notifications.value
        pruneNotifications()
    }

    fun markAsRead(id: String) {
        _notifications.value = _notifications.value.map {
            if (it.id == id) it.copy(isRead = true) else it
        }
    }

    fun markAllRead() {
        _notifications.value = _notifications.value.map { it.copy(isRead = true) }
    }

    fun dismiss(id: String) {
        _notifications.value = _notifications.value.filter { it.id != id }
    }

    fun clearAll() {
        _notifications.value = emptyList()
    }

    // Navigation

    fun handleNotificationTap(notification: AppNotification) {
        markAsRead(notification.id)
        notification.type.destinationTab?.let { _selectedTab.value = it }
    }

    fun setSelectedTab(tab: Int) {
        _selectedTab.value = tab
    }

    // Settings

    fun updateSettings(newSettings: NotificationSettings) {
        _settings.value = newSettings
    }

    // Pruning

    private fun pruneNotifications() {
        val maxCount = 50
        val maxAgeMs = 30L * 24 * 60 * 60 * 1000 // 30 days
        val cutoff = System.currentTimeMillis() - maxAgeMs

        var list = _notifications.value
        list = list.filter { it.createdAt > cutoff }
        if (list.size > maxCount) list = list.take(maxCount)
        _notifications.value = list
    }

    // Seed Data

    fun loadSeedNotifications() {
        if (_notifications.value.isNotEmpty()) return

        val now = System.currentTimeMillis()
        _notifications.value = listOf(
            AppNotification(id = "seed-1", type = NotificationType.MATCH, title = "New Match!", body = "You and Priya matched! Say hi before the timer runs out.", createdAt = now - 300_000),
            AppNotification(id = "seed-2", type = NotificationType.LIKE, title = "Someone liked you", body = "Arjun liked your profile. Check Liked You to see!", createdAt = now - 1_800_000),
            AppNotification(id = "seed-3", type = NotificationType.MESSAGE, title = "New message from Meera", body = "\"I just made the best dal pakwan of my life!\"", createdAt = now - 3_600_000),
            AppNotification(id = "seed-5", type = NotificationType.EXPIRY, title = "Match with Roshni expires in 4h", body = "Send a message before it's too late!", createdAt = now - 10_800_000, isRead = true),
            AppNotification(id = "seed-6", type = NotificationType.LIKE, title = "Anika liked your photo", body = "You have a new admirer! Take a look.", createdAt = now - 14_400_000),
            AppNotification(id = "seed-8", type = NotificationType.SYSTEM, title = "Weekly summary: 47 views, 12 likes", body = "Your profile had a great week! Keep it up.", createdAt = now - 86_400_000, isRead = true),
            AppNotification(id = "seed-9", type = NotificationType.ICEBREAKER, title = "Conversation starter", body = "Try asking about their favorite Sindhi dish!", createdAt = now - 90_000_000, isRead = true),
            AppNotification(id = "seed-10", type = NotificationType.FEATURE, title = "New feature: Voice Intros!", body = "Record a short voice intro to stand out from the crowd.", createdAt = now - 172_800_000, isRead = true),
        )
    }

    companion object {
        val shared = AppNotificationManager()
    }
}
