@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.mitimaiti.app.models.*
import com.mitimaiti.app.ui.components.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.ProfileViewModel

private val PREDEFINED_INTERESTS = listOf(
    "Travel", "Music", "Cooking", "Reading", "Fitness", "Photography",
    "Art", "Dancing", "Movies", "Gaming", "Yoga", "Hiking",
    "Food", "Fashion", "Technology", "Sports", "Writing", "Meditation",
    "Volunteering", "Gardening", "Pets", "Board Games", "Karaoke", "Comedy"
)

private val PREDEFINED_MUSIC = listOf(
    "Bollywood", "Pop", "Hip Hop", "Classical", "Sindhi Folk", "Rock",
    "Jazz", "EDM", "R&B", "Sufi", "Indie", "Country"
)

private val PREDEFINED_MOVIES = listOf(
    "Action", "Comedy", "Drama", "Romance", "Thriller", "Sci-Fi",
    "Horror", "Documentary", "Bollywood", "Anime", "Indie", "Fantasy"
)

private val PREDEFINED_FESTIVALS = listOf(
    "Cheti Chand", "Diwali", "Holi", "Eid", "Christmas", "Navratri",
    "Thadri", "Lohri", "Ganesh Chaturthi", "Raksha Bandhan"
)

private val PREDEFINED_CUISINES = listOf(
    "Sindhi", "North Indian", "South Indian", "Chinese", "Italian",
    "Japanese", "Mexican", "Thai", "Mediterranean", "Continental"
)

private val TRAVEL_STYLES = listOf(
    "Adventure", "Luxury", "Backpacking", "Cultural", "Beach", "Road Trips"
)

private val SMOKING_OPTIONS = listOf("Never", "Socially", "Regularly")
private val DRINKING_OPTIONS = listOf("Never", "Socially", "Regularly")
private val EXERCISE_OPTIONS = listOf("Daily", "Often", "Sometimes", "Never")
private val WANT_KIDS_OPTIONS = listOf("Want kids", "Don't want kids", "Open to kids", "Have kids")
private val SETTLING_OPTIONS = listOf("1-2 years", "3-5 years", "Not sure", "Already settled")

private val HEIGHT_OPTIONS = (140..210).map { it }

private val GENERATION_OPTIONS = listOf("1st Gen", "2nd Gen", "3rd Gen", "4th Gen+")
private val DIALECT_OPTIONS = listOf("Kutchi", "Hyderabadi", "Tharparkar", "Lari", "Vicholi", "Lasi", "Dhatki", "Other")
private val COMMUNITY_OPTIONS = listOf("Lohana", "Amil", "Bhaiband", "Sahiti", "Sindhi Muslim", "Sindhi Hindu", "Other")

