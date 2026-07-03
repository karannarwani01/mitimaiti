@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import coil.compose.AsyncImage
import androidx.compose.foundation.BorderStroke
import com.mitimaiti.app.models.CulturalBadge
import com.mitimaiti.app.models.LikedYouCard
import com.mitimaiti.app.ui.components.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.InboxViewModel
import kotlin.math.roundToInt

@Composable
fun LikedYouScreen(viewModel: InboxViewModel) {
    val colors = LocalAdaptiveColors.current
    val likes by viewModel.likes.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.backgroundGradient)
            .statusBarsPadding()
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    "Liked You",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                if (likes.isNotEmpty()) {
                    Text(
                        "${likes.size} people",
                        fontSize = 14.sp,
                        color = colors.textSecondary
                    )
                }
            }
        }

        if (isLoading) {
            Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                ShimmerDiscoverCard()
            }
        } else if (likes.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                EmptyState(
                    icon = Icons.Default.FavoriteBorder,
                    title = "No likes yet",
                    description = "When someone likes your profile, they'll appear here"
                )
            }
        } else {
            val featuredLike = likes.first()
            val upNextLikes = likes.drop(1).take(3)
            val gridLikes = likes.drop(4)

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 16.dp)
            ) {
                // Featured card with swipe gestures
                item(key = "featured_${featuredLike.id}") {
                    FeaturedLikeCard(
                        like = featuredLike,
                        onLikeBack = { viewModel.likeBack(featuredLike.id) },
                        onPass = { viewModel.passLike(featuredLike.id) }
                    )
                }

                // Up Next section
                if (upNextLikes.isNotEmpty()) {
                    item(key = "up_next_header") {
                        Text(
                            "Up Next",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = colors.textPrimary,
                            modifier = Modifier.padding(
                                start = 20.dp,
                                top = 20.dp,
                                bottom = 12.dp
                            )
                        )
                    }

                    item(key = "up_next_row") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            upNextLikes.forEachIndexed { index, like ->
                                // Staggered fade-in animation
                                val itemAlpha = remember { Animatable(0f) }
                                LaunchedEffect(like.id) {
                                    kotlinx.coroutines.delay(index * 80L)
                                    itemAlpha.animateTo(1f, tween(300))
                                }
                                Box(
                                    modifier = Modifier
                                        .width(120.dp)
                                        .height(150.dp)
                                        .alpha(itemAlpha.value)
                                ) {
                                    UpNextCard(
                                        like = like,
                                        onLikeBack = { viewModel.likeBack(like.id) },
                                        onPass = { viewModel.passLike(like.id) }
                                    )
                                }
                            }
                        }
                    }
                }

                // Remaining grid
                if (gridLikes.isNotEmpty()) {
                    item(key = "grid_header") {
                        Text(
                            "More Likes",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = colors.textPrimary,
                            modifier = Modifier.padding(
                                start = 20.dp,
                                top = 20.dp,
                                bottom = 12.dp
                            )
                        )
                    }

                    // 2-column grid using chunked rows
                    val rows = gridLikes.chunked(2)
                    items(rows, key = { row -> row.map { it.id }.joinToString("_") }) { row ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp)
                                .padding(bottom = 10.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            row.forEach { like ->
                                Box(modifier = Modifier.weight(1f)) {
                                    LikeCard(
                                        like = like,
                                        onLikeBack = { viewModel.likeBack(like.id) },
                                        onPass = { viewModel.passLike(like.id) }
                                    )
                                }
                            }
                            if (row.size == 1) {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FeaturedLikeCard(
    like: LikedYouCard,
    onLikeBack: () -> Unit,
    onPass: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val user = like.user
    val view = LocalView.current

    // Entrance animation
    val entranceScale = remember { Animatable(0.95f) }
    val entranceAlpha = remember { Animatable(0f) }
    LaunchedEffect(like.id) {
        launch { entranceScale.animateTo(1f, spring(dampingRatio = 0.75f, stiffness = 300f)) }
        launch { entranceAlpha.animateTo(1f, spring(dampingRatio = 0.75f, stiffness = 300f)) }
    }

    var offsetX by remember { mutableFloatStateOf(0f) }
    var swiped by remember { mutableStateOf(false) }
    val screenWidthPx = LocalConfiguration.current.screenWidthDp * LocalConfiguration.current.densityDpi / 160f
    val swipeThreshold = screenWidthPx * 0.25f

    val animatedOffset by animateFloatAsState(
        targetValue = offsetX,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        finishedListener = {
            if (swiped) {
                if (offsetX > 0) onLikeBack() else onPass()
                offsetX = 0f
                swiped = false
            }
        },
        label = "featured_swipe"
    )

    val rotation = (animatedOffset / screenWidthPx) * 15f
    val likeAlpha = (animatedOffset / swipeThreshold).coerceIn(0f, 1f)
    val nopeAlpha = (-animatedOffset / swipeThreshold).coerceIn(0f, 1f)

    Card(
        shape = RoundedCornerShape(AppTheme.radiusXl),
        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .graphicsLayer {
                scaleX = entranceScale.value
                scaleY = entranceScale.value
                alpha = entranceAlpha.value
            }
            .offset { IntOffset(animatedOffset.roundToInt(), 0) }
            .graphicsLayer { rotationZ = rotation }
            .pointerInput(like.id) {
                detectDragGestures(
                    onDragEnd = {
                        when {
                            offsetX > swipeThreshold -> {
                                swiped = true
                                offsetX = screenWidthPx * 1.5f
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            }
                            offsetX < -swipeThreshold -> {
                                swiped = true
                                offsetX = -screenWidthPx * 1.5f
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            }
                            else -> offsetX = 0f
                        }
                    },
                    onDragCancel = { offsetX = 0f },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        offsetX += dragAmount.x
                    }
                )
            }
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.75f)
        ) {
            // Photo
            AsyncImage(
                model = user.primaryPhoto?.url ?: "",
                contentDescription = user.displayName,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            // Bottom gradient
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.55f)
                    .align(Alignment.BottomCenter)
                    .background(
                        Brush.verticalGradient(
                            colorStops = arrayOf(
                                0.0f to Color.Transparent,
                                0.35f to Color.Black.copy(alpha = 0.05f),
                                0.6f to Color.Black.copy(alpha = 0.25f),
                                0.85f to Color.Black.copy(alpha = 0.65f),
                                1.0f to Color.Black.copy(alpha = 0.80f)
                            )
                        )
                    )
            )

            // Cultural badge - top right (shared component)
            CulturalScoreBadge(
                score = like.culturalScore,
                badge = like.culturalBadge,
                modifier = Modifier.align(Alignment.TopEnd).padding(12.dp)
            )

            // "What they liked" pill — top left. Real server-backed label only:
            // a comment means they wrote a note (shown below); otherwise it
            // was a plain profile like. No invented "liked your vibe" claims.
            val likedLabel = if (like.likeComment != null) "Commented on your profile" else "Liked your profile"
            Surface(
                shape = RoundedCornerShape(AppTheme.radiusFull),
                color = AppColors.Rose.copy(alpha = 0.9f),
                modifier = Modifier.align(Alignment.TopStart).padding(12.dp)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Favorite, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(likedLabel, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }

            // LIKE overlay (bordered style)
            if (likeAlpha > 0f) {
                Box(modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(AppTheme.radiusXl)), contentAlignment = Alignment.TopStart) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color.Transparent,
                        border = BorderStroke(3.dp, AppColors.Success.copy(alpha = likeAlpha)),
                        modifier = Modifier.padding(28.dp).rotate(-15f)
                    ) {
                        Text("LIKE", fontSize = 36.sp, fontWeight = FontWeight.Black, color = AppColors.Success.copy(alpha = likeAlpha), modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    }
                }
            }

            // NOPE overlay (bordered style)
            if (nopeAlpha > 0f) {
                Box(modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(AppTheme.radiusXl)), contentAlignment = Alignment.TopEnd) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color.Transparent,
                        border = BorderStroke(3.dp, AppColors.Error.copy(alpha = nopeAlpha)),
                        modifier = Modifier.padding(28.dp).rotate(15f)
                    ) {
                        Text("NOPE", fontSize = 36.sp, fontWeight = FontWeight.Black, color = AppColors.Error.copy(alpha = nopeAlpha), modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    }
                }
            }

            // Info at bottom
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
                // Their note (like-with-comment) — the reason this card is up top
                like.likeComment?.let { note ->
                    Surface(
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        color = Color.Black.copy(alpha = 0.55f),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.25f))
                    ) {
                        Text(
                            "“$note”",
                            fontSize = 14.sp,
                            color = Color.White,
                            maxLines = 4,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(10.dp))
                }
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        user.displayName,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    user.age?.let {
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "$it",
                            fontSize = 24.sp,
                            color = Color.White.copy(alpha = 0.8f)
                        )
                    }
                }
                if (user.city.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.LocationOn,
                            "Location",
                            tint = Color.White.copy(alpha = 0.7f),
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                        Text(
                            user.city,
                            fontSize = 15.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }

                // Timestamp
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    formatLikeTimestamp(like.likedAt),
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.5f)
                )

                Spacer(modifier = Modifier.height(16.dp))

                // Action buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    // Pass button
                    FloatingActionButton(
                        onClick = onPass,
                        containerColor = Color.White.copy(alpha = 0.2f),
                        contentColor = Color.White,
                        shape = CircleShape,
                        modifier = Modifier.size(52.dp),
                        elevation = FloatingActionButtonDefaults.elevation(0.dp)
                    ) {
                        Icon(
                            Icons.Default.Close,
                            "Pass",
                            modifier = Modifier.size(26.dp)
                        )
                    }
                    // Like back button
                    FloatingActionButton(
                        onClick = onLikeBack,
                        containerColor = AppColors.Rose,
                        contentColor = Color.White,
                        shape = CircleShape,
                        modifier = Modifier.size(52.dp)
                    ) {
                        Icon(
                            Icons.Default.Favorite,
                            "Like Back",
                            modifier = Modifier.size(26.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun UpNextCard(
    like: LikedYouCard,
    onLikeBack: () -> Unit,
    onPass: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val user = like.user

    Card(
        shape = RoundedCornerShape(AppTheme.radiusMd),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.7f)
        ) {
            // Photo
            AsyncImage(
                model = user.primaryPhoto?.url ?: "",
                contentDescription = user.displayName,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            // Bottom gradient
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.6f)
                    .align(Alignment.BottomCenter)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))
                        )
                    )
            )

            // Cultural badge (shared component)
            CulturalScoreBadge(
                score = like.culturalScore,
                badge = like.culturalBadge,
                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp)
            )

            // Info at bottom
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(8.dp)
            ) {
                Text(
                    "${user.displayName}, ${user.age ?: ""}",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (user.city.isNotEmpty()) {
                    Text(user.city, fontSize = 10.sp, color = Color.White.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(formatLikeTimestamp(like.likedAt), fontSize = 9.sp, color = Color.White.copy(alpha = 0.5f))
            }
        }
    }
}

