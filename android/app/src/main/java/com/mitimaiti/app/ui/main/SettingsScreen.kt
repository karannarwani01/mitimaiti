@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.models.*
import com.mitimaiti.app.ui.components.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.utils.AppLanguage
import com.mitimaiti.app.utils.LocalizationManager
import com.mitimaiti.app.utils.ThemeManager
import com.mitimaiti.app.viewmodels.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    themeManager: ThemeManager,
    localizationManager: LocalizationManager? = null,
    onBack: () -> Unit,
    onLogout: () -> Unit,
    onOpenTerms: () -> Unit = {},
    onOpenPrivacy: () -> Unit = {},
    onOpenGuidelines: () -> Unit = {}
) {
    val colors = LocalAdaptiveColors.current
    val scrollState = rememberScrollState()

    // Visibility
    val discoveryEnabled by viewModel.discoveryEnabled.collectAsState()
    val incognitoMode by viewModel.incognitoMode.collectAsState()
    val showFullName by viewModel.showFullName.collectAsState()
    val isSnoozed by viewModel.isSnoozed.collectAsState()

    // Filters
    val ageMin by viewModel.ageMin.collectAsState()
    val ageMax by viewModel.ageMax.collectAsState()
    val heightMin by viewModel.heightMin.collectAsState()
    val heightMax by viewModel.heightMax.collectAsState()
    val genderPreference by viewModel.genderPreference.collectAsState()
    val intentFilter by viewModel.intentFilter.collectAsState()
    val verifiedOnly by viewModel.verifiedOnly.collectAsState()

    // Community & Culture
    val fluencyFilter by viewModel.fluencyFilter.collectAsState()
    val generationFilter by viewModel.generationFilter.collectAsState()
    val religionFilter by viewModel.religionFilter.collectAsState()
    val gotraFilter by viewModel.gotraFilter.collectAsState()
    val dietaryFilter by viewModel.dietaryFilter.collectAsState()

    // Lifestyle
    val educationFilter by viewModel.educationFilter.collectAsState()
    val smokingFilter by viewModel.smokingFilter.collectAsState()
    val drinkingFilter by viewModel.drinkingFilter.collectAsState()
    val familyPlansFilter by viewModel.familyPlansFilter.collectAsState()

    // Notifications
    val notifyMatches by viewModel.notifyMatches.collectAsState()
    val notifyMessages by viewModel.notifyMessages.collectAsState()
    val notifyLikes by viewModel.notifyLikes.collectAsState()
    val notifyFamily by viewModel.notifyFamily.collectAsState()
    val notifyExpiry by viewModel.notifyExpiry.collectAsState()
    val notifySafety by viewModel.notifySafety.collectAsState()
    val notifyDailyPrompts by viewModel.notifyDailyPrompts.collectAsState()
    val notifyNewFeatures by viewModel.notifyNewFeatures.collectAsState()

    // Theme
    val selectedTheme by viewModel.theme.collectAsState()

    // Dialogs
    val showLogoutConfirmation by viewModel.showLogoutConfirmation.collectAsState()
    val showDeleteConfirmation by viewModel.showDeleteConfirmation.collectAsState()

    // Toast
    val toastMessage by viewModel.toastMessage.collectAsState()

    // Picker sheets
    var showFluencyPicker by remember { mutableStateOf(false) }
    var showGenerationPicker by remember { mutableStateOf(false) }
    var showReligionPicker by remember { mutableStateOf(false) }
    var showGotraPicker by remember { mutableStateOf(false) }
    var showDietaryPicker by remember { mutableStateOf(false) }
    var showEducationPicker by remember { mutableStateOf(false) }
    var showSmokingPicker by remember { mutableStateOf(false) }
    var showDrinkingPicker by remember { mutableStateOf(false) }
    var showFamilyPlansPicker by remember { mutableStateOf(false) }
    var showIntentPicker by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = colors.background,
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            "Settings",
                            fontWeight = FontWeight.Bold,
                            color = colors.textPrimary
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.surface)
                )
            }
        ) { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .verticalScroll(scrollState)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                // ── Visibility ──
                SettingsSection(title = "Visibility", icon = Icons.Default.Visibility) {
                    SettingsToggle("Discovery", "Show your profile in discovery", discoveryEnabled) {
                        viewModel.setDiscoveryEnabled(it)
                        viewModel.showToast("Discovery ${if (it) "enabled" else "disabled"}")
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Incognito Mode", "Browse without being seen", incognitoMode) {
                        viewModel.setIncognitoMode(it)
                        viewModel.showToast("Incognito ${if (it) "enabled" else "disabled"}")
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Show Full Name", "Display your full name on profile", showFullName) {
                        viewModel.setShowFullName(it)
                        viewModel.showToast("Full name ${if (it) "shown" else "hidden"}")
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Snooze", "Pause all activity temporarily", isSnoozed) {
                        viewModel.setSnoozed(it)
                        viewModel.showToast(if (it) "Profile snoozed" else "Welcome back!")
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Who I'm Looking For ──
                SettingsSection(title = "Who I'm Looking For", icon = Icons.Default.Search) {
                    // Gender picker (segmented)
                    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                        Text(
                            "Gender",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ShowMe.entries.forEach { option ->
                                FilterChip(
                                    selected = genderPreference == option,
                                    onClick = {
                                        viewModel.setGenderPreference(option)
                                        viewModel.showToast("Showing ${option.displayName}")
                                    },
                                    label = { Text(option.displayName) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = AppColors.Rose,
                                        selectedLabelColor = Color.White
                                    )
                                )
                            }
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)

                    // Age range slider
                    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        Text(
                            "Age Range: $ageMin - $ageMax",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textPrimary
                        )
                        RangeSlider(
                            value = ageMin.toFloat()..ageMax.toFloat(),
                            onValueChange = { range ->
                                viewModel.setAgeRange(range.start.toInt(), range.endInclusive.toInt())
                            },
                            valueRange = 18f..60f,
                            colors = SliderDefaults.colors(
                                thumbColor = AppColors.Rose,
                                activeTrackColor = AppColors.Rose
                            )
                        )
                    }
                    HorizontalDivider(color = colors.borderSubtle)

                    // Height range slider
                    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        Text(
                            "Height Range: ${heightMin}cm - ${heightMax}cm",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textPrimary
                        )
                        RangeSlider(
                            value = heightMin.toFloat()..heightMax.toFloat(),
                            onValueChange = { range ->
                                viewModel.setHeightRange(range.start.toInt(), range.endInclusive.toInt())
                            },
                            valueRange = 140f..210f,
                            colors = SliderDefaults.colors(
                                thumbColor = AppColors.Rose,
                                activeTrackColor = AppColors.Rose
                            )
                        )
                    }
                    HorizontalDivider(color = colors.borderSubtle)

                    // Intent filter
                    SettingsPickerRow(
                        title = "Intent",
                        value = intentFilter?.displayName ?: "Any",
                        onClick = { showIntentPicker = true }
                    )
                    HorizontalDivider(color = colors.borderSubtle)

                    // Verified Only toggle
                    SettingsToggle("Verified Only", "Only show verified profiles", verifiedOnly) {
                        viewModel.setVerifiedOnly(it)
                        viewModel.showToast(if (it) "Showing verified only" else "Showing all profiles")
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Community & Culture ──
                SettingsSection(title = "Community & Culture", icon = Icons.Default.Diversity3) {
                    SettingsPickerRow("Fluency", fluencyFilter?.displayName ?: "Any") { showFluencyPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Generation", generationFilter ?: "Any") { showGenerationPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Religion", religionFilter ?: "Any") { showReligionPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Gotra", gotraFilter ?: "Any") { showGotraPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Dietary", dietaryFilter?.displayName ?: "Any") { showDietaryPicker = true }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Lifestyle ──
                SettingsSection(title = "Lifestyle", icon = Icons.Default.SelfImprovement) {
                    SettingsPickerRow("Education", educationFilter ?: "Any") { showEducationPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Smoking", smokingFilter ?: "Any") { showSmokingPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Drinking", drinkingFilter ?: "Any") { showDrinkingPicker = true }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsPickerRow("Family Plans", familyPlansFilter ?: "Any") { showFamilyPlansPicker = true }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Notifications ──
                SettingsSection(title = "Notifications", icon = Icons.Default.Notifications) {
                    SettingsToggle("Matches", "New match notifications", notifyMatches) {
                        viewModel.notifyMatches.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Messages", "New message notifications", notifyMessages) {
                        viewModel.notifyMessages.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Likes", "When someone likes your profile", notifyLikes) {
                        viewModel.notifyLikes.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Family", "Family suggestions & activity", notifyFamily) {
                        viewModel.notifyFamily.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Expiry", "Match & message expiry reminders", notifyExpiry) {
                        viewModel.notifyExpiry.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Safety", "Safety alerts & tips", notifySafety) {
                        viewModel.notifySafety.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("Daily Prompts", "Daily conversation starters", notifyDailyPrompts) {
                        viewModel.notifyDailyPrompts.value = it
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    SettingsToggle("New Features", "App updates & new features", notifyNewFeatures) {
                        viewModel.notifyNewFeatures.value = it
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Appearance ──
                SettingsSection(title = "Appearance", icon = Icons.Default.Palette) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Theme",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AppThemeMode.entries.forEach { mode ->
                                FilterChip(
                                    selected = selectedTheme == mode,
                                    onClick = {
                                        viewModel.theme.value = mode
                                        themeManager.setTheme(mode)
                                        viewModel.showToast("Theme: ${mode.displayName}")
                                    },
                                    label = { Text(mode.displayName) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = AppColors.Rose,
                                        selectedLabelColor = Color.White
                                    )
                                )
                            }
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Language picker
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Language",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        val currentLang = localizationManager?.language?.collectAsState()?.value ?: AppLanguage.ENGLISH
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AppLanguage.entries.forEach { lang ->
                                FilterChip(
                                    selected = currentLang == lang,
                                    onClick = {
                                        localizationManager?.setLanguage(lang)
                                        viewModel.showToast("Language: ${lang.displayName}")
                                    },
                                    label = { Text(lang.displayName) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = AppColors.Rose,
                                        selectedLabelColor = Color.White
                                    )
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── Account ──
                SettingsSection(title = "Account", icon = Icons.Default.AccountCircle) {
                    // Edit Profile
                    TextButton(
                        onClick = { onBack() }, // Navigate back then to edit profile
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Edit, null, tint = AppColors.Rose, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Edit Profile", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Family Mode
                    TextButton(
                        onClick = { viewModel.showToast("Navigate to Family Mode") },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.FamilyRestroom, null, tint = AppColors.Gold, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Family Mode", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Change Phone
                    TextButton(
                        onClick = { viewModel.showToast("Phone change flow coming soon") },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Phone, null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Change Phone", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Text("+91 ****3210", fontSize = 13.sp, color = colors.textMuted)
                            Spacer(modifier = Modifier.width(4.dp))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Export Data
                    TextButton(
                        onClick = { viewModel.showToast("Data export requested. Check your email.") },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Download, null, tint = AppColors.Info, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Export My Data", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AppColors.Info)
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Log Out (yellow/warning)
                    TextButton(
                        onClick = { viewModel.showLogoutConfirmation.value = true },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Logout, null,
                                tint = AppColors.Warning,
                                modifier = Modifier.size(20.dp)
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                "Log Out",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = AppColors.Warning
                            )
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Delete Account (red/danger)
                    TextButton(
                        onClick = { viewModel.showDeleteConfirmation.value = true },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.DeleteForever, null,
                                tint = AppColors.Error,
                                modifier = Modifier.size(20.dp)
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                "Delete Account",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = AppColors.Error
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // ── About ──
                SettingsSection(title = "About", icon = Icons.Default.Info) {
                    // Terms of Service
                    TextButton(
                        onClick = onOpenTerms,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Description, null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Terms of Service", fontSize = 15.sp, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Privacy Policy
                    TextButton(
                        onClick = onOpenPrivacy,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Policy, null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Privacy Policy", fontSize = 15.sp, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    HorizontalDivider(color = colors.borderSubtle)
                    // Community Guidelines
                    TextButton(
                        onClick = onOpenGuidelines,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Gavel, null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Community Guidelines", fontSize = 15.sp, color = colors.textPrimary)
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        "MitiMaiti v1.0.0",
                        fontSize = 13.sp,
                        color = colors.textMuted,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Made with love for the Sindhi community",
                        fontSize = 12.sp,
                        color = colors.textMuted,
                        textAlign = TextAlign.Center
                    )
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }

        // Log Out confirmation dialog
        if (showLogoutConfirmation) {
            AlertDialog(
                onDismissRequest = { viewModel.showLogoutConfirmation.value = false },
                title = {
                    Text("Log Out", fontWeight = FontWeight.Bold, color = colors.textPrimary)
                },
                text = {
                    Text(
                        "Are you sure you want to log out?",
                        color = colors.textSecondary
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.showLogoutConfirmation.value = false
                            onLogout()
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Warning)
                    ) {
                        Text("Log Out", color = Color.White)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.showLogoutConfirmation.value = false }) {
                        Text("Cancel", color = colors.textSecondary)
                    }
                },
                containerColor = colors.surface
            )
        }

        // Delete Account confirmation dialog with 30-day warning
        if (showDeleteConfirmation) {
            AlertDialog(
                onDismissRequest = { viewModel.showDeleteConfirmation.value = false },
                title = {
                    Text(
                        "Delete Account",
                        fontWeight = FontWeight.Bold,
                        color = AppColors.Error
                    )
                },
                text = {
                    Column {
                        Text(
                            "Are you sure you want to delete your account?",
                            color = colors.textPrimary,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Your account will be deactivated immediately and permanently deleted after 30 days. You can log back in within 30 days to cancel the deletion.",
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            lineHeight = 18.sp
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Surface(
                            shape = RoundedCornerShape(AppTheme.radiusSm),
                            color = AppColors.Error.copy(alpha = 0.1f)
                        ) {
                            Text(
                                "This action is irreversible after 30 days",
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = AppColors.Error
                            )
                        }
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.showDeleteConfirmation.value = false
                            viewModel.showToast("Account deletion scheduled")
                            // Actually delete server-side, then log out locally.
                            viewModel.deleteAccount { onLogout() }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Error)
                    ) {
                        Text("Delete Account", color = Color.White)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.showDeleteConfirmation.value = false }) {
                        Text("Cancel", color = colors.textSecondary)
                    }
                },
                containerColor = colors.surface
            )
        }

        // Toast overlay
        androidx.compose.animation.AnimatedVisibility(
            visible = toastMessage != null,
            enter = androidx.compose.animation.fadeIn() + androidx.compose.animation.slideInVertically(initialOffsetY = { it }),
            exit = androidx.compose.animation.fadeOut() + androidx.compose.animation.slideOutVertically(targetOffsetY = { it }),
            modifier = Modifier.fillMaxSize().padding(bottom = 32.dp)
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.BottomCenter
            ) {
                Surface(
                    shape = RoundedCornerShape(AppTheme.radiusFull),
                    color = colors.cardDark,
                    shadowElevation = 8.dp
                ) {
                    Text(
                        toastMessage ?: "",
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                        fontSize = 14.sp,
                        color = colors.textPrimary,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }

        // Picker bottom sheets
        if (showFluencyPicker) {
            PickerSheet(
                title = "Sindhi Fluency",
                options = listOf("Any") + SindhiFluency.entries.map { it.displayName },
                selected = fluencyFilter?.displayName ?: "Any",
                onSelect = { value ->
                    viewModel.setFluencyFilter(SindhiFluency.entries.firstOrNull { it.displayName == value })
                    viewModel.showToast("Fluency: $value")
                    showFluencyPicker = false
                },
                onDismiss = { showFluencyPicker = false }
            )
        }
        if (showGenerationPicker) {
            PickerSheet(
                title = "Generation",
                options = listOf("Any", "1st Gen", "2nd Gen", "3rd Gen", "4th Gen+"),
                selected = generationFilter ?: "Any",
                onSelect = { value ->
                    viewModel.generationFilter.value = if (value == "Any") null else value
                    viewModel.showToast("Generation: $value")
                    showGenerationPicker = false
                },
                onDismiss = { showGenerationPicker = false }
            )
        }
        if (showReligionPicker) {
            PickerSheet(
                title = "Religion",
                options = listOf("Any", "Hindu", "Muslim", "Sikh", "Jain", "Christian", "Other"),
                selected = religionFilter ?: "Any",
                onSelect = { value ->
                    viewModel.setReligionFilter(if (value == "Any") null else value)
                    viewModel.showToast("Religion: $value")
                    showReligionPicker = false
                },
                onDismiss = { showReligionPicker = false }
            )
        }
        if (showGotraPicker) {
            PickerSheet(
                title = "Gotra",
                options = listOf("Any", "Exclude same gotra", "Advani", "Bijlani", "Chandiramani", "Daswani", "Gidwani", "Keswani", "Lalwani", "Makhija", "Motwani", "Tolani", "Wadhwa", "Other"),
                selected = when (gotraFilter) {
                    null -> "Any"
                    "exclude_same" -> "Exclude same gotra"
                    else -> gotraFilter ?: "Any"
                },
                onSelect = { value ->
                    viewModel.setGotraFilter(when (value) {
                        "Any" -> null
                        "Exclude same gotra" -> "exclude_same"
                        else -> value
                    })
                    viewModel.showToast("Gotra: $value")
                    showGotraPicker = false
                },
                onDismiss = { showGotraPicker = false }
            )
        }
        if (showDietaryPicker) {
            PickerSheet(
                title = "Dietary Preference",
                options = listOf("Any") + FoodPreference.entries.map { it.displayName },
                selected = dietaryFilter?.displayName ?: "Any",
                onSelect = { value ->
                    viewModel.setDietaryFilter(FoodPreference.entries.firstOrNull { it.displayName == value })
                    viewModel.showToast("Diet: $value")
                    showDietaryPicker = false
                },
                onDismiss = { showDietaryPicker = false }
            )
        }
        if (showEducationPicker) {
            PickerSheet(
                title = "Education",
                options = listOf("Any", "High School", "Bachelor's", "Master's", "Doctorate", "Professional"),
                selected = educationFilter ?: "Any",
                onSelect = { value ->
                    viewModel.setEducationFilter(if (value == "Any") null else value)
                    viewModel.showToast("Education: $value")
                    showEducationPicker = false
                },
                onDismiss = { showEducationPicker = false }
            )
        }
        if (showSmokingPicker) {
            PickerSheet(
                title = "Smoking",
                options = listOf("Any", "Never", "Sometimes", "Regularly"),
                selected = smokingFilter ?: "Any",
                onSelect = { value ->
                    viewModel.setSmokingFilter(if (value == "Any") null else value)
                    viewModel.showToast("Smoking: $value")
                    showSmokingPicker = false
                },
                onDismiss = { showSmokingPicker = false }
            )
        }
        if (showDrinkingPicker) {
            PickerSheet(
                title = "Drinking",
                options = listOf("Any", "Never", "Socially", "Regularly"),
                selected = drinkingFilter ?: "Any",
                onSelect = { value ->
                    viewModel.setDrinkingFilter(if (value == "Any") null else value)
                    viewModel.showToast("Drinking: $value")
                    showDrinkingPicker = false
                },
                onDismiss = { showDrinkingPicker = false }
            )
        }
        if (showFamilyPlansPicker) {
            PickerSheet(
                title = "Family Plans",
                options = listOf("Any", "Want kids", "Don't want kids", "Open to kids", "Have kids"),
                selected = familyPlansFilter ?: "Any",
                onSelect = { value ->
                    viewModel.familyPlansFilter.value = if (value == "Any") null else value
                    viewModel.showToast("Family plans: $value")
                    showFamilyPlansPicker = false
                },
                onDismiss = { showFamilyPlansPicker = false }
            )
        }
        if (showIntentPicker) {
            PickerSheet(
                title = "Intent",
                options = listOf("Any") + Intent.entries.map { it.displayName },
                selected = intentFilter?.displayName ?: "Any",
                onSelect = { value ->
                    viewModel.setIntentFilter(Intent.entries.firstOrNull { it.displayName == value })
                    viewModel.showToast("Intent: $value")
                    showIntentPicker = false
                },
                onDismiss = { showIntentPicker = false }
            )
        }
    }
}

@Composable
private fun SettingsSection(
    title: String,
    icon: ImageVector,
    content: @Composable ColumnScope.() -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Column {
        Row(
            modifier = Modifier.padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, null, tint = AppColors.Rose, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                title,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        GlassCard(modifier = Modifier.fillMaxWidth()) {
            content()
        }
    }
}

@Composable
private fun SettingsToggle(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textPrimary
            )
            Text(subtitle, fontSize = 12.sp, color = colors.textMuted)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = AppColors.Rose,
                checkedThumbColor = Color.White
            )
        )
    }
}

@Composable
private fun SettingsPickerRow(
    title: String,
    value: String,
    onClick: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            title,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                value,
                fontSize = 14.sp,
                color = if (value == "Any") colors.textMuted else AppColors.Rose
            )
            Spacer(modifier = Modifier.width(4.dp))
            Icon(
                Icons.Default.ChevronRight, null,
                tint = colors.textMuted,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun PickerSheet(
    title: String,
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = {
            Text(title, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        },
        text = {
            Column {
                options.forEach { option ->
                    val isSelected = option == selected
                    Surface(
                        onClick = { onSelect(option) },
                        color = if (isSelected) AppColors.Rose.copy(alpha = 0.1f) else Color.Transparent,
                        shape = RoundedCornerShape(AppTheme.radiusSm)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                option,
                                fontSize = 15.sp,
                                color = if (isSelected) AppColors.Rose else colors.textPrimary,
                                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                            )
                            if (isSelected) {
                                Icon(
                                    Icons.Default.Check, null,
                                    tint = AppColors.Rose,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = colors.textSecondary)
            }
        }
    )
}
