package com.mitimaiti.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.models.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors

data class FilterState(
    val ageMin: Int = 21,
    val ageMax: Int = 35,
    val heightMin: Int = 150,
    val heightMax: Int = 190,
    val genderPreference: ShowMe = ShowMe.EVERYONE,
    val intentFilter: Intent? = null,
    val verifiedOnly: Boolean = false,
    val expandAgeRange: Boolean = true,
    val flexibleHeight: Boolean = true,
    val includeOtherIntents: Boolean = true,
    val selectedInterests: List<String> = emptyList(),
    // Lifestyle tab
    val fluencyFilter: SindhiFluency? = null,
    val generationFilter: String? = null,
    val religionFilter: String? = null,
    val gotraFilter: String? = null,
    val dietaryFilter: FoodPreference? = null,
    val educationFilter: String? = null,
    val smokingFilter: String? = null,
    val drinkingFilter: String? = null,
    val familyPlansFilter: String? = null,
    val exerciseFilter: String? = null
)

private val INTERESTS = listOf(
    "Travel", "Cooking", "Cricket", "Music", "Fitness", "Reading",
    "Photography", "Dancing", "Art", "Movies", "Yoga", "Hiking",
    "Coffee", "Food", "Gaming"
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun FilterSheet(
    filterState: FilterState,
    onFilterChanged: (FilterState) -> Unit,
    onDismiss: () -> Unit,
    onReset: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    var state by remember { mutableStateOf(filterState) }
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Essentials", "Lifestyle")

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        dragHandle = {
            Box(
                modifier = Modifier
                    .padding(vertical = 12.dp)
                    .width(40.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(colors.textMuted.copy(alpha = 0.3f))
            )
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 16.dp)
        ) {
            // Header: X — Refine Discovery — Reset
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, "Close", tint = colors.textSecondary)
                }
                Text(
                    "Refine Discovery",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                TextButton(onClick = {
                    state = FilterState()
                    onReset()
                }) {
                    Icon(Icons.Default.Refresh, null, tint = AppColors.Rose, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Reset", color = AppColors.Rose, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Tab bar: Essentials | Lifestyle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .clip(RoundedCornerShape(AppTheme.radiusFull))
                    .background(colors.surfaceMedium),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                tabs.forEachIndexed { index, title ->
                    val isSelected = selectedTab == index
                    Surface(
                        onClick = { selectedTab = index },
                        modifier = Modifier
                            .weight(1f)
                            .padding(4.dp),
                        shape = RoundedCornerShape(AppTheme.radiusFull),
                        color = if (isSelected) AppColors.Rose else Color.Transparent
                    ) {
                        Text(
                            title,
                            modifier = Modifier.padding(vertical = 10.dp),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (isSelected) Color.White else colors.textSecondary,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Tab content
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (selectedTab == 0) {
                    EssentialsTab(state) { state = it }
                } else {
                    LifestyleTab(state) { state = it }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Show Results button
            Button(
                onClick = {
                    onFilterChanged(state)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .height(52.dp),
                shape = RoundedCornerShape(AppTheme.radiusFull),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
            ) {
                Text("Show Results", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EssentialsTab(state: FilterState, onUpdate: (FilterState) -> Unit) {
    val colors = LocalAdaptiveColors.current

    // Age Range
    FilterCard {
        Text("Age range", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(4.dp))
        Text("Between ${state.ageMin} and ${state.ageMax}", fontSize = 14.sp, color = colors.textSecondary)
        Spacer(modifier = Modifier.height(8.dp))
        RangeSlider(
            value = state.ageMin.toFloat()..state.ageMax.toFloat(),
            onValueChange = { range ->
                onUpdate(state.copy(ageMin = range.start.toInt(), ageMax = range.endInclusive.toInt()))
            },
            valueRange = 18f..60f,
            steps = 41,
            colors = SliderDefaults.colors(
                thumbColor = AppColors.Rose,
                activeTrackColor = AppColors.Rose,
                inactiveTrackColor = colors.border
            )
        )
        ToggleRow("Expand range if few results", state.expandAgeRange) {
            onUpdate(state.copy(expandAgeRange = it))
        }
    }

    // Height
    FilterCard {
        Text("Height", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(4.dp))
        Text("${state.heightMin} cm — ${state.heightMax} cm", fontSize = 14.sp, color = colors.textSecondary)
        Spacer(modifier = Modifier.height(8.dp))
        RangeSlider(
            value = state.heightMin.toFloat()..state.heightMax.toFloat(),
            onValueChange = { range ->
                onUpdate(state.copy(heightMin = range.start.toInt(), heightMax = range.endInclusive.toInt()))
            },
            valueRange = 140f..210f,
            steps = 69,
            colors = SliderDefaults.colors(
                thumbColor = AppColors.Rose,
                activeTrackColor = AppColors.Rose,
                inactiveTrackColor = colors.border
            )
        )
        ToggleRow("Flexible on height", state.flexibleHeight) {
            onUpdate(state.copy(flexibleHeight = it))
        }
    }

    // Looking for
    FilterCard {
        Text("Looking for", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Intent.entries.forEach { intent ->
                FilterChip(
                    selected = state.intentFilter == intent,
                    onClick = {
                        onUpdate(state.copy(intentFilter = if (state.intentFilter == intent) null else intent))
                    },
                    label = { Text(intent.displayName, fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.Rose.copy(alpha = 0.15f),
                        selectedLabelColor = AppColors.Rose
                    )
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        ToggleRow("Include others if few results", state.includeOtherIntents) {
            onUpdate(state.copy(includeOtherIntents = it))
        }
    }

    // Shared interests
    FilterCard {
        Text("Shared interests", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(4.dp))
        Text("Tap to prioritize people who share these", fontSize = 13.sp, color = colors.textSecondary)
        Spacer(modifier = Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            INTERESTS.forEach { interest ->
                val isSelected = state.selectedInterests.contains(interest)
                FilterChip(
                    selected = isSelected,
                    onClick = {
                        val updated = if (isSelected) state.selectedInterests - interest
                        else state.selectedInterests + interest
                        onUpdate(state.copy(selectedInterests = updated))
                    },
                    label = { Text(interest, fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.Rose.copy(alpha = 0.15f),
                        selectedLabelColor = AppColors.Rose
                    )
                )
            }
        }
    }

    // Verified profiles only
    FilterCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text("Verified profiles only", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text("Photo-verified members", fontSize = 13.sp, color = colors.textSecondary)
            }
            Switch(
                checked = state.verifiedOnly,
                onCheckedChange = { onUpdate(state.copy(verifiedOnly = it)) },
                colors = SwitchDefaults.colors(
                    checkedTrackColor = AppColors.Rose,
                    checkedThumbColor = Color.White
                )
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LifestyleTab(state: FilterState, onUpdate: (FilterState) -> Unit) {
    val colors = LocalAdaptiveColors.current
    val chipColors = FilterChipDefaults.filterChipColors(
        selectedContainerColor = AppColors.Rose.copy(alpha = 0.15f),
        selectedLabelColor = AppColors.Rose
    )

    // Culture
    FilterCard {
        Text("Culture", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)

        Spacer(modifier = Modifier.height(12.dp))
        Text("SINDHI FLUENCY", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Fluent", "Conversational", "Basic", "Learning").forEach { option ->
                val fluency = SindhiFluency.entries.find { it.displayName == option }
                FilterChip(
                    selected = state.fluencyFilter == fluency,
                    onClick = { onUpdate(state.copy(fluencyFilter = if (state.fluencyFilter == fluency) null else fluency)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text("RELIGION", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Hindu", "Sikh", "Muslim", "Other").forEach { religion ->
                FilterChip(
                    selected = state.religionFilter == religion,
                    onClick = { onUpdate(state.copy(religionFilter = if (state.religionFilter == religion) null else religion)) },
                    label = { Text(religion, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text("DIETARY PREFERENCE", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Veg", "Non-Veg", "Vegan", "Jain").forEach { option ->
                val pref = FoodPreference.entries.find { it.displayName == option }
                FilterChip(
                    selected = state.dietaryFilter == pref,
                    onClick = { onUpdate(state.copy(dietaryFilter = if (state.dietaryFilter == pref) null else pref)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text("GOTRA", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Lohana", "Amil", "Bhatia", "Sahiti", "Chhapru").forEach { gotra ->
                FilterChip(
                    selected = state.gotraFilter == gotra,
                    onClick = { onUpdate(state.copy(gotraFilter = if (state.gotraFilter == gotra) null else gotra)) },
                    label = { Text(gotra, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }
    }

    // Education
    FilterCard {
        Text("Education", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Bachelors", "Masters", "PhD", "Professional").forEach { edu ->
                FilterChip(
                    selected = state.educationFilter == edu,
                    onClick = { onUpdate(state.copy(educationFilter = if (state.educationFilter == edu) null else edu)) },
                    label = { Text(edu, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }
    }

    // Habits
    FilterCard {
        Text("Habits", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)

        Spacer(modifier = Modifier.height(12.dp))
        Text("SMOKING", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Never", "Socially", "Regularly").forEach { option ->
                FilterChip(
                    selected = state.smokingFilter == option,
                    onClick = { onUpdate(state.copy(smokingFilter = if (state.smokingFilter == option) null else option)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text("DRINKING", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Never", "Socially", "Regularly").forEach { option ->
                FilterChip(
                    selected = state.drinkingFilter == option,
                    onClick = { onUpdate(state.copy(drinkingFilter = if (state.drinkingFilter == option) null else option)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text("EXERCISE", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.textMuted, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Daily", "Often", "Sometimes", "Never").forEach { option ->
                FilterChip(
                    selected = state.exerciseFilter == option,
                    onClick = { onUpdate(state.copy(exerciseFilter = if (state.exerciseFilter == option) null else option)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }
    }

    // Family Plans
    FilterCard {
        Text("Family Plans", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        Spacer(modifier = Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Yes", "No", "Open to it", "Already has").forEach { option ->
                FilterChip(
                    selected = state.familyPlansFilter == option,
                    onClick = { onUpdate(state.copy(familyPlansFilter = if (state.familyPlansFilter == option) null else option)) },
                    label = { Text(option, fontSize = 13.sp) },
                    colors = chipColors
                )
            }
        }
    }
}

@Composable
private fun FilterCard(content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalAdaptiveColors.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(AppTheme.radiusMd),
        color = colors.surfaceMedium
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            content = content
        )
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val colors = LocalAdaptiveColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 14.sp, color = colors.textSecondary)
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
