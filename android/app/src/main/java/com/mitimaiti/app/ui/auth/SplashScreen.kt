package com.mitimaiti.app.ui.auth

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.navigation.SplashDestination
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(
    resolveDestination: suspend () -> SplashDestination,
    onFinished: (SplashDestination) -> Unit
) {
    val colors = LocalAdaptiveColors.current

    // Animation states
    var contentScale by remember { mutableFloatStateOf(0.5f) }
    var contentAlpha by remember { mutableFloatStateOf(0f) }
    var heartBeat by remember { mutableStateOf(false) }

    val animatedScale by animateFloatAsState(
        targetValue = contentScale,
        animationSpec = spring(dampingRatio = 0.65f, stiffness = 200f),
        label = "scale"
    )
    val animatedAlpha by animateFloatAsState(
        targetValue = contentAlpha,
        animationSpec = tween(700),
        label = "alpha"
    )

    // Pulsing animation for heart and circles
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 0.85f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(1800, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseScale"
    )
    val heartScale by infiniteTransition.animateFloat(
        initialValue = 0.96f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "heartScale"
    )

    LaunchedEffect(Unit) {
        heartBeat = true
        contentScale = 1f
        contentAlpha = 1f
        // Run the auth check in parallel with the minimum splash duration.
        // Whichever takes longer determines when we navigate; auth check exceeds
        // the animation only on a Render cold start (~30s) where we'd rather
        // wait than dump the user onto Welcome and lose their valid session.
        val destination = coroutineScope {
            val authJob = async { resolveDestination() }
            delay(2500)
            authJob.await()
        }
        onFinished(destination)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(
                listOf(colors.background, colors.surfaceMedium, colors.background)
            )),
        contentAlignment = Alignment.Center
    ) {
        // Pulsing rose circles
        Box(contentAlignment = Alignment.Center) {
            repeat(3) { i ->
                Box(
                    modifier = Modifier
                        .size((200 + i * 100).dp)
                        .scale(pulseScale)
                        .background(AppColors.Rose.copy(alpha = 0.05f), CircleShape)
                )
            }
        }

        // Content
        Column(
            modifier = Modifier
                .scale(animatedScale)
                .then(Modifier),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Heart icon with glow
            Box(contentAlignment = Alignment.Center) {
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .scale(if (heartBeat) 1.2f else 0.9f)
                        .blur(18.dp)
                        .background(AppColors.Rose.copy(alpha = 0.12f), CircleShape)
                )
                Icon(
                    imageVector = Icons.Filled.Favorite,
                    contentDescription = null,
                    modifier = Modifier
                        .size(56.dp)
                        .scale(heartScale),
                    tint = AppColors.Rose
                )
            }

            // Title
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = "MitiMaiti",
                    fontSize = 40.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                Text(
                    text = "Where Sindhi Hearts Meet",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppColors.Gold
                )
            }
        }
    }
}