@Composable
fun LikeCard(
    like: LikedYouCard,
    onLikeBack: () -> Unit,
    onPass: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val user = like.user

    Card(
        shape = RoundedCornerShape(AppTheme.radiusLg),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.75f)
        ) {
            // Photo
            AsyncImage(
                model = user.primaryPhoto?.url ?: "",
                contentDescription = user.displayName,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            // Bottom gradient
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.55f)
                    .align(Alignment.BottomCenter)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))
                        )
                    )
            )

            // Cultural badge (shared component)
            CulturalScoreBadge(
                score = like.culturalScore,
                badge = like.culturalBadge,
                modifier = Modifier.align(Alignment.TopEnd).padding(8.dp)
            )

            // Like label badge - top left
            Surface(
                shape = RoundedCornerShape(bottomEnd = AppTheme.radiusSm),
                color = AppColors.Rose.copy(alpha = 0.85f),
                modifier = Modifier.align(Alignment.TopStart)
            ) {
                Text(
                    "Liked your profile",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    fontSize = 9.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White
                )
            }

            // Info at bottom
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(10.dp)
            ) {
                // One-line preview of their like-with-comment note
                like.likeComment?.let { note ->
                    Text(
                        "💬 “$note”",
                        fontSize = 12.sp,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                }
                Text(
                    "${user.displayName}, ${user.age ?: ""}",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (user.city.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.LocationOn,
                            "Location",
                            tint = Color.White.copy(alpha = 0.7f),
                            modifier = Modifier.size(12.dp)
                        )
                        Text(
                            user.city,
                            fontSize = 12.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }

                // Timestamp
                Text(
                    formatLikeTimestamp(like.likedAt),
                    fontSize = 10.sp,
                    color = Color.White.copy(alpha = 0.5f)
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Action buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    // Pass button
                    IconButton(
                        onClick = onPass,
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.2f))
                    ) {
                        Icon(
                            Icons.Default.Close,
                            "Pass",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                    // Like back button
                    IconButton(
                        onClick = onLikeBack,
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(AppColors.Rose.copy(alpha = 0.8f))
                    ) {
                        Icon(
                            Icons.Default.Favorite,
                            "Like Back",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }
    }
}

/**
 * Formats a like timestamp into a relative time string.
 */
private fun formatLikeTimestamp(likedAt: Long): String {
    val now = System.currentTimeMillis()
    val diff = now - likedAt
    val minutes = diff / (1000 * 60)
    val hours = minutes / 60
    val days = hours / 24

    return when {
        minutes < 1 -> "Just now"
        minutes < 60 -> "${minutes}m ago"
        hours < 24 -> "${hours}h ago"
        days < 7 -> "${days}d ago"
        else -> "${days / 7}w ago"
    }
}
