package com.mitimaiti.app.ui.auth

import androidx.compose.animation.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import com.mitimaiti.app.R
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import kotlinx.coroutines.delay

@Composable
fun WelcomeScreen(
    onGetStarted: () -> Unit,
    onGuidelines: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onTerms: () -> Unit = {}
) {
    val colors = LocalAdaptiveColors.current
    var isVisible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(300); isVisible = true }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.backgroundGradient)
            .verticalScroll(rememberScrollState())
    ) {
        // ── Hero Section ──
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        listOf(AppColors.Rose.copy(alpha = 0.08f), Color.Transparent)
                    )
                )
                .statusBarsPadding()
                .padding(horizontal = 32.dp, vertical = 48.dp),
            contentAlignment = Alignment.Center
        ) {
            androidx.compose.animation.AnimatedVisibility(visible = isVisible, enter = fadeIn() + slideInVertically { -40 }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Image(
                        painter = painterResource(id = R.drawable.logo_mark),
                        contentDescription = "MitiMaiti",
                        modifier = Modifier.size(104.dp)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "MitiMaiti",
                        fontSize = 52.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Rose
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Where Sindhi Hearts Connect",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppColors.Gold
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "Find meaningful connections rooted in Sindhi culture, values, and traditions",
                        fontSize = 16.sp,
                        color = colors.textSecondary,
                        textAlign = TextAlign.Center,
                        lineHeight = 24.sp
                    )
                    Spacer(modifier = Modifier.height(32.dp))

                    // CTA buttons
                    Button(
                        onClick = onGetStarted,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
                    ) {
                        Text("Get Started", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedButton(
                        onClick = onGetStarted,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, AppColors.Rose)
                    ) {
                        Text("Already have an account? Sign in", fontSize = 15.sp, color = AppColors.Rose)
                    }
                }
            }
        }

        // ── How It Works Section ──
        androidx.compose.animation.AnimatedVisibility(visible = isVisible, enter = fadeIn() + slideInVertically { 60 }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surfaceMedium)
                    .padding(horizontal = 24.dp, vertical = 32.dp)
            ) {
                Text(
                    "How It Works",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(24.dp))

                StepCard(1, "Create Your Profile", "Share your story, photos, and what makes you uniquely Sindhi")
                Spacer(modifier = Modifier.height(12.dp))
                StepCard(2, "Discover Matches", "Our cultural scoring helps you find truly compatible connections")
                Spacer(modifier = Modifier.height(12.dp))
                StepCard(3, "Connect & Chat", "Start meaningful conversations with respect-first messaging")
            }
        }

        // ── Features Section ──
        androidx.compose.animation.AnimatedVisibility(visible = isVisible, enter = fadeIn() + slideInVertically { 80 }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 32.dp)
            ) {
                Text(
                    "Why MitiMaiti?",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Built by the community, for the community",
                    fontSize = 14.sp,
                    color = colors.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(24.dp))

                // 2-column grid of features
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FeatureCard(Icons.Default.AutoAwesome, "Cultural Compatibility", "Scored on language, values, and traditions", Modifier.weight(1f))
                    FeatureCard(Icons.Default.FamilyRestroom, "Family Mode", "Let family help find your match", Modifier.weight(1f))
                }
                Spacer(modifier = Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FeatureCard(Icons.Default.VerifiedUser, "Verified Profiles", "Photo verification for trust", Modifier.weight(1f))
                    FeatureCard(Icons.Default.Public, "Global Network", "Sindhi singles worldwide", Modifier.weight(1f))
                }
                Spacer(modifier = Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FeatureCard(Icons.Default.Favorite, "Kundli Matching", "Traditional compatibility scoring", Modifier.weight(1f))
                    FeatureCard(Icons.Default.Forum, "Respectful Chat", "24-hour reply window", Modifier.weight(1f))
                }
            }
        }

        // ── Bottom CTA Section ──
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(AppColors.Rose, AppColors.RoseDark)))
                .padding(horizontal = 32.dp, vertical = 40.dp),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "Ready to find your person?",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Join thousands of Sindhi singles already on MitiMaiti",
                    fontSize = 15.sp,
                    color = Color.White.copy(alpha = 0.8f),
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = onGetStarted,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(AppTheme.radiusLg),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White)
                ) {
                    Text("Get Started", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Rose)
                }
            }
        }

        // ── Footer ──
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.cardDark)
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("MitiMaiti", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AppColors.Rose)
            Spacer(modifier = Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                TextButton(onClick = onTerms) { Text("Terms", fontSize = 13.sp, color = colors.textMuted) }
                TextButton(onClick = onPrivacy) { Text("Privacy", fontSize = 13.sp, color = colors.textMuted) }
                TextButton(onClick = onGuidelines) { Text("Guidelines", fontSize = 13.sp, color = colors.textMuted) }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "\u00A9 2026 MitiMaiti. All rights reserved.",
                fontSize = 12.sp,
                color = colors.textMuted
            )
        }
    }
}

@Composable
private fun StepCard(number: Int, title: String, description: String) {
    val colors = LocalAdaptiveColors.current
    Surface(
        shape = RoundedCornerShape(AppTheme.radiusMd),
        color = colors.surface
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(AppColors.Rose, AppColors.RoseLight))),
                contentAlignment = Alignment.Center
            ) {
                Text("$number", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(description, fontSize = 13.sp, color = colors.textSecondary, lineHeight = 18.sp)
            }
        }
    }
}

@Composable
private fun FeatureCard(icon: ImageVector, title: String, description: String, modifier: Modifier = Modifier) {
    val colors = LocalAdaptiveColors.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(AppTheme.radiusMd),
        color = colors.surface
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(AppColors.Rose.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, null, tint = AppColors.Rose, modifier = Modifier.size(22.dp))
            }
            Spacer(modifier = Modifier.height(10.dp))
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.height(4.dp))
            Text(description, fontSize = 12.sp, color = colors.textSecondary, textAlign = TextAlign.Center, lineHeight = 16.sp)
        }
    }
}
