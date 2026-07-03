@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.mitimaiti.app.utils.ImageCompression
import com.mitimaiti.app.models.Intent
import com.mitimaiti.app.models.User
import com.mitimaiti.app.services.PhotoRepository
import com.mitimaiti.app.ui.components.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.ProfileViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onEditProfile: () -> Unit,
    onSettings: () -> Unit,
    onLogout: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val context = LocalContext.current
    val user by viewModel.user.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val repoPhotos by PhotoRepository.photos.collectAsState()
    val completeness by viewModel.completenessFlow.collectAsState()
    var showPhotoPicker by remember { mutableStateOf(false) }

    // ── Selfie verification camera flow ──
    val isVerifying by viewModel.isVerifying.collectAsState()
    val verifyMessage by viewModel.verifyMessage.collectAsState()
    val pendingSelfieUri = remember { mutableStateOf<Uri?>(null) }

    val selfieLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success: Boolean ->
        val uri = pendingSelfieUri.value
        pendingSelfieUri.value = null
        if (!success || uri == null) return@rememberLauncherForActivityResult
        val bytes = ImageCompression.compressForUpload(context, uri)
        if (bytes != null) viewModel.verifySelfie(bytes)
        else Toast.makeText(context, "Couldn't read the selfie. Please try again.", Toast.LENGTH_SHORT).show()
    }

    fun launchSelfieCamera() {
        val photoFile = java.io.File(context.cacheDir, "verify_selfie_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photoFile)
        pendingSelfieUri.value = uri
        selfieLauncher.launch(uri)
    }

    val selfiePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) launchSelfieCamera()
        else Toast.makeText(context, "Camera permission is needed to take a verification selfie", Toast.LENGTH_SHORT).show()
    }

    fun startVerification() {
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) launchSelfieCamera() else selfiePermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    // Verification result dialog
    verifyMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissVerifyMessage() },
            title = { Text(if (user?.isVerified == true) "Verified! ✅" else "Verification") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissVerifyMessage() }) { Text("OK", color = AppColors.Rose) }
            }
        )
    }

    if (isLoading || user == null) {
        Column(
            modifier = Modifier.fillMaxSize().statusBarsPadding().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            ShimmerProfileCard()
        }
        return
    }

    val profile = user!!
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.backgroundGradient)
            .statusBarsPadding()
            .verticalScroll(scrollState)
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Profile",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary
            )
            IconButton(onClick = onSettings) {
                Icon(Icons.Default.Settings, "Settings", tint = colors.textSecondary)
            }
        }

        // Profile card with gradient header + avatar
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            shape = RoundedCornerShape(AppTheme.radiusCard),
            color = colors.surface,
            shadowElevation = 4.dp
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // Gradient header
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(100.dp)
                        .background(
                            Brush.linearGradient(listOf(AppColors.Rose, AppColors.RoseDark))
                        ),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    // Avatar overlapping the gradient
                    Box(
                        modifier = Modifier
                            .offset(y = 40.dp)
                            .size(88.dp)
                            .clip(CircleShape)
                            .background(Color.White, CircleShape)
                            .border(3.dp, Color.White, CircleShape)
                            .clickable { showPhotoPicker = true },
                        contentAlignment = Alignment.Center
                    ) {
                        AsyncImage(
                            model = PhotoRepository.primaryPhotoUri
                                ?: profile.primaryPhoto?.url
                                ?: "",
                            contentDescription = profile.displayName,
                            modifier = Modifier
                                .size(82.dp)
                                .clip(CircleShape),
                            contentScale = ContentScale.Crop
                        )
                    }
                }

                // Camera badge
                Box(
                    modifier = Modifier
                        .offset(x = 30.dp, y = (-4).dp)
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(AppColors.Rose, CircleShape)
                        .border(2.dp, Color.White, CircleShape)
                        .clickable { showPhotoPicker = true },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Default.CameraAlt, null,
                        tint = Color.White,
                        modifier = Modifier.size(14.dp)
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Name, age, verified
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        profile.displayName,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.textPrimary
                    )
                    profile.age?.let {
                        Text(", $it", fontSize = 20.sp, color = colors.textSecondary)
                    }
                    if (profile.isVerified) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Icon(
                            Icons.Default.Verified, "Verified",
                            tint = AppColors.Info,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }

                // Location
                if (profile.city.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.LocationOn, null,
                            tint = colors.textMuted,
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                        Text(
                            "${profile.city}, ${profile.country}",
                            fontSize = 14.sp,
                            color = colors.textSecondary
                        )
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Edit Profile button
                OutlinedButton(
                    onClick = onEditProfile,
                    shape = RoundedCornerShape(AppTheme.radiusFull),
                    border = BorderStroke(1.dp, AppColors.Rose),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.Rose),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 6.dp)
                ) {
                    Icon(Icons.Default.Edit, null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Edit Profile", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Profile Completeness card
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            shape = RoundedCornerShape(AppTheme.radiusMd),
            color = colors.surface,
            shadowElevation = 2.dp
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "Profile Completeness",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.textPrimary
                    )
                    Text(
                        "${completeness}%",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Rose
                    )
                }
                Spacer(modifier = Modifier.height(10.dp))
                LinearProgressIndicator(
                    progress = { completeness / 100f },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(8.dp)
                        .clip(RoundedCornerShape(4.dp)),
                    color = AppColors.Rose,
                    trackColor = colors.border,
                    drawStopIndicator = {}
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    "Complete your profile to get better matches",
                    fontSize = 12.sp,
                    color = colors.textMuted
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Get Verified card (Bumble-style photo verification)
        if (!profile.isVerified) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                shape = RoundedCornerShape(AppTheme.radiusMd),
                color = colors.surface,
                shadowElevation = 2.dp
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Verified, null,
                        tint = AppColors.Info,
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Get Verified",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.textPrimary
                        )
                        Text(
                            "Take a quick selfie to earn the blue badge. Your selfie is never stored.",
                            fontSize = 12.sp,
                            color = colors.textMuted
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = { startVerification() },
                        enabled = !isVerifying,
                        shape = RoundedCornerShape(AppTheme.radiusFull),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp)
                    ) {
                        if (isVerifying) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                color = Color.White,
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text("Verify", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
        }

        // Stats row — three separate cards with circular icon badges (matches web design)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            StatCard(
                icon = Icons.Default.Visibility,
                value = viewModel.profileStats.views.toString(),
                label = "Views",
                accent = AppColors.Rose,
                modifier = Modifier.weight(1f),
                colors = colors
            )
            StatCard(
                icon = Icons.Default.FavoriteBorder,
                value = viewModel.profileStats.likes.toString(),
                label = "Likes",
                accent = AppColors.Rose,
                modifier = Modifier.weight(1f),
                colors = colors
            )
            StatCard(
                icon = Icons.Default.ChatBubbleOutline,
                value = viewModel.profileStats.matches.toString(),
                label = "Matches",
                accent = Color(0xFF3B82F6), // blue-500 for Matches (matches web)
                modifier = Modifier.weight(1f),
                colors = colors
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Profile sections with field counts
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            shape = RoundedCornerShape(AppTheme.radiusMd),
            color = colors.surface,
            shadowElevation = 2.dp
        ) {
            Column {
                val basicsFields = listOf(profile.education, profile.occupation, profile.company,
                    profile.heightCm?.toString(), profile.religion, profile.smoking, profile.drinking, profile.exercise)
                val basicsCount = basicsFields.count { !it.isNullOrEmpty() }

                val sindhiFields = listOf(profile.sindhiFluency?.displayName, profile.sindhiDialect,
                    profile.generation, profile.gotra, profile.familyOriginCity)
                val sindhiCount = sindhiFields.count { !it.isNullOrEmpty() }

                val chattiFields = listOf(profile.wantKids, profile.settlingTimeline, profile.exercise,
                    profile.smoking, profile.drinking, profile.religion, profile.bio.ifEmpty { null })
                val chattiCount = chattiFields.count { !it.isNullOrEmpty() }

                val cultureFields = listOf(profile.familyValues?.displayName,
                    profile.foodPreference?.displayName, profile.festivalsCelebrated.ifEmpty { null }?.toString())
                val cultureCount = cultureFields.count { it != null }

                val personalityFields = listOf(
                    profile.interests.ifEmpty { null }?.toString(),
                    profile.musicPreferences.ifEmpty { null }?.toString(),
                    profile.movieGenres.ifEmpty { null }?.toString(),
                    profile.travelStyle,
                    profile.languages.ifEmpty { null }?.toString()
                )
                val personalityCount = personalityFields.count { !it.isNullOrEmpty() }

                ProfileSectionRow("My Basics", "$basicsCount/8 fields", onEditProfile)
                HorizontalDivider(color = colors.border.copy(alpha = 0.5f))
                ProfileSectionRow("My Sindhi Identity", "$sindhiCount/5 fields", onEditProfile)
                HorizontalDivider(color = colors.border.copy(alpha = 0.5f))
                ProfileSectionRow("My Chatti", "$chattiCount/7 fields", onEditProfile)
                HorizontalDivider(color = colors.border.copy(alpha = 0.5f))
                ProfileSectionRow("My Culture", "$cultureCount/3 fields", onEditProfile)
                HorizontalDivider(color = colors.border.copy(alpha = 0.5f))
                ProfileSectionRow("My Personality", "$personalityCount/5 fields", onEditProfile)
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // Primary photo picker sheet
    if (showPhotoPicker) {
        PrimaryPhotoPickerSheet(
            existingPhotos = repoPhotos.map { it.uri },
            onDismiss = { showPhotoPicker = false },
            onNewPhotoFromGallery = { uri ->
                viewModel.addPhoto(uri)
                val newIndex = PhotoRepository.photos.value.indexOfFirst { it.uri == uri }
                if (newIndex > 0) viewModel.setPrimaryPhoto(newIndex)
            },
            onSetPrimary = { index -> viewModel.setPrimaryPhoto(index) }
        )
    }
}

@Composable
private fun StatCard(
    icon: ImageVector,
    value: String,
    label: String,
    accent: Color,
    modifier: Modifier = Modifier,
    colors: com.mitimaiti.app.ui.theme.AdaptiveColors
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(AppTheme.radiusMd),
        color = colors.surface,
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(accent.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, null, tint = accent, modifier = Modifier.size(16.dp))
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                value,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary
            )
            Text(
                label,
                fontSize = 10.sp,
                color = colors.textMuted
            )
        }
    }
}

@Composable
private fun ProfileSectionRow(title: String, subtitle: String, onClick: () -> Unit) {
    val colors = LocalAdaptiveColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary
            )
            Text(
                subtitle,
                fontSize = 13.sp,
                color = colors.textMuted
            )
        }
        Icon(
            Icons.Default.ChevronRight, null,
            tint = colors.textMuted,
            modifier = Modifier.size(20.dp)
        )
    }
}
