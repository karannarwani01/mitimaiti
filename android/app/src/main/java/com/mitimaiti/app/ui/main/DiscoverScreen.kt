@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import android.view.HapticFeedbackConstants
import coil.compose.AsyncImage
import com.mitimaiti.app.models.*
import com.mitimaiti.app.ui.components.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.FeedViewModel
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    viewModel: FeedViewModel,
    onNavigateToEditProfile: () -> Unit = {},
    userProfileCompleteness: Int = 100,
    /** Called with (matchId, matchedUser) when "Send Message" is tapped on the match popup. */
    onSendMessage: (String, User) -> Unit = { _, _ -> }
) {
    val colors = LocalAdaptiveColors.current
    val cards by viewModel.cards.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val showMatchAlert by viewModel.showMatchAlert.collectAsState()
    val matchedUser by viewModel.matchedUser.collectAsState()
    val showScoreBreakdown by viewModel.showScoreBreakdown.collectAsState()
    val selectedCard by viewModel.selectedCard.collectAsState()

    var showFilters by remember { mutableStateOf(false) }
    var filterState by remember { mutableStateOf(FilterState()) }
    val activeFilterCount = countActiveFilters(filterState)

    Box(modifier = Modifier.fillMaxSize().background(colors.backgroundGradient)) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
            // ── Header ──
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Discover", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(
                        onClick = { showFilters = true },
                        shape = RoundedCornerShape(AppTheme.radiusFull),
                        color = Color.Transparent,
                        border = androidx.compose.foundation.BorderStroke(1.dp, colors.textMuted.copy(alpha = 0.3f))
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Icon(Icons.Default.Tune, "Filters", tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                            Text("Filters", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                            if (activeFilterCount > 0) {
                                Surface(
                                    shape = CircleShape,
                                    color = AppColors.Rose,
                                    modifier = Modifier.size(20.dp)
                                ) {
                                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                                        Text("$activeFilterCount", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Card Deck + Buttons + Banner ──
            when {
                isLoading -> {
                    Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.TopCenter) {
                        ShimmerDiscoverCard(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    }
                }
                cards.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Explore,
                            title = "No more profiles",
                            description = "Check back later for new Sindhi singles in your area",
                            actionLabel = "Adjust Filters",
                            onAction = { showFilters = true }
                        )
                    }
                }
                else -> {
                    val visibleCards = cards.take(3)
                    val topCard = visibleCards.first()

                    // Card area
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .padding(start = 16.dp, end = 16.dp, top = 4.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        // Stacked background cards (right-side peek like iOS)
                        repeat(3) { i ->
                            if (i > 0) {
                                Surface(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .fillMaxHeight()
                                        .padding(
                                            start = 0.dp,
                                            end = (32 - i * 8).dp,
                                            top = (i * 3).dp,
                                            bottom = (i * 3).dp
                                        )
                                        .zIndex(-i.toFloat()),
                                    shape = RoundedCornerShape(20.dp),
                                    color = Color(1f - i * 0.04f, 1f - i * 0.04f, 1f - i * 0.04f),
                                    shadowElevation = 2.dp,
                                    border = androidx.compose.foundation.BorderStroke(0.5.dp, Color.Gray.copy(alpha = 0.15f))
                                ) {}
                            }
                        }

                        // Top swipeable card
                        key(topCard.id) {
                            SwipeablePhotoCard(
                                card = topCard,
                                onSwipeRight = { viewModel.likeUser() },
                                onSwipeLeft = { viewModel.passUser() },
                                onTap = { }
                            )
                        }
                    }

                    // ── Pass / Like Buttons (below card, like iOS) ──
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val view = LocalView.current

                        // Pass button
                        FloatingActionButton(
                            onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                viewModel.passUser()
                            },
                            containerColor = colors.surface,
                            contentColor = colors.textSecondary,
                            shape = CircleShape,
                            modifier = Modifier
                                .size(52.dp)
                                .shadow(6.dp, CircleShape),
                            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 3.dp)
                        ) {
                            Icon(Icons.Default.Close, "Pass", modifier = Modifier.size(22.dp))
                        }

                        Spacer(modifier = Modifier.width(24.dp))

                        // Like button
                        FloatingActionButton(
                            onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                viewModel.likeUser()
                            },
                            containerColor = AppColors.Rose,
                            contentColor = Color.White,
                            shape = CircleShape,
                            modifier = Modifier
                                .size(56.dp)
                                .shadow(8.dp, CircleShape),
                            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 4.dp)
                        ) {
                            Icon(Icons.Default.Favorite, "Like", modifier = Modifier.size(24.dp))
                        }
                    }

                    // ── Profile completeness banner ──
                    if (userProfileCompleteness < 90) {
                        Surface(
                            onClick = onNavigateToEditProfile,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 4.dp),
                            shape = RoundedCornerShape(AppTheme.radiusFull),
                            color = Color(0xFFFFF8E1),
                            border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFFFFD54F))
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("\uD83D\uDFE1", fontSize = 14.sp)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    "Complete your profile ",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = colors.textPrimary
                                )
                                Text(
                                    "for better matches",
                                    fontSize = 13.sp,
                                    color = colors.textSecondary,
                                    modifier = Modifier.weight(1f)
                                )
                                Icon(Icons.Default.ChevronRight, null, tint = AppColors.Saffron, modifier = Modifier.size(18.dp))
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }

        // ── Match Alert ──
        if (showMatchAlert && matchedUser != null) {
            val matchedMatchId by viewModel.matchedMatchId.collectAsState()
            AlertDialog(
                onDismissRequest = { viewModel.dismissMatchAlert() },
                title = { Text("It's a Match! 🎉", fontWeight = FontWeight.Bold) },
                text = { Text("You and ${matchedUser!!.displayName} liked each other!") },
                confirmButton = {
                    TextButton(onClick = {
                        val matchId = matchedMatchId
                        val user = matchedUser
                        viewModel.dismissMatchAlert()
                        if (matchId != null && user != null) onSendMessage(matchId, user)
                    }) {
                        Text("Send Message", color = AppColors.Rose)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.dismissMatchAlert() }) {
                        Text("Keep Swiping")
                    }
                }
            )
        }

        // ── Score Breakdown ──
        if (showScoreBreakdown && selectedCard != null) {
            com.mitimaiti.app.ui.components.ScoreBreakdownSheet(
                card = selectedCard!!,
                onDismiss = { viewModel.hideScoreBreakdown() }
            )
        }

        // ── Filter Sheet ──
        if (showFilters) {
            FilterSheet(
                filterState = filterState,
                onFilterChanged = {
                    filterState = it
                    // Persist to the backend and reload the deck — the feed
                    // query applies these filters server-side.
                    viewModel.applyFilters(it)
                },
                onDismiss = { showFilters = false },
                onReset = {
                    filterState = FilterState()
                    viewModel.applyFilters(FilterState())
                }
            )
        }
    }
}

