package com.mitimaiti.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.mitimaiti.app.models.CulturalBadge
import com.mitimaiti.app.models.FeedCard
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors

/**
 * Full profile view opened by tapping a Discover card (Hinge-style).
 * Mirrors iOS DiscoverView.ProfileDetailSheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileDetailSheet(
    card: FeedCard,
    onLike: () -> Unit,
    onPass: () -> Unit,
    onShowScore: () -> Unit,
    onDismiss: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val user = card.user

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp)
        ) {
            // Photo header
            AsyncImage(
                model = user.primaryPhoto?.url ?: "",
                contentDescription = user.displayName,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(320.dp)
                    .clip(RoundedCornerShape(16.dp)),
                contentScale = ContentScale.Crop
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Name + age + verified
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(user.displayName, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
                user.age?.let { Text("$it", fontSize = 20.sp, color = colors.textSecondary) }
                if (user.isVerified) {
                    Icon(Icons.Default.Verified, "Verified", tint = AppColors.Info, modifier = Modifier.size(20.dp))
                }
            }

            // Location
            if (user.city.isNotEmpty()) {
                Spacer(modifier = Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Default.LocationOn, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp))
                    Text(user.city, fontSize = 14.sp, color = colors.textSecondary)
                    card.distanceKm?.let { Text("· ${it.toInt()} km", fontSize = 14.sp, color = colors.textMuted) }
                }
            }

            // Intent chip
            user.intent?.let { intent ->
                Spacer(modifier = Modifier.height(8.dp))
                Surface(shape = RoundedCornerShape(AppTheme.radiusFull), color = Color(intent.color).copy(alpha = 0.15f)) {
                    Text(
                        "${intent.emoji} ${intent.displayName}",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color(intent.color)
                    )
                }
            }

            // Voice intro (Hinge-style)
            user.voiceIntroUrl?.let { url ->
                Spacer(modifier = Modifier.height(10.dp))
                VoiceIntroPill(url = url)
            }

            // Score chips (tap → full breakdown)
            Spacer(modifier = Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Surface(
                    onClick = onShowScore,
                    shape = RoundedCornerShape(AppTheme.radiusFull),
                    color = when (card.culturalScore.badge) {
                        CulturalBadge.GOLD -> AppColors.BadgeGold
                        CulturalBadge.GREEN -> AppColors.BadgeGreen
                        CulturalBadge.ORANGE -> AppColors.BadgeOrange
                        CulturalBadge.NONE -> Color.Gray
                    }.copy(alpha = 0.9f)
                ) {
                    Text(
                        "✨ Cultural ${card.culturalScore.overallScore}%",
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
                card.kundliScore?.let { k ->
                    Surface(onClick = onShowScore, shape = RoundedCornerShape(AppTheme.radiusFull), color = AppColors.BadgeGold.copy(alpha = 0.25f)) {
                        Text(
                            "⭐ Kundli ${k.totalScore.toInt()}/${k.maxScore.toInt()}",
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.BadgeGold
                        )
                    }
                }
            }

            // Bio
            if (user.bio.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                SectionCard(colors.surfaceMedium) {
                    Text(user.bio, fontSize = 15.sp, color = colors.textSecondary, lineHeight = 22.sp)
                }
            }

            // Prompts (Hinge-style Q&A)
            user.prompts.forEach { prompt ->
                Spacer(modifier = Modifier.height(10.dp))
                SectionCard(colors.surfaceMedium) {
                    Text(prompt.question, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = AppColors.BadgeGold)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(prompt.answer, fontSize = 15.sp, color = colors.textPrimary)
                }
            }

            // Sindhi identity + basics
            val identityRows = listOfNotNull(
                user.sindhiFluency?.let { "Sindhi fluency" to it.displayName },
                user.foodPreference?.let { "Food preference" to it.displayName },
                user.familyValues?.let { "Family values" to it.displayName },
                user.heightCm?.let { "Height" to "$it cm" },
                user.education?.takeIf { it.isNotBlank() }?.let { "Education" to it },
                user.occupation?.takeIf { it.isNotBlank() }?.let { "Work" to it },
                user.religion?.takeIf { it.isNotBlank() }?.let { "Religion" to it },
            )
            if (identityRows.isNotEmpty()) {
                Spacer(modifier = Modifier.height(10.dp))
                SectionCard(colors.surfaceMedium) {
                    Text("🪔 Sindhi Roots & Basics", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    Spacer(modifier = Modifier.height(8.dp))
                    identityRows.forEach { (label, value) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 3.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(label, fontSize = 13.sp, color = colors.textMuted)
                            Text(value, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                        }
                    }
                }
            }

            // Interests
            if (user.interests.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text("Interests", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Spacer(modifier = Modifier.height(8.dp))
                @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    user.interests.forEach { interest ->
                        Surface(shape = RoundedCornerShape(AppTheme.radiusFull), color = colors.surfaceMedium) {
                            Text(
                                interest,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = colors.textPrimary
                            )
                        }
                    }
                }
            }

            // Pass / Like
            Spacer(modifier = Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Button(
                    onClick = onPass,
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(AppTheme.radiusFull),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.surfaceMedium, contentColor = colors.textSecondary)
                ) {
                    Icon(Icons.Default.Close, null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Pass", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
                Button(
                    onClick = onLike,
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(AppTheme.radiusFull),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose, contentColor = Color.White)
                ) {
                    Icon(Icons.Default.Favorite, null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Like", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun SectionCard(color: Color, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), color = color) {
        Column(modifier = Modifier.padding(14.dp), content = content)
    }
}

/** Tap-to-play pill for a profile's voice introduction. */
@Composable
fun VoiceIntroPill(url: String) {
    var isPlaying by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    val player = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf<android.media.MediaPlayer?>(null) }

    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose {
            player.value?.release()
            player.value = null
        }
    }

    Surface(
        onClick = {
            if (isPlaying) {
                player.value?.stop(); player.value?.release(); player.value = null
                isPlaying = false
            } else {
                try {
                    val mp = android.media.MediaPlayer()
                    mp.setDataSource(url)
                    mp.setOnPreparedListener { it.start() }
                    mp.setOnCompletionListener { isPlaying = false; it.release(); player.value = null }
                    mp.prepareAsync()
                    player.value = mp
                    isPlaying = true
                } catch (e: Exception) { isPlaying = false }
            }
        },
        shape = RoundedCornerShape(AppTheme.radiusFull),
        color = AppColors.Rose.copy(alpha = 0.12f),
        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.4f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(if (isPlaying) "⏸" else "▶", fontSize = 14.sp, color = AppColors.Rose)
            Text(
                if (isPlaying) "Playing voice intro…" else "Play voice intro",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.Rose
            )
        }
    }
}
