@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.onboarding

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.location.Geocoder
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import coil.compose.AsyncImage
import com.mitimaiti.app.models.Gender
import com.mitimaiti.app.models.Intent
import com.mitimaiti.app.models.ShowMe
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.OnboardingStep
import com.mitimaiti.app.viewmodels.OnboardingViewModel

@Composable
fun OnboardingScreen(onComplete: () -> Unit, onNavigateToEditProfile: () -> Unit = {}) {
    val viewModel: OnboardingViewModel = viewModel()
    val colors = LocalAdaptiveColors.current
    val rootContext = LocalContext.current
    val isSubmitting by viewModel.isSubmitting.collectAsState()
    val submitError by viewModel.submitError.collectAsState()
    val finishOnboarding: () -> Unit = {
        viewModel.submitOnboarding(rootContext) { ok -> if (ok) onComplete() }
    }
    val currentStep by viewModel.currentStep.collectAsState()
    val totalSteps = OnboardingStep.entries.size
    val stepIndex = OnboardingStep.entries.indexOf(currentStep)

    val firstName by viewModel.firstName.collectAsState()
    val birthDay by viewModel.birthDay.collectAsState()
    val birthMonth by viewModel.birthMonth.collectAsState()
    val birthYear by viewModel.birthYear.collectAsState()
    val selectedGender by viewModel.selectedGender.collectAsState()
    val selectedPhotos by viewModel.selectedPhotos.collectAsState()
    val selectedIntent by viewModel.selectedIntent.collectAsState()
    val selectedShowMe by viewModel.selectedShowMe.collectAsState()
    val selectedCity by viewModel.selectedCity.collectAsState()
    val isNonSindhi by viewModel.isNonSindhi.collectAsState()
    val progress by remember(stepIndex, totalSteps) {
        derivedStateOf { (stepIndex + 1).toFloat() / totalSteps }
    }
    val canProceed by remember(currentStep, firstName, birthDay, birthMonth, birthYear, selectedGender, selectedPhotos, selectedIntent, selectedShowMe, selectedCity) {
        derivedStateOf {
            when (currentStep) {
                OnboardingStep.NAME -> firstName.isNotBlank()
                OnboardingStep.BIRTHDAY -> viewModel.isAgeValid
                OnboardingStep.GENDER -> selectedGender != null
                OnboardingStep.PHOTOS -> selectedPhotos.isNotEmpty()
                OnboardingStep.INTENT -> selectedIntent != null
                OnboardingStep.SHOW_ME -> selectedShowMe != null
                OnboardingStep.LOCATION -> selectedCity.isNotBlank()
                OnboardingStep.READY -> true
            }
        }
    }
    val age by remember(birthDay, birthMonth, birthYear) {
        derivedStateOf { viewModel.age }
    }

    // Photo picker launcher
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let { viewModel.addPhoto(it) }
    }

    // Track direction for slide animation
    var lastStep by remember { mutableIntStateOf(0) }
    val isForward = stepIndex >= lastStep
    LaunchedEffect(stepIndex) { lastStep = stepIndex }

    Box(modifier = Modifier.fillMaxSize().background(colors.backgroundGradient)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp)
        ) {
            // Top bar: back button + step counter
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (stepIndex > 0) {
                    IconButton(onClick = { viewModel.previousStep() }) {
                        Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
                    }
                } else {
                    Spacer(modifier = Modifier.size(48.dp))
                }
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    "${stepIndex + 1}/$totalSteps",
                    fontSize = 14.sp,
                    color = colors.textMuted
                )
            }

            // Progress bar (rose colored, animated)
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = AppColors.Rose,
                trackColor = colors.border,
                drawStopIndicator = {}
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Step content with animated transitions (slide left/right)
            Box(modifier = Modifier.weight(1f)) {
                AnimatedContent(
                    targetState = currentStep,
                    transitionSpec = {
                        if (isForward) {
                            (slideInHorizontally(
                                initialOffsetX = { it },
                                animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
                            ) + fadeIn(animationSpec = tween(300)))
                                .togetherWith(
                                    slideOutHorizontally(
                                        targetOffsetX = { -it },
                                        animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
                                    ) + fadeOut(animationSpec = tween(300))
                                )
                        } else {
                            (slideInHorizontally(
                                initialOffsetX = { -it },
                                animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
                            ) + fadeIn(animationSpec = tween(300)))
                                .togetherWith(
                                    slideOutHorizontally(
                                        targetOffsetX = { it },
                                        animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
                                    ) + fadeOut(animationSpec = tween(300))
                                )
                        }
                    },
                    label = "onboarding_step"
                ) { step ->
                    when (step) {
                        OnboardingStep.NAME -> NameStep(
                            name = firstName,
                            onNameChange = { viewModel.firstName.value = it },
                            isNonSindhi = isNonSindhi,
                            onNonSindhiChange = { viewModel.isNonSindhi.value = it }
                        )
                        OnboardingStep.BIRTHDAY -> BirthdayStep(
                            day = birthDay,
                            month = birthMonth,
                            year = birthYear,
                            age = age,
                            onDayChange = { viewModel.birthDay.value = it },
                            onMonthChange = { viewModel.birthMonth.value = it },
                            onYearChange = { viewModel.birthYear.value = it }
                        )
                        OnboardingStep.GENDER -> GenderStep(
                            selected = selectedGender,
                            onSelect = { viewModel.selectedGender.value = it }
                        )
                        OnboardingStep.PHOTOS -> PhotosStep(
                            photos = selectedPhotos.map { it.uri },
                            onAddPhoto = {
                                photoPickerLauncher.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                )
                            },
                            onRemovePhoto = { viewModel.removePhoto(it) }
                        )
                        OnboardingStep.INTENT -> IntentStep(
                            selected = selectedIntent,
                            onSelect = { viewModel.selectedIntent.value = it }
                        )
                        OnboardingStep.SHOW_ME -> ShowMeStep(
                            selected = selectedShowMe,
                            onSelect = { viewModel.selectedShowMe.value = it }
                        )
                        OnboardingStep.LOCATION -> LocationStep(
                            location = selectedCity,
                            onLocationChange = { viewModel.selectedCity.value = it },
                            onCountryChange = { viewModel.selectedCountry.value = it }
                        )
                        OnboardingStep.READY -> {
                            val profileCompleteness = remember(firstName, selectedGender, selectedIntent, selectedShowMe, selectedCity, selectedPhotos) {
                                var s = 0.0
                                if (firstName.isNotBlank()) s += 0.20
                                if (selectedGender != null) s += 0.15
                                if (selectedIntent != null) s += 0.15
                                if (selectedShowMe != null) s += 0.10
                                if (selectedCity.isNotBlank()) s += 0.15
                                if (selectedPhotos.isNotEmpty()) s += 0.25
                                (s.coerceIn(0.0, 1.0) * 100).toInt()
                            }
                            ReadyStep(
                                name = firstName,
                                age = age,
                                city = selectedCity,
                                isNonSindhi = isNonSindhi,
                                profileCompleteness = profileCompleteness,
                                onCompleteSindhi = {
                                    viewModel.submitOnboarding(rootContext) { ok ->
                                        if (ok) {
                                            onComplete()
                                            onNavigateToEditProfile()
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // Next / Let's Go button
            Button(
                onClick = {
                    android.util.Log.d("Onboarding", "Button tapped, step=$currentStep, canProceed=$canProceed, isSubmitting=$isSubmitting")
                    if (currentStep == OnboardingStep.READY) finishOnboarding() else viewModel.nextStep()
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = canProceed && !isSubmitting,
                shape = RoundedCornerShape(AppTheme.radiusLg),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppColors.Rose,
                    disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                )
            ) {
                Text(
                    if (currentStep == OnboardingStep.READY) "\u2728 Go to Discover" else "Continue",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun NameStep(
    name: String,
    onNameChange: (String) -> Unit,
    isNonSindhi: Boolean,
    onNonSindhiChange: (Boolean) -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Column {
        Text(
            "What's your full name?",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "This is how it appears on your profile.",
            fontSize = 16.sp,
            color = colors.textSecondary
        )
        Spacer(modifier = Modifier.height(32.dp))
        OutlinedTextField(
            value = name,
            onValueChange = { if (it.length <= 50) onNameChange(it) },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Enter your full name", color = colors.textMuted) },
            shape = RoundedCornerShape(AppTheme.radiusMd),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = AppColors.Rose,
                unfocusedBorderColor = colors.border,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary
            ),
            singleLine = true
        )
        Spacer(modifier = Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                "Your family name can be hidden in Settings",
                fontSize = 12.sp,
                color = colors.textMuted
            )
            Text(
                "${name.length}/50",
                fontSize = 12.sp,
                color = colors.textMuted
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Not Sindhi toggle
        Surface(
            shape = RoundedCornerShape(AppTheme.radiusMd),
            color = AppColors.Rose.copy(alpha = 0.05f),
            border = BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.1f))
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Not Sindhi? No worries!",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.textPrimary
                    )
                    Text(
                        "Open to vibing with the Sindhi community",
                        fontSize = 12.sp,
                        color = colors.textSecondary
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Switch(
                    checked = isNonSindhi,
                    onCheckedChange = onNonSindhiChange,
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = AppColors.Rose,
                        uncheckedThumbColor = Color.White,
                        uncheckedTrackColor = colors.border
                    )
                )
            }
        }
    }
}

@Composable
private fun BirthdayStep(
    day: String,
    month: String,
    year: String,
    age: Int?,
    onDayChange: (String) -> Unit,
    onMonthChange: (String) -> Unit,
    onYearChange: (String) -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val isUnderage = age != null && age < 18

    Column {
        Text(
            "When's your birthday?",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Your age shows on your profile. Birthday won't be shared.",
            fontSize = 16.sp,
            color = colors.textSecondary
        )
        Spacer(modifier = Modifier.height(32.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = day,
                onValueChange = { if (it.length <= 2 && it.all { c -> c.isDigit() }) onDayChange(it) },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Day", color = colors.textMuted) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                shape = RoundedCornerShape(AppTheme.radiusMd),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.Rose,
                    unfocusedBorderColor = colors.border,
                    focusedTextColor = colors.textPrimary,
                    unfocusedTextColor = colors.textPrimary
                ),
                singleLine = true
            )
            // Month field — type number (1-12) or abbreviation (Jan, Feb, etc.)
            Box(modifier = Modifier.weight(1f)) {
                val monthMap = mapOf(
                    "jan" to "1", "feb" to "2", "mar" to "3", "apr" to "4",
                    "may" to "5", "jun" to "6", "jul" to "7", "aug" to "8",
                    "sep" to "9", "oct" to "10", "nov" to "11", "dec" to "12"
                )
                val monthNames = listOf(
                    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
                )
                var textFieldValue by remember { mutableStateOf(month) }
                val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
                var isFocused by remember { mutableStateOf(false) }

                OutlinedTextField(
                    value = textFieldValue,
                    onValueChange = { input ->
                        textFieldValue = input
                        // Only auto-commit for 2-digit numbers or abbreviations
                        val trimmed = input.trim()
                        val asNum = trimmed.filter { c -> c.isDigit() }
                        if (asNum.length == 2) {
                            val num = asNum.toIntOrNull()
                            if (num != null && num in 1..12) {
                                onMonthChange(asNum)
                                textFieldValue = monthNames[num - 1]
                            }
                        } else if (asNum.isEmpty()) {
                            // Check if month abbreviation
                            val match = monthMap[trimmed.lowercase()]
                            if (match != null) {
                                onMonthChange(match)
                                textFieldValue = monthNames[match.toInt() - 1]
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { state ->
                            if (isFocused && !state.isFocused) {
                                // On blur: convert single digit to month name
                                val trimmed = textFieldValue.trim()
                                val num = trimmed.toIntOrNull()
                                if (num != null && num in 1..12) {
                                    onMonthChange("$num")
                                    textFieldValue = monthNames[num - 1]
                                }
                            }
                            isFocused = state.isFocused
                        },
                    placeholder = { Text("Month", color = colors.textMuted) },
                    shape = RoundedCornerShape(AppTheme.radiusMd),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.Rose,
                        unfocusedBorderColor = colors.border,
                        focusedTextColor = colors.textPrimary,
                        unfocusedTextColor = colors.textPrimary
                    ),
                    singleLine = true
                )
            }
            OutlinedTextField(
                value = year,
                onValueChange = { if (it.length <= 4 && it.all { c -> c.isDigit() }) onYearChange(it) },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Year", color = colors.textMuted) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                shape = RoundedCornerShape(AppTheme.radiusMd),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.Rose,
                    unfocusedBorderColor = colors.border,
                    focusedTextColor = colors.textPrimary,
                    unfocusedTextColor = colors.textPrimary
                ),
                singleLine = true
            )
        }

        // Show calculated age
        if (age != null) {
            Spacer(modifier = Modifier.height(12.dp))
            if (isUnderage) {
                Text(
                    "You must be at least 18 years old to use MitiMaiti",
                    fontSize = 14.sp,
                    color = AppColors.Error,
                    fontWeight = FontWeight.Medium
                )
            } else {
                Text(
                    "Age: $age years old",
                    fontSize = 14.sp,
                    color = AppColors.Success,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
private fun GenderStep(selected: Gender?, onSelect: (Gender) -> Unit) {
    val colors = LocalAdaptiveColors.current
    Column {
        Text(
            "How do you identify?",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(32.dp))

        Gender.entries.forEach { gender ->
            val isSelected = gender == selected
            Surface(
                onClick = { onSelect(gender) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                shape = RoundedCornerShape(AppTheme.radiusLg),
                color = if (isSelected) AppColors.Rose.copy(alpha = 0.05f) else colors.surface,
                border = if (isSelected) BorderStroke(2.dp, AppColors.Rose)
                else BorderStroke(1.dp, colors.border)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = genderIcon(gender),
                        contentDescription = null,
                        tint = if (isSelected) AppColors.Rose else colors.textPrimary,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(14.dp))
                    Text(
                        gender.displayName,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textPrimary,
                        modifier = Modifier.weight(1f)
                    )
                    RadioButton(
                        selected = isSelected,
                        onClick = { onSelect(gender) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.Rose,
                            unselectedColor = colors.border
                        )
                    )
                }
            }
        }
    }
}

@Composable
private fun PhotosStep(photos: List<Uri>, onAddPhoto: () -> Unit, onRemovePhoto: (Int) -> Unit) {
    val colors = LocalAdaptiveColors.current
    Column {
        Text(
            "Add your\nbest photos",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Add at least 1 photo to continue. Profiles with 3+ photos get more matches!",
            fontSize = 16.sp,
            color = colors.textSecondary
        )
        Spacer(modifier = Modifier.height(32.dp))

        // 3x2 grid of photo slots
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in 0..1) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    for (col in 0..2) {
                        val index = row * 3 + col
                        val hasPhoto = index < photos.size
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .aspectRatio(0.8f)
                                .clip(RoundedCornerShape(AppTheme.radiusMd))
                                .background(if (hasPhoto) Color.Transparent else colors.surfaceMedium)
                                .then(
                                    if (!hasPhoto && photos.size < 6)
                                        Modifier.clickable { onAddPhoto() }
                                    else Modifier
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            if (hasPhoto) {
                                AsyncImage(
                                    model = photos[index],
                                    contentDescription = "Photo ${index + 1}",
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .clip(RoundedCornerShape(AppTheme.radiusMd)),
                                    contentScale = ContentScale.Crop
                                )
                                // Remove button
                                IconButton(
                                    onClick = { onRemovePhoto(index) },
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .size(28.dp)
                                        .background(
                                            Color.Black.copy(alpha = 0.5f),
                                            CircleShape
                                        )
                                ) {
                                    Icon(
                                        Icons.Default.Close,
                                        "Remove photo",
                                        tint = Color.White,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            } else {
                                Surface(
                                    modifier = Modifier.fillMaxSize(),
                                    shape = RoundedCornerShape(AppTheme.radiusMd),
                                    color = colors.surfaceMedium,
                                    border = BorderStroke(2.dp, colors.border.copy(alpha = 0.5f))
                                ) {
                                    Box(contentAlignment = Alignment.Center) {
                                        Icon(
                                            Icons.Default.CameraAlt,
                                            "Add photo",
                                            tint = colors.textMuted,
                                            modifier = Modifier.size(32.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))
        Text(
            "${photos.size}/6 photos added",
            fontSize = 14.sp,
            color = colors.textMuted,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun IntentStep(selected: Intent?, onSelect: (Intent) -> Unit) {
    val colors = LocalAdaptiveColors.current
    Column {
        Text(
            "What are you looking for?",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(32.dp))

        Intent.entries.filter { it != Intent.MARRIAGE }.forEach { intent ->
            val isSelected = intent == selected
            Surface(
                onClick = { onSelect(intent) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                shape = RoundedCornerShape(AppTheme.radiusLg),
                color = if (isSelected) Color(intent.color).copy(alpha = 0.05f) else colors.surface,
                border = if (isSelected) BorderStroke(2.dp, Color(intent.color))
                else BorderStroke(1.dp, colors.border)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = intentIcon(intent),
                        contentDescription = null,
                        tint = if (isSelected) Color(intent.color) else colors.textPrimary,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(14.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            intent.displayName,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textPrimary
                        )
                        Text(
                            intent.description,
                            fontSize = 13.sp,
                            color = colors.textSecondary
                        )
                    }
                    RadioButton(
                        selected = isSelected,
                        onClick = { onSelect(intent) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = Color(intent.color),
                            unselectedColor = colors.border
                        )
                    )
                }
            }
        }
    }
}

@Composable
private fun ShowMeStep(selected: ShowMe?, onSelect: (ShowMe) -> Unit) {
    val colors = LocalAdaptiveColors.current
    Column {
        Text(
            "Show me",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "You can always change this later.",
            fontSize = 16.sp,
            color = colors.textSecondary
        )
        Spacer(modifier = Modifier.height(32.dp))

        ShowMe.entries.forEach { option ->
            val isSelected = option == selected
            Surface(
                onClick = { onSelect(option) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                shape = RoundedCornerShape(AppTheme.radiusLg),
                color = if (isSelected) AppColors.Rose.copy(alpha = 0.05f) else colors.surface,
                border = if (isSelected) BorderStroke(2.dp, AppColors.Rose)
                else BorderStroke(1.dp, colors.border)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = showMeIcon(option),
                        contentDescription = null,
                        tint = if (isSelected) AppColors.Rose else colors.textPrimary,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(14.dp))
                    Text(
                        option.displayName,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textPrimary,
                        modifier = Modifier.weight(1f)
                    )
                    RadioButton(
                        selected = isSelected,
                        onClick = { onSelect(option) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.Rose,
                            unselectedColor = colors.border
                        )
                    )
                }
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun LocationStep(location: String, onLocationChange: (String) -> Unit, onCountryChange: (String) -> Unit = {}) {
    val colors = LocalAdaptiveColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isLocating by remember { mutableStateOf(false) }
    var detectedCity by remember { mutableStateOf("") }
    var detectedCountry by remember { mutableStateOf("") }

    // GPS fix → city, with the failure modes that bit us on a real device:
    // getCurrentLocation returns null indoors (fall back to lastLocation),
    // Geocoder is a blocking network call (run off the main thread), and
    // every failure tells the user to type the city instead of going silent.
    fun detectLocation() {
        isLocating = true
        val fusedClient = LocationServices.getFusedLocationProviderClient(context)
        fun geocode(lat: Double, lng: Double) {
            scope.launch {
                val result = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    getCityAndCountryFromLocation(context, lat, lng)
                }
                isLocating = false
                if (result != null && result.first != "Unknown") {
                    onLocationChange(result.first)
                    onCountryChange(result.second)
                    detectedCity = result.first
                    detectedCountry = result.second
                } else {
                    android.widget.Toast.makeText(context, "Couldn't work out your city — please type it below.", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
        }
        fun fail() {
            isLocating = false
            android.widget.Toast.makeText(context, "Couldn't get a location fix — please type your city below.", android.widget.Toast.LENGTH_SHORT).show()
        }
        // City-level accuracy is enough and works indoors, unlike HIGH_ACCURACY.
        fusedClient.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
            .addOnSuccessListener { loc ->
                if (loc != null) geocode(loc.latitude, loc.longitude)
                else fusedClient.lastLocation
                    .addOnSuccessListener { last ->
                        if (last != null) geocode(last.latitude, last.longitude) else fail()
                    }
                    .addOnFailureListener { fail() }
            }
            .addOnFailureListener { fail() }
    }

    // If the SYSTEM location toggle is off (the case we hit on a real device:
    // permission granted but location_mode=0), pop Android's one-tap
    // "turn on device location?" dialog instead of failing.
    val resolutionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) detectLocation()
        else android.widget.Toast.makeText(context, "Location is off — turn it on or type your city below.", android.widget.Toast.LENGTH_SHORT).show()
    }

    fun ensureLocationOnThenDetect() {
        val request = com.google.android.gms.location.LocationSettingsRequest.Builder()
            .addLocationRequest(
                com.google.android.gms.location.LocationRequest.Builder(
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY, 10_000L
                ).build()
            )
            .build()
        LocationServices.getSettingsClient(context)
            .checkLocationSettings(request)
            .addOnSuccessListener { detectLocation() }
            .addOnFailureListener { e ->
                if (e is com.google.android.gms.common.api.ResolvableApiException) {
                    try {
                        resolutionLauncher.launch(
                            androidx.activity.result.IntentSenderRequest.Builder(e.resolution).build()
                        )
                    } catch (_: Exception) {
                        android.widget.Toast.makeText(context, "Turn on Location in quick settings, then try again.", android.widget.Toast.LENGTH_SHORT).show()
                    }
                } else {
                    android.widget.Toast.makeText(context, "Location unavailable — type your city below.", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
    }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (granted) ensureLocationOnThenDetect()
        else android.widget.Toast.makeText(context, "Location permission denied — type your city below.", android.widget.Toast.LENGTH_SHORT).show()
    }

    Column {
        Text(
            "Where are you?",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            lineHeight = 36.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "MitiMaiti uses your city to show nearby Sindhis.",
            fontSize = 16.sp,
            color = colors.textSecondary
        )
        Spacer(modifier = Modifier.height(24.dp))

        // Use current location button
        Surface(
            onClick = {
                val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACCESS_COARSE_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (granted) ensureLocationOnThenDetect()
                else locationPermissionLauncher.launch(
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                )
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(AppTheme.radiusLg),
            color = AppColors.Rose.copy(alpha = 0.05f),
            border = BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.15f)),
            enabled = !isLocating
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(AppColors.Rose.copy(alpha = 0.1f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    if (isLocating) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = AppColors.Rose
                        )
                    } else {
                        Icon(
                            Icons.Default.NearMe, null,
                            tint = AppColors.Rose,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        if (isLocating) "Detecting location..." else "Use my current location",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Rose
                    )
                    Text(
                        "Auto-detect your city",
                        fontSize = 13.sp,
                        color = colors.textSecondary
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Search field
        OutlinedTextField(
            value = location,
            onValueChange = {
                onLocationChange(it)
                onCountryChange("")
                detectedCity = ""
                detectedCountry = ""
            },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Search city...", color = colors.textMuted) },
            leadingIcon = { Icon(Icons.Default.Search, null, tint = colors.textMuted) },
            shape = RoundedCornerShape(AppTheme.radiusLg),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = AppColors.Rose,
                unfocusedBorderColor = colors.border,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary
            ),
            singleLine = true
        )

        // Detected location display
        if (detectedCity.isNotEmpty()) {
            Spacer(modifier = Modifier.height(16.dp))
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppTheme.radiusLg),
                color = AppColors.Rose.copy(alpha = 0.05f),
                border = BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.2f))
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.LocationOn, null,
                        tint = AppColors.Rose,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        "$detectedCity, $detectedCountry",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textPrimary,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        "Change",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.Rose,
                        modifier = Modifier.clickable {
                            onLocationChange("")
                            onCountryChange("")
                            detectedCity = ""
                            detectedCountry = ""
                        }
                    )
                }
            }
        }
    }
}

@Suppress("DEPRECATION")
private fun getCityAndCountryFromLocation(context: Context, lat: Double, lng: Double): Pair<String, String>? {
    return try {
        val geocoder = Geocoder(context, java.util.Locale.getDefault())
        val addresses = geocoder.getFromLocation(lat, lng, 1)
        val addr = addresses?.firstOrNull() ?: return null
        val city = addr.locality ?: addr.subAdminArea ?: "Unknown"
        val country = addr.countryName ?: ""
        Pair(city, country)
    } catch (e: Exception) {
        null
    }
}

@Composable
private fun ReadyStep(name: String, age: Int?, city: String, isNonSindhi: Boolean, profileCompleteness: Int, onCompleteSindhi: () -> Unit) {
    val colors = LocalAdaptiveColors.current

    Box(modifier = Modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // Party popper emoji
        Text(
            "\uD83C\uDF89",
            fontSize = 40.sp,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            "You're In!",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            "Welcome to the MitiMaiti community, $name!",
            fontSize = 14.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Profile preview card
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(AppTheme.radiusCard),
            shadowElevation = 8.dp,
            color = colors.surface
        ) {
            Column {
                // Rose gradient header with avatar
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(110.dp)
                        .background(
                            Brush.linearGradient(listOf(AppColors.Rose, AppColors.RoseDark))
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    // Sparkle decorations
                    Icon(
                        Icons.Default.AutoAwesome, null,
                        tint = Color.White.copy(alpha = 0.3f),
                        modifier = Modifier
                            .size(16.dp)
                            .align(Alignment.TopEnd)
                            .offset(x = (-24).dp, y = 16.dp)
                    )
                    Icon(
                        Icons.Default.AutoAwesome, null,
                        tint = Color.White.copy(alpha = 0.2f),
                        modifier = Modifier
                            .size(12.dp)
                            .align(Alignment.BottomStart)
                            .offset(x = 20.dp, y = (-16).dp)
                    )

                    // Avatar circle
                    Box(
                        modifier = Modifier
                            .size(64.dp)
                            .background(Color.White.copy(alpha = 0.2f), CircleShape)
                            .clip(CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        val primaryPhoto = com.mitimaiti.app.services.PhotoRepository.primaryPhotoUri
                        if (primaryPhoto != null) {
                            AsyncImage(
                                model = primaryPhoto,
                                contentDescription = "Profile photo",
                                modifier = Modifier.fillMaxSize().clip(CircleShape),
                                contentScale = ContentScale.Crop
                            )
                        } else {
                            Text(
                                name.take(1).uppercase(),
                                fontSize = 28.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }

                // Info section
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Text(
                        "$name${if (age != null) ", $age" else ""}",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.textPrimary
                    )
                    if (city.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.LocationOn, null,
                                tint = colors.textMuted,
                                modifier = Modifier.size(14.dp)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(
                                city,
                                fontSize = 14.sp,
                                color = colors.textMuted
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    // Profile completeness
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Profile completeness",
                            fontSize = 13.sp,
                            color = colors.textSecondary
                        )
                        Text(
                            "$profileCompleteness%",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.Rose
                        )
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    LinearProgressIndicator(
                        progress = { profileCompleteness / 100f },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        color = AppColors.Rose,
                        trackColor = colors.border,
                        drawStopIndicator = {}
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "Fill out more to get better matches!",
                        fontSize = 12.sp,
                        color = colors.textMuted,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Complete Sindhi Identity card
        Surface(
            onClick = onCompleteSindhi,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(AppTheme.radiusMd),
            color = AppColors.Gold.copy(alpha = 0.08f),
            border = BorderStroke(1.dp, AppColors.Gold.copy(alpha = 0.15f))
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.AutoAwesome, null,
                    tint = AppColors.Gold,
                    modifier = Modifier.size(24.dp)
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        if (isNonSindhi) "Complete your Profile" else "Complete your Sindhi Identity",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.textPrimary
                    )
                    Text(
                        if (isNonSindhi) "Add more details for better matching" else "Add fluency, gotra, festivals for better cultural matching",
                        fontSize = 12.sp,
                        color = colors.textSecondary
                    )
                }
                Icon(
                    Icons.Default.ChevronRight, null,
                    tint = colors.textMuted,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
        ConfettiOverlay()
    }
}

@Composable
private fun ConfettiOverlay() {
    val palette = listOf(
        Color(0xFFB5336A), Color(0xFFD4A853), Color(0xFFE8A0BE),
        Color(0xFF8A1A4A), Color(0xFFFF6B9D), Color(0xFFFFD700)
    )
    Box(modifier = Modifier.fillMaxSize()) {
        repeat(30) { i ->
            ConfettiParticle(
                color = palette[i % palette.size],
                isCircle = i % 2 == 0,
                seed = i
            )
        }
    }
}

@Composable
private fun ConfettiParticle(color: Color, isCircle: Boolean, seed: Int) {
    val rng = remember(seed) { java.util.Random(seed.toLong() * 1009L + 31L) }
    val targetX = remember(seed) { (rng.nextFloat() * 280f) - 140f }
    val targetY = remember(seed) { 200f + rng.nextFloat() * 200f }
    val targetRotation = remember(seed) { (rng.nextFloat() * 720f) - 360f }
    val width = remember(seed) { if (isCircle) (6f + rng.nextFloat() * 4f) else (4f + rng.nextFloat() * 4f) }
    val height = remember(seed) { if (isCircle) width else (8f + rng.nextFloat() * 6f) }
    val delayMs = remember(seed) { (rng.nextFloat() * 600f).toInt() }

    val xOffset = remember { Animatable(0f) }
    val yOffset = remember { Animatable(-60f) }
    val rotation = remember { Animatable(0f) }
    val opacity = remember { Animatable(1f) }

    LaunchedEffect(Unit) {
        launch { xOffset.animateTo(targetX, tween(2000, delayMillis = delayMs, easing = EaseOut)) }
        launch { yOffset.animateTo(targetY, tween(2000, delayMillis = delayMs, easing = EaseOut)) }
        launch { rotation.animateTo(targetRotation, tween(2000, delayMillis = delayMs, easing = EaseOut)) }
        launch {
            delay((delayMs + 1200).toLong())
            opacity.animateTo(0f, tween(800, easing = EaseIn))
        }
    }

    Box(
        modifier = Modifier
            .offset(x = xOffset.value.dp, y = yOffset.value.dp)
            .rotate(rotation.value)
            .alpha(opacity.value)
            .size(width.dp, height.dp)
            .clip(if (isCircle) CircleShape else RoundedCornerShape(1.dp))
            .background(color)
    )
}

private fun genderIcon(gender: Gender): androidx.compose.ui.graphics.vector.ImageVector = when (gender) {
    Gender.MAN -> Icons.Default.Man
    Gender.WOMAN -> Icons.Default.Woman
    Gender.NON_BINARY -> Icons.Default.Transgender
}

private fun intentIcon(intent: Intent): androidx.compose.ui.graphics.vector.ImageVector = when (intent) {
    Intent.CASUAL -> Icons.Default.LocalCafe
    Intent.SERIOUS -> Icons.Default.Favorite
    Intent.OPEN -> Icons.Default.AutoAwesome
    Intent.MARRIAGE -> Icons.Default.People
}

private fun showMeIcon(option: ShowMe): androidx.compose.ui.graphics.vector.ImageVector = when (option) {
    ShowMe.MEN -> Icons.Default.Man
    ShowMe.WOMEN -> Icons.Default.Woman
    ShowMe.EVERYONE -> Icons.Default.Diversity3
}