private fun countActiveFilters(state: FilterState): Int {
    var count = 0
    if (state.ageMin != 21 || state.ageMax != 35) count++
    if (state.heightMin != 150 || state.heightMax != 190) count++
    if (state.genderPreference != ShowMe.EVERYONE) count++
    if (state.intentFilter != null) count++
    if (state.verifiedOnly) count++
    if (state.fluencyFilter != null) count++
    if (state.generationFilter != null) count++
    if (state.religionFilter != null) count++
    if (state.gotraFilter != null) count++
    if (state.dietaryFilter != null) count++
    if (state.educationFilter != null) count++
    if (state.smokingFilter != null) count++
    if (state.drinkingFilter != null) count++
    if (state.familyPlansFilter != null) count++
    if (state.exerciseFilter != null) count++
    return count
}

// ───────────────────────────────────────────
// Swipeable Photo Card (iOS style — single photo with overlay)
// ───────────────────────────────────────────
@Composable
private fun SwipeablePhotoCard(
    card: FeedCard,
    onSwipeRight: () -> Unit,
    onSwipeLeft: () -> Unit,
    onTap: () -> Unit
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    var swiped by remember { mutableStateOf(false) }
    val screenWidthPx = LocalConfiguration.current.screenWidthDp * LocalConfiguration.current.densityDpi / 160f
    val swipeThreshold = screenWidthPx * 0.25f

    val animatedOffset by animateFloatAsState(
        targetValue = offsetX,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        finishedListener = {
            if (swiped) {
                if (offsetX > 0) onSwipeRight() else onSwipeLeft()
                offsetX = 0f
                swiped = false
            }
        },
        label = "swipe"
    )

    val rotation = (animatedOffset / screenWidthPx) * 12f
    val likeAlpha = (animatedOffset / swipeThreshold).coerceIn(0f, 1f)
    val passAlpha = (-animatedOffset / swipeThreshold).coerceIn(0f, 1f)

    val user = card.user

    Box(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(1f)
            .offset { IntOffset(animatedOffset.roundToInt(), 0) }
            .rotate(rotation)
            .pointerInput(card.id) {
                detectDragGestures(
                    onDragEnd = {
                        when {
                            offsetX > swipeThreshold -> { swiped = true; offsetX = screenWidthPx * 1.5f }
                            offsetX < -swipeThreshold -> { swiped = true; offsetX = -screenWidthPx * 1.5f }
                            else -> offsetX = 0f
                        }
                    },
                    onDragCancel = { offsetX = 0f },
                    onDrag = { change, dragAmount -> change.consume(); offsetX += dragAmount.x }
                )
            }
            .clickable { onTap() }
    ) {
        // Photo fills the entire card
        Card(
            modifier = Modifier.fillMaxSize(),
            shape = RoundedCornerShape(20.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                AsyncImage(
                    model = user.primaryPhoto?.url ?: "",
                    contentDescription = user.displayName,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )

                // Bottom gradient overlay
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(0.45f)
                        .align(Alignment.BottomCenter)
                        .background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))
                            )
                        )
                )

                // Score badge (top right)
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = when (card.culturalScore.badge) {
                        CulturalBadge.GOLD -> AppColors.BadgeGold
                        CulturalBadge.GREEN -> AppColors.BadgeGreen
                        CulturalBadge.ORANGE -> AppColors.BadgeOrange
                        CulturalBadge.NONE -> Color.Gray
                    }.copy(alpha = 0.9f),
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(12.dp)
                ) {
                    Text(
                        "${card.culturalScore.overallScore}%",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }

                // Name, age, location overlay at bottom
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(20.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            user.displayName,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        user.age?.let {
                            Text("$it", fontSize = 20.sp, color = Color.White.copy(alpha = 0.85f))
                        }
                        if (user.isVerified) {
                            Icon(Icons.Default.Verified, "Verified", tint = AppColors.Info, modifier = Modifier.size(18.dp))
                        }
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        if (user.city.isNotEmpty()) {
                            Icon(Icons.Default.LocationOn, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(13.dp))
                            Text(user.city, fontSize = 13.sp, color = Color.White.copy(alpha = 0.7f))
                            card.distanceKm?.let {
                                Text("- ${it.toInt()}km", fontSize = 13.sp, color = Color.White.copy(alpha = 0.5f))
                            }
                        }
                        user.intent?.let { intent ->
                            Spacer(modifier = Modifier.width(4.dp))
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = Color(intent.color).copy(alpha = 0.35f)
                            ) {
                                Text(
                                    intent.displayName,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                                    fontSize = 12.sp,
                                    color = Color.White,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }

                    // Hinge-style prompt teaser (first prompt Q&A)
                    user.prompts.firstOrNull()?.let { prompt ->
                        Spacer(modifier = Modifier.height(10.dp))
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = Color.Black.copy(alpha = 0.35f)
                        ) {
                            Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                                Text(
                                    prompt.question,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White.copy(alpha = 0.7f),
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    "“${prompt.answer}”",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color.White,
                                    maxLines = 2,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }

                // LIKE overlay
                if (likeAlpha > 0f) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color.Transparent,
                        border = androidx.compose.foundation.BorderStroke(4.dp, AppColors.Success.copy(alpha = likeAlpha)),
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(32.dp)
                            .rotate(-15f)
                    ) {
                        Text(
                            "LIKE",
                            fontSize = 40.sp,
                            fontWeight = FontWeight.Black,
                            color = AppColors.Success.copy(alpha = likeAlpha),
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                        )
                    }
                }

                // NOPE overlay
                if (passAlpha > 0f) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color.Transparent,
                        border = androidx.compose.foundation.BorderStroke(4.dp, AppColors.Error.copy(alpha = passAlpha)),
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(32.dp)
                            .rotate(15f)
                    ) {
                        Text(
                            "NOPE",
                            fontSize = 40.sp,
                            fontWeight = FontWeight.Black,
                            color = AppColors.Error.copy(alpha = passAlpha),
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                        )
                    }
                }
            }
        }
    }
}