private val PROMPT_QUESTIONS = listOf(
    "A typical Sunday for me looks like...",
    "The way to my heart is...",
    "I'm looking for someone who...",
    "My most controversial opinion is...",
    "I geek out on...",
    "My ideal first date is...",
    "Two truths and a lie...",
    "I recently discovered that...",
    "A life goal of mine is...",
    "My love language is..."
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditProfileScreen(
    viewModel: ProfileViewModel,
    onBack: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val context = LocalContext.current
    val isSaving by viewModel.isSaving.collectAsState()
    val saveSuccess by viewModel.saveSuccess.collectAsState()
    val user by viewModel.user.collectAsState()
    val scrollState = rememberScrollState()

    // Edit fields
    val bio by viewModel.editBio.collectAsState()
    val education by viewModel.editEducation.collectAsState()
    val occupation by viewModel.editOccupation.collectAsState()
    val company by viewModel.editCompany.collectAsState()
    val religion by viewModel.editReligion.collectAsState()
    val height by viewModel.editHeight.collectAsState()
    val smoking by viewModel.editSmoking.collectAsState()
    val drinking by viewModel.editDrinking.collectAsState()
    val exercise by viewModel.editExercise.collectAsState()
    val wantKids by viewModel.editWantKids.collectAsState()
    val settlingTimeline by viewModel.editSettlingTimeline.collectAsState()
    val fluency by viewModel.editFluency.collectAsState()
    val dialect by viewModel.editDialect.collectAsState()
    val generation by viewModel.editGeneration.collectAsState()
    val gotra by viewModel.editGotra.collectAsState()
    val familyOriginCity by viewModel.editFamilyOriginCity.collectAsState()
    val familyOriginCountry by viewModel.editFamilyOriginCountry.collectAsState()
    val communitySubGroup by viewModel.editCommunitySubGroup.collectAsState()
    val familyValues by viewModel.editFamilyValues.collectAsState()
    val foodPreference by viewModel.editFoodPreference.collectAsState()
    val festivals by viewModel.editFestivals.collectAsState()
    val cuisinePreferences by viewModel.editCuisinePreferences.collectAsState()
    val interests by viewModel.editInterests.collectAsState()
    val musicPreferences by viewModel.editMusicPreferences.collectAsState()
    val movieGenres by viewModel.editMovieGenres.collectAsState()
    val travelStyle by viewModel.editTravelStyle.collectAsState()
    val prompts by viewModel.editPrompts.collectAsState()

    // Photos from shared repository
    val userPhotos by viewModel.userPhotos.collectAsState()
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let { picked ->
            val bytes = com.mitimaiti.app.utils.ImageCompression.compressForUpload(context, picked)
            if (bytes != null) viewModel.uploadPhotoBytes(bytes)
        }
    }

    // Primary photo picker sheet
    var showPrimaryPhotoPicker by remember { mutableStateOf(false) }

    // Section expanded states
    var photosExpanded by remember { mutableStateOf(true) }
    var bioExpanded by remember { mutableStateOf(true) }
    var promptsExpanded by remember { mutableStateOf(true) }
    var basicsExpanded by remember { mutableStateOf(true) }
    var lifestyleExpanded by remember { mutableStateOf(false) }
    var sindhiExpanded by remember { mutableStateOf(false) }
    var culturalExpanded by remember { mutableStateOf(false) }
    var personalityExpanded by remember { mutableStateOf(false) }

    // Height picker dialog
    var showHeightPicker by remember { mutableStateOf(false) }
    // Prompt add dialog
    var showPromptDialog by remember { mutableStateOf(false) }
    var selectedPromptQuestion by remember { mutableStateOf("") }
    var promptAnswer by remember { mutableStateOf("") }

    LaunchedEffect(saveSuccess) {
        if (saveSuccess) {
            Toast.makeText(context, "Profile saved successfully!", Toast.LENGTH_SHORT).show()
            viewModel.dismissSaveSuccess()
            onBack()
        }
    }

    // Height picker dialog
    if (showHeightPicker) {
        AlertDialog(
            onDismissRequest = { showHeightPicker = false },
            title = { Text("Select Height") },
            text = {
                Column(
                    modifier = Modifier
                        .heightIn(max = 300.dp)
                        .verticalScroll(rememberScrollState())
                ) {
                    HEIGHT_OPTIONS.forEach { cm ->
                        val feet = cm / 30.48
                        val ft = feet.toInt()
                        val inches = ((feet - ft) * 12).toInt()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    viewModel.editHeight.value = cm
                                    showHeightPicker = false
                                }
                                .padding(vertical = 10.dp, horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val isSelected = height == cm
                            if (isSelected) {
                                Icon(
                                    Icons.Default.Check,
                                    null,
                                    tint = AppColors.Rose,
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                            }
                            Text(
                                "${cm}cm ($ft'$inches\")",
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                color = if (isSelected) AppColors.Rose else colors.textPrimary
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showHeightPicker = false }) {
                    Text("Cancel", color = AppColors.Rose)
                }
            }
        )
    }

    // Prompt add dialog
    if (showPromptDialog) {
        val existingQuestions = prompts.map { it.question }.toSet()
        val availableQuestions = PROMPT_QUESTIONS.filter { it !in existingQuestions }

        AlertDialog(
            onDismissRequest = { showPromptDialog = false; selectedPromptQuestion = ""; promptAnswer = "" },
            title = { Text("Add a Prompt") },
            text = {
                Column {
                    if (selectedPromptQuestion.isEmpty()) {
                        Text(
                            "Choose a question:",
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                        Column(
                            modifier = Modifier
                                .heightIn(max = 300.dp)
                                .verticalScroll(rememberScrollState())
                        ) {
                            availableQuestions.forEach { question ->
                                TextButton(
                                    onClick = { selectedPromptQuestion = question },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(
                                        question,
                                        color = colors.textPrimary,
                                        textAlign = TextAlign.Start,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                        }
                    } else {
                        Text(
                            selectedPromptQuestion,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.Rose,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                        OutlinedTextField(
                            value = promptAnswer,
                            onValueChange = { if (it.length <= 250) promptAnswer = it },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("Your answer...") },
                            minLines = 3,
                            maxLines = 5,
                            shape = RoundedCornerShape(AppTheme.radiusMd),
                            colors = editFieldColors(),
                            supportingText = {
                                Text(
                                    "${promptAnswer.length}/250",
                                    color = colors.textMuted,
                                    modifier = Modifier.fillMaxWidth(),
                                    textAlign = TextAlign.End
                                )
                            }
                        )
                    }
                }
            },
            confirmButton = {
                if (selectedPromptQuestion.isNotEmpty()) {
                    TextButton(
                        onClick = {
                            if (promptAnswer.isNotBlank()) {
                                val newPrompt = UserPrompt(
                                    question = selectedPromptQuestion,
                                    answer = promptAnswer.trim()
                                )
                                viewModel.editPrompts.value = prompts + newPrompt
                                showPromptDialog = false
                                selectedPromptQuestion = ""
                                promptAnswer = ""
                            }
                        },
                        enabled = promptAnswer.isNotBlank()
                    ) {
                        Text("Add", color = if (promptAnswer.isNotBlank()) AppColors.Rose else colors.textMuted)
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    if (selectedPromptQuestion.isNotEmpty()) {
                        selectedPromptQuestion = ""
                        promptAnswer = ""
                    } else {
                        showPromptDialog = false
                    }
                }) {
                    Text(
                        if (selectedPromptQuestion.isNotEmpty()) "Back" else "Cancel",
                        color = colors.textSecondary
                    )
                }
            }
        )
    }

    Scaffold(
        containerColor = colors.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Edit Profile",
                        fontWeight = FontWeight.Bold,
                        color = colors.textPrimary
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
                    }
                },
                actions = {
                    TextButton(
                        onClick = { viewModel.saveProfile() },
                        enabled = !isSaving
                    ) {
                        if (isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = AppColors.Rose,
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                "Save",
                                color = AppColors.Rose,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 16.sp
                            )
                        }
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
            // Photo grid (3x2)
            ExpandableSection(
                title = "Photos",
                icon = Icons.Default.PhotoLibrary,
                expanded = photosExpanded,
                onToggle = { photosExpanded = !photosExpanded }
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (row in 0..1) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            for (col in 0..2) {
                                val index = row * 3 + col
                                val photoUri = userPhotos.getOrNull(index)
                                val isMain = index == 0 && photoUri != null
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .aspectRatio(0.75f)
                                        .clip(RoundedCornerShape(AppTheme.radiusMd))
                                        .background(colors.surfaceMedium)
                                        .then(
                                            if (isMain)
                                                Modifier.border(
                                                    2.dp,
                                                    AppColors.Gold,
                                                    RoundedCornerShape(AppTheme.radiusMd)
                                                )
                                            else Modifier.border(
                                                1.dp,
                                                colors.border,
                                                RoundedCornerShape(AppTheme.radiusMd)
                                            )
                                        )
                                        .clickable {
                                            when {
                                                isMain -> showPrimaryPhotoPicker = true
                                                photoUri == null && userPhotos.size < 6 -> {
                                                    photoPickerLauncher.launch(
                                                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                                    )
                                                }
                                            }
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (photoUri != null) {
                                        AsyncImage(
                                            model = photoUri,
                                            contentDescription = "Photo ${index + 1}",
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .clip(RoundedCornerShape(AppTheme.radiusMd)),
                                            contentScale = ContentScale.Crop
                                        )
                                        // Remove button
                                        IconButton(
                                            onClick = { viewModel.removePhoto(index) },
                                            modifier = Modifier
                                                .align(Alignment.TopEnd)
                                                .size(24.dp)
                                                .background(
                                                    Color.Black.copy(alpha = 0.5f),
                                                    RoundedCornerShape(12.dp)
                                                )
                                        ) {
                                            Icon(
                                                Icons.Default.Close,
                                                "Remove",
                                                tint = Color.White,
                                                modifier = Modifier.size(14.dp)
                                            )
                                        }
                                        if (isMain) {
                                            Surface(
                                                shape = RoundedCornerShape(
                                                    bottomStart = 0.dp,
                                                    bottomEnd = 0.dp,
                                                    topStart = AppTheme.radiusMd,
                                                    topEnd = 0.dp
                                                ),
                                                color = AppColors.Gold,
                                                modifier = Modifier.align(Alignment.TopStart)
                                            ) {
                                                Text(
                                                    "MAIN",
                                                    modifier = Modifier.padding(
                                                        horizontal = 6.dp,
                                                        vertical = 2.dp
                                                    ),
                                                    fontSize = 9.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    color = Color.White
                                                )
                                            }
                                        }
                                    } else {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Icon(
                                                Icons.Default.AddAPhoto,
                                                contentDescription = "Add photo",
                                                tint = colors.textMuted,
                                                modifier = Modifier.size(28.dp)
                                            )
                                            Spacer(modifier = Modifier.height(4.dp))
                                            Text(
                                                "Add",
                                                fontSize = 11.sp,
                                                color = colors.textMuted
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Add up to 6 photos. First photo is your main profile photo.",
                    fontSize = 12.sp,
                    color = colors.textMuted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Bio section
            ExpandableSection(
                title = "Bio",
                icon = Icons.Default.Notes,
                expanded = bioExpanded,
                onToggle = { bioExpanded = !bioExpanded }
            ) {
                OutlinedTextField(
                    value = bio,
                    onValueChange = { if (it.length <= 500) viewModel.editBio.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Tell people about yourself...", color = colors.textMuted) },
                    minLines = 3,
                    maxLines = 6,
                    shape = RoundedCornerShape(AppTheme.radiusMd),
                    colors = editFieldColors(),
                    supportingText = {
                        Text(
                            "${bio.length}/500",
                            color = colors.textMuted,
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = TextAlign.End
                        )
                    }
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Prompts section
            ExpandableSection(
                title = "Prompts (${prompts.size}/3)",
                icon = Icons.Default.QuestionAnswer,
                expanded = promptsExpanded,
                onToggle = { promptsExpanded = !promptsExpanded }
            ) {
                prompts.forEachIndexed { index, prompt ->
                    GlassCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    prompt.question,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = AppColors.Rose,
                                    modifier = Modifier.weight(1f)
                                )
                                IconButton(
                                    onClick = {
                                        val mutable = prompts.toMutableList()
                                        mutable.removeAt(index)
                                        viewModel.editPrompts.value = mutable.toList()
                                    },
                                    modifier = Modifier.size(32.dp)
                                ) {
                                    Icon(
                                        Icons.Default.Close,
                                        "Remove",
                                        tint = colors.textMuted,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                prompt.answer,
                                fontSize = 14.sp,
                                color = colors.textPrimary,
                                lineHeight = 20.sp
                            )
                        }
                    }
                }
                if (prompts.size < 3) {
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { showPromptDialog = true },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        border = BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.5f))
                    ) {
                        Icon(
                            Icons.Default.Add,
                            null,
                            tint = AppColors.Rose,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Add a Prompt", color = AppColors.Rose, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Basics section
            ExpandableSection(
                title = "Basics",
                icon = Icons.Default.Person,
                expanded = basicsExpanded,
                onToggle = { basicsExpanded = !basicsExpanded }
            ) {
                EditField(
                    label = "Education",
                    value = education,
                    onValueChange = { viewModel.editEducation.value = it },
                    icon = Icons.Default.School
                )
                EditField(
                    label = "Occupation",
                    value = occupation,
                    onValueChange = { viewModel.editOccupation.value = it },
                    icon = Icons.Default.Work
                )
                EditField(
                    label = "Company",
                    value = company,
                    onValueChange = { viewModel.editCompany.value = it },
                    icon = Icons.Default.Business
                )

                // Height picker
                GlassCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showHeightPicker = true }
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Height,
                            "Height",
                            tint = AppColors.Rose,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            "Height",
                            fontSize = 14.sp,
                            color = colors.textSecondary,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            if (height != null) "${height}cm" else "Select",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (height != null) colors.textPrimary else colors.textMuted
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            Icons.Default.ChevronRight,
                            null,
                            tint = colors.textMuted,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }

                EditField(
                    label = "Religion",
                    value = religion,
                    onValueChange = { viewModel.editReligion.value = it },
                    icon = Icons.Default.TempleBuddhist
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Lifestyle section
            ExpandableSection(
                title = "Lifestyle",
                icon = Icons.Default.Spa,
                expanded = lifestyleExpanded,
                onToggle = { lifestyleExpanded = !lifestyleExpanded }
            ) {
                ChipSelectorField(
                    label = "Smoking",
                    options = SMOKING_OPTIONS,
                    selected = smoking,
                    onSelect = { viewModel.editSmoking.value = it }
                )
                ChipSelectorField(
                    label = "Drinking",
                    options = DRINKING_OPTIONS,
                    selected = drinking,
                    onSelect = { viewModel.editDrinking.value = it }
                )
                ChipSelectorField(
                    label = "Exercise",
                    options = EXERCISE_OPTIONS,
                    selected = exercise,
                    onSelect = { viewModel.editExercise.value = it }
                )
                ChipSelectorField(
                    label = "Want Kids",
                    options = WANT_KIDS_OPTIONS,
                    selected = wantKids,
                    onSelect = { viewModel.editWantKids.value = it }
                )
                ChipSelectorField(
                    label = "Settling Timeline",
                    options = SETTLING_OPTIONS,
                    selected = settlingTimeline,
                    onSelect = { viewModel.editSettlingTimeline.value = it }
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Sindhi section
            ExpandableSection(
                title = "Sindhi Identity",
                icon = Icons.Default.Language,
                expanded = sindhiExpanded,
                onToggle = { sindhiExpanded = !sindhiExpanded }
            ) {
                // Fluency picker
                ChipSelectorField(
                    label = "Sindhi Fluency",
                    options = SindhiFluency.entries.map { it.displayName },
                    selected = fluency?.displayName ?: "",
                    onSelect = { name ->
                        viewModel.editFluency.value =
                            SindhiFluency.entries.firstOrNull { it.displayName == name }
                    }
                )
                ChipSelectorField(
                    label = "Dialect",
                    options = DIALECT_OPTIONS,
                    selected = dialect,
                    onSelect = { viewModel.editDialect.value = it }
                )
                ChipSelectorField(
                    label = "Generation",
                    options = GENERATION_OPTIONS,
                    selected = generation,
                    onSelect = { viewModel.editGeneration.value = it }
                )
                EditField(
                    label = "Gotra",
                    value = gotra,
                    onValueChange = { viewModel.editGotra.value = it },
                    icon = Icons.Default.AccountTree
                )
                EditField(
                    label = "Family Origin City",
                    value = familyOriginCity,
                    onValueChange = { viewModel.editFamilyOriginCity.value = it },
                    icon = Icons.Default.Home
                )
                EditField(
                    label = "Family Origin Country",
                    value = familyOriginCountry,
                    onValueChange = { viewModel.editFamilyOriginCountry.value = it },
                    icon = Icons.Default.Public
                )
                ChipSelectorField(
                    label = "Community",
                    options = COMMUNITY_OPTIONS,
                    selected = communitySubGroup,
                    onSelect = { viewModel.editCommunitySubGroup.value = it }
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Cultural section
            ExpandableSection(
                title = "Cultural",
                icon = Icons.Default.Celebration,
                expanded = culturalExpanded,
                onToggle = { culturalExpanded = !culturalExpanded }
            ) {
                // Family Values
                ChipSelectorField(
                    label = "Family Values",
                    options = FamilyValues.entries.map { it.displayName },
                    selected = familyValues?.displayName ?: "",
                    onSelect = { name ->
                        viewModel.editFamilyValues.value =
                            FamilyValues.entries.firstOrNull { it.displayName == name }
                    }
                )
                // Food Preference
                ChipSelectorField(
                    label = "Food Preference",
                    options = FoodPreference.entries.map { it.displayName },
                    selected = foodPreference?.displayName ?: "",
                    onSelect = { name ->
                        viewModel.editFoodPreference.value =
                            FoodPreference.entries.firstOrNull { it.displayName == name }
                    }
                )
                // Festivals (multi-select)
                MultiSelectChipField(
                    label = "Festivals",
                    options = PREDEFINED_FESTIVALS,
                    selected = festivals,
                    onToggle = { item ->
                        val current = festivals.toMutableList()
                        if (current.contains(item)) current.remove(item) else current.add(item)
                        viewModel.editFestivals.value = current.toList()
                    }
                )
                // Cuisine Preferences (multi-select)
                MultiSelectChipField(
                    label = "Cuisine Preferences",
                    options = PREDEFINED_CUISINES,
                    selected = cuisinePreferences,
                    onToggle = { item ->
                        val current = cuisinePreferences.toMutableList()
                        if (current.contains(item)) current.remove(item) else current.add(item)
                        viewModel.editCuisinePreferences.value = current.toList()
                    }
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Personality section
            ExpandableSection(
                title = "Personality",
                icon = Icons.Default.EmojiEmotions,
                expanded = personalityExpanded,
                onToggle = { personalityExpanded = !personalityExpanded }
            ) {
                // Interests (multi-select)
                MultiSelectChipField(
                    label = "Interests",
                    options = PREDEFINED_INTERESTS,
                    selected = interests,
                    onToggle = { item ->
                        val current = interests.toMutableList()
                        if (current.contains(item)) current.remove(item) else current.add(item)
                        viewModel.editInterests.value = current.toList()
                    }
                )
                // Music (multi-select)
                MultiSelectChipField(
                    label = "Music",
                    options = PREDEFINED_MUSIC,
                    selected = musicPreferences,
                    onToggle = { item ->
                        val current = musicPreferences.toMutableList()
                        if (current.contains(item)) current.remove(item) else current.add(item)
                        viewModel.editMusicPreferences.value = current.toList()
                    }
                )
                // Movies (multi-select)
                MultiSelectChipField(
                    label = "Movies",
                    options = PREDEFINED_MOVIES,
                    selected = movieGenres,
                    onToggle = { item ->
                        val current = movieGenres.toMutableList()
                        if (current.contains(item)) current.remove(item) else current.add(item)
                        viewModel.editMovieGenres.value = current.toList()
                    }
                )
                // Travel Style
                ChipSelectorField(
                    label = "Travel Style",
                    options = TRAVEL_STYLES,
                    selected = travelStyle,
                    onSelect = { viewModel.editTravelStyle.value = it }
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    // Primary photo picker sheet for MAIN photo slot
    if (showPrimaryPhotoPicker) {
        PrimaryPhotoPickerSheet(
            existingPhotos = userPhotos,
            onDismiss = { showPrimaryPhotoPicker = false },
            onNewPhotoFromGallery = { uri ->
                viewModel.addPhoto(uri)
                // Move the newly added photo to primary position
                val newIndex = com.mitimaiti.app.services.PhotoRepository.photos.value.indexOf(uri)
                if (newIndex > 0) viewModel.setPrimaryPhoto(newIndex)
            },
            onSetPrimary = { index -> viewModel.setPrimaryPhoto(index) }
        )
    }
}

@Composable
private fun ExpandableSection(
    title: String,
    icon: ImageVector,
    expanded: Boolean,
    onToggle: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    val colors = LocalAdaptiveColors.current
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onToggle)
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(icon, null, tint = AppColors.Rose, modifier = Modifier.size(22.dp))
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    title,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.textPrimary,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = colors.textMuted,
                    modifier = Modifier.size(24.dp)
                )
            }
            // Content
            AnimatedVisibility(
                visible = expanded,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                Column(
                    modifier = Modifier.padding(
                        start = 16.dp,
                        end = 16.dp,
                        bottom = 16.dp
                    ),
                    content = content
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipSelectorField(
    label: String,
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Column(modifier = Modifier.padding(vertical = 6.dp)) {
        Text(
            label,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textSecondary,
            modifier = Modifier.padding(bottom = 8.dp)
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            options.forEach { option ->
                val isSelected = option == selected
                FilterChip(
                    selected = isSelected,
                    onClick = { onSelect(option) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.Rose,
                        selectedLabelColor = Color.White,
                        containerColor = colors.surfaceMedium,
                        labelColor = colors.textPrimary
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        borderColor = colors.border,
                        selectedBorderColor = AppColors.Rose,
                        enabled = true,
                        selected = isSelected
                    )
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun MultiSelectChipField(
    label: String,
    options: List<String>,
    selected: List<String>,
    onToggle: (String) -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Column(modifier = Modifier.padding(vertical = 6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                label,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textSecondary
            )
            if (selected.isNotEmpty()) {
                Text(
                    "${selected.size} selected",
                    fontSize = 12.sp,
                    color = AppColors.Rose
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            options.forEach { option ->
                val isSelected = selected.contains(option)
                FilterChip(
                    selected = isSelected,
                    onClick = { onToggle(option) },
                    label = { Text(option, fontSize = 13.sp) },
                    leadingIcon = if (isSelected) {
                        {
                            Icon(
                                Icons.Default.Check,
                                null,
                                modifier = Modifier.size(16.dp),
                                tint = Color.White
                            )
                        }
                    } else null,
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.Rose,
                        selectedLabelColor = Color.White,
                        containerColor = colors.surfaceMedium,
                        labelColor = colors.textPrimary
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        borderColor = colors.border,
                        selectedBorderColor = AppColors.Rose,
                        enabled = true,
                        selected = isSelected
                    )
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    val colors = LocalAdaptiveColors.current
    Text(
        title,
        fontSize = 18.sp,
        fontWeight = FontWeight.Bold,
        color = colors.textPrimary,
        modifier = Modifier.padding(vertical = 8.dp)
    )
}

@Composable
private fun EditField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    icon: ImageVector
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        label = { Text(label) },
        leadingIcon = { Icon(icon, label, tint = AppColors.Rose, modifier = Modifier.size(20.dp)) },
        shape = RoundedCornerShape(AppTheme.radiusMd),
        colors = editFieldColors(),
        singleLine = true
    )
}

@Composable
private fun editFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AppColors.Rose,
    unfocusedBorderColor = LocalAdaptiveColors.current.border,
    focusedTextColor = LocalAdaptiveColors.current.textPrimary,
    unfocusedTextColor = LocalAdaptiveColors.current.textPrimary,
    focusedLabelColor = AppColors.Rose,
    unfocusedLabelColor = LocalAdaptiveColors.current.textMuted
)
