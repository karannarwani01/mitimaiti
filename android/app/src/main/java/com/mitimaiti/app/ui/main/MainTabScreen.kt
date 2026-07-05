@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import android.view.HapticFeedbackConstants
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.mitimaiti.app.ui.components.CountBadge
import com.mitimaiti.app.ui.components.NotificationPanel
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.utils.AppNotificationManager
import com.mitimaiti.app.viewmodels.FeedViewModel
import com.mitimaiti.app.viewmodels.InboxViewModel
import com.mitimaiti.app.viewmodels.ProfileViewModel

enum class MainTab(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    DISCOVER("Discover", Icons.Filled.Explore, Icons.Outlined.Explore),
    LIKED_YOU("Liked You", Icons.Filled.Favorite, Icons.Outlined.FavoriteBorder),
    MATCHES("Matches", Icons.Filled.ChatBubble, Icons.Outlined.ChatBubbleOutline),
    PROFILE("Profile", Icons.Filled.Person, Icons.Outlined.Person)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainTabScreen(
    feedViewModel: FeedViewModel,
    inboxViewModel: InboxViewModel,
    profileViewModel: ProfileViewModel,
    onNavigateToChat: (String) -> Unit,
    onNavigateToEditProfile: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onLogout: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    var selectedTab by remember { mutableStateOf(MainTab.DISCOVER) }
    val totalLikes = inboxViewModel.totalLikes
    val unreadMessages = inboxViewModel.unreadMessages

    // Notification panel state
    var showNotificationPanel by remember { mutableStateOf(false) }
    val notifications by AppNotificationManager.shared.notifications.collectAsState()
    val unreadNotifCount = notifications.count { !it.isRead }
    val view = LocalView.current

    LaunchedEffect(Unit) {
        feedViewModel.loadFeed()
        inboxViewModel.loadInbox()
        profileViewModel.loadProfile()
    }

    Scaffold(
        containerColor = colors.background,
        topBar = { },
        bottomBar = {
            NavigationBar(
                modifier = Modifier.drawBehind {
                    val shadowColor = Color.Black.copy(alpha = 0.08f)
                    drawRect(
                        color = shadowColor,
                        topLeft = Offset(0f, -8.dp.toPx()),
                        size = size.copy(height = 8.dp.toPx())
                    )
                },
                containerColor = colors.surface,
                contentColor = colors.textPrimary
            ) {
                MainTab.entries.forEach { tab ->
                    val selected = selectedTab == tab
                    val scaleTarget = if (selected) 1.15f else 1.0f
                    val iconScale by animateFloatAsState(
                        targetValue = scaleTarget,
                        animationSpec = spring(
                            dampingRatio = 0.4f,
                            stiffness = 300f
                        ),
                        label = "tabBounce"
                    )
                    val badgeCount = when (tab) {
                        MainTab.LIKED_YOU -> totalLikes
                        MainTab.MATCHES -> unreadMessages
                        else -> 0
                    }
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            selectedTab = tab
                        },
                        icon = {
                            if (badgeCount > 0) {
                                BadgedBox(
                                    modifier = Modifier.scale(iconScale),
                                    badge = {
                                    Badge(containerColor = AppColors.Rose) {
                                        Text(
                                            if (badgeCount > 99) "99+" else badgeCount.toString(),
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }) {
                                    Icon(
                                        if (selected) tab.selectedIcon else tab.unselectedIcon,
                                        contentDescription = tab.title
                                    )
                                }
                            } else {
                                Icon(
                                    if (selected) tab.selectedIcon else tab.unselectedIcon,
                                    contentDescription = tab.title,
                                    modifier = Modifier.scale(iconScale)
                                )
                            }
                        },
                        label = { Text(tab.title, fontSize = 11.sp) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = AppColors.Rose,
                            selectedTextColor = AppColors.Rose,
                            unselectedIconColor = colors.textMuted,
                            unselectedTextColor = colors.textMuted,
                            indicatorColor = AppColors.Rose.copy(alpha = 0.1f)
                        )
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            // Tab content with animated transitions
            AnimatedContent(
                targetState = selectedTab,
                transitionSpec = {
                    fadeIn(animationSpec = tween(200)) togetherWith
                        fadeOut(animationSpec = tween(200))
                },
                label = "tabContent"
            ) { currentTab ->
                when (currentTab) {
                    MainTab.DISCOVER -> DiscoverScreen(
                        viewModel = feedViewModel,
                        onNavigateToEditProfile = onNavigateToEditProfile,
                        userProfileCompleteness = profileViewModel.computedCompleteness,
                        onSendMessage = { matchId, matchedUser ->
                            // Seed the inbox with the fresh match so the chat
                            // route can resolve it immediately, then open it.
                            inboxViewModel.upsertMatch(
                                com.mitimaiti.app.models.Match(
                                    id = matchId,
                                    otherUser = matchedUser,
                                    status = com.mitimaiti.app.models.MatchStatus.PENDING_FIRST_MESSAGE,
                                    matchedAt = System.currentTimeMillis(),
                                    expiresAt = System.currentTimeMillis() + 24 * 60 * 60 * 1000L
                                )
                            )
                            onNavigateToChat(matchId)
                        }
                    )
                    MainTab.LIKED_YOU -> LikedYouScreen(viewModel = inboxViewModel)
                    MainTab.MATCHES -> MatchesScreen(
                        viewModel = inboxViewModel,
                        onNavigateToChat = onNavigateToChat
                    )
                    MainTab.PROFILE -> ProfileScreen(
                        viewModel = profileViewModel,
                        onEditProfile = onNavigateToEditProfile,
                        onSettings = onNavigateToSettings,
                        onLogout = onLogout
                    )
                }
            }

            // Notification panel overlay (on top of content)
            NotificationPanel(
                visible = showNotificationPanel,
                onDismiss = { showNotificationPanel = false },
                onNotificationTap = { notification ->
                    showNotificationPanel = false
                    // Navigate to relevant tab based on notification type
                    val targetTab = notification.type.destinationTab?.let { MainTab.entries.getOrNull(it) }
                    if (targetTab != null) selectedTab = targetTab
                }
            )
        }
    }
}
