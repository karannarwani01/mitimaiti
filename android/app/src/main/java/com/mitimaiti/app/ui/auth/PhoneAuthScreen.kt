@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.auth

import android.content.Context
import android.telephony.TelephonyManager
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.mitimaiti.app.BuildConfig
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel
import kotlinx.coroutines.launch

data class CountryCode(
    val code: String,
    val country: String,
    val shortName: String
)

private val countryCodes = listOf(
    CountryCode("+91", "India", "IN"),
    CountryCode("+971", "UAE", "AE"),
    CountryCode("+44", "United Kingdom", "GB"),
    CountryCode("+1", "USA", "US"),
    CountryCode("+1", "Canada", "CA"),
    CountryCode("+65", "Singapore", "SG"),
    CountryCode("+852", "Hong Kong", "HK"),
    CountryCode("+61", "Australia", "AU"),
    CountryCode("+254", "Kenya", "KE"),
    CountryCode("+234", "Nigeria", "NG"),
)

/**
 * Best guess of the user's country for the phone-code picker, in order of
 * reliability for a phone number: SIM card country → registered network
 * country → device locale region. None of these require any permission.
 * Falls back to the first entry (India) if the region isn't in our list.
 */
private fun detectCountryCode(context: Context): CountryCode {
    val iso = try {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        tm?.simCountryIso?.takeIf { it.isNotBlank() }
            ?: tm?.networkCountryIso?.takeIf { it.isNotBlank() }
            ?: java.util.Locale.getDefault().country
    } catch (_: Exception) {
        java.util.Locale.getDefault().country
    }
    return countryCodes.firstOrNull { it.shortName.equals(iso, ignoreCase = true) }
        ?: countryCodes[0]
}

@Composable
fun PhoneAuthScreen(viewModel: AuthViewModel, onOTPSent: () -> Unit, onEmailSelected: () -> Unit, onBack: () -> Unit) {
    val colors = LocalAdaptiveColors.current
    val view = LocalView.current
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val otpSent by viewModel.otpSent.collectAsState()
    val isAuthenticated by viewModel.isAuthenticated.collectAsState()
    var selectedCountry by remember { mutableStateOf(detectCountryCode(context)) }
    var showDropdown by remember { mutableStateOf(false) }
    var isPhoneFocused by remember { mutableStateOf(false) }
    // Local digits-only state (no country code). The viewmodel's `phone` holds
    // the full E.164 we send to the API — we set it once on submit; binding the
    // input to it caused the field to redisplay "+919876543210" after Continue.
    var rawPhone by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(otpSent) { if (otpSent) onOTPSent() }
    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated) onOTPSent()
    }

    // Google Sign-In via Credential Manager. Pulls a Google ID token, hands it
    // off to the backend's /v1/auth/google/verify endpoint via AuthViewModel.
    val onGoogleSignIn: () -> Unit = {
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank()) {
            viewModel.setGoogleSignInError(
                "Google sign-in not configured (missing GOOGLE_WEB_CLIENT_ID)."
            )
        } else {
            coroutineScope.launch {
                val credentialManager = CredentialManager.create(context)
                val googleIdOption = GetGoogleIdOption.Builder()
                    .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
                    .setFilterByAuthorizedAccounts(false)
                    .setAutoSelectEnabled(false)
                    .build()
                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(googleIdOption)
                    .build()
                try {
                    val result = credentialManager.getCredential(context, request)
                    val credential = result.credential
                    if (credential is CustomCredential &&
                        credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                    ) {
                        val tokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                        viewModel.signInWithGoogle(tokenCredential.idToken)
                    } else {
                        viewModel.setGoogleSignInError("Unexpected credential type from Google.")
                    }
                } catch (e: GetCredentialCancellationException) {
                    // User dismissed the picker — silent, no error toast.
                } catch (e: NoCredentialException) {
                    viewModel.setGoogleSignInError(
                        "No Google account available on this device. Add one in Settings."
                    )
                } catch (e: GetCredentialException) {
                    viewModel.setGoogleSignInError(
                        e.localizedMessage ?: "Google sign-in failed. Please try again."
                    )
                }
            }
        }
    }

    val phoneBorderColor by animateColorAsState(
        targetValue = if (isPhoneFocused) AppColors.Rose else colors.border,
        animationSpec = tween(200), label = "phoneBorder"
    )

    Box(modifier = Modifier.fillMaxSize().background(colors.backgroundGradient)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
        ) {
            Spacer(modifier = Modifier.height(8.dp))

            // Header: Back + centered "MitiMaiti"
            Box(modifier = Modifier.fillMaxWidth()) {
                IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                    Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
                }
                Text(
                    "MitiMaiti",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.Rose,
                    modifier = Modifier.align(Alignment.Center)
                )
            }

            Spacer(modifier = Modifier.height(28.dp))

            // Title
            Text(
                "What's your phone number?",
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary,
                lineHeight = 32.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Phone input row: Country code selector + Phone field
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Country code selector
                Box {
                    Surface(
                        modifier = Modifier
                            .height(56.dp)
                            .clickable {
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                showDropdown = !showDropdown
                            },
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        color = colors.surfaceMedium,
                        border = androidx.compose.foundation.BorderStroke(1.dp, colors.border)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                "${selectedCountry.shortName} ${selectedCountry.code}",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = colors.textPrimary
                            )
                            Icon(
                                Icons.Default.KeyboardArrowDown,
                                contentDescription = "Select country",
                                modifier = Modifier.size(18.dp),
                                tint = colors.textSecondary
                            )
                        }
                    }

                    // Dropdown
                    DropdownMenu(
                        expanded = showDropdown,
                        onDismissRequest = { showDropdown = false },
                        modifier = Modifier
                            .width(260.dp)
                            .background(colors.surface)
                    ) {
                        countryCodes.forEachIndexed { index, cc ->
                            DropdownMenuItem(
                                text = {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(
                                            "${cc.shortName} - ${cc.country}",
                                            fontSize = 14.sp,
                                            color = colors.textPrimary
                                        )
                                        Text(
                                            cc.code,
                                            fontSize = 14.sp,
                                            color = colors.textSecondary
                                        )
                                    }
                                },
                                onClick = {
                                    selectedCountry = cc
                                    showDropdown = false
                                }
                            )
                        }
                    }
                }

                // Phone number input
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(56.dp)
                        .clip(RoundedCornerShape(AppTheme.radiusMd))
                        .background(colors.surfaceMedium)
                        .border(1.dp, phoneBorderColor, RoundedCornerShape(AppTheme.radiusMd))
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    if (rawPhone.isEmpty()) {
                        Text(
                            "98765 43210",
                            fontSize = 16.sp,
                            color = colors.textMuted
                        )
                    }
                    BasicTextField(
                        value = rawPhone,
                        onValueChange = { newValue ->
                            rawPhone = newValue.filter { it.isDigit() }.take(10)
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .onFocusChanged { isPhoneFocused = it.isFocused },
                        textStyle = TextStyle(
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            color = colors.textPrimary
                        ),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        singleLine = true,
                        cursorBrush = SolidColor(AppColors.Rose)
                    )
                }
            }

            // Privacy note
            Spacer(modifier = Modifier.height(14.dp))
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    Icons.Default.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp).offset(y = 2.dp),
                    tint = colors.textSecondary
                )
                Text(
                    "We'll send you a verification code. Standard SMS rates may apply.",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                    lineHeight = 18.sp
                )
            }

            // Error message
            AnimatedVisibility(
                visible = error != null,
                enter = fadeIn() + slideInVertically(),
                exit = fadeOut() + slideOutVertically()
            ) {
                error?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(it, color = AppColors.Error, fontSize = 14.sp)
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Continue button with rose gradient
            val isValid = rawPhone.length >= 7
            Button(
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    // Build E.164 only at submit time so the visible field stays
                    // local digits while the viewmodel holds the full number for
                    // the API + the OTP screen subtitle.
                    viewModel.updatePhone("${selectedCountry.code}$rawPhone")
                    viewModel.sendOTP()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                enabled = isValid && !isLoading,
                shape = RoundedCornerShape(AppTheme.radiusLg),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppColors.Rose,
                    disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                )
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        "Continue",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                }
            }

            // Divider: "or continue with"
            Spacer(modifier = Modifier.height(20.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Divider(modifier = Modifier.weight(1f), color = colors.border)
                Text(
                    "or continue with",
                    fontSize = 13.sp,
                    color = colors.textSecondary,
                    fontWeight = FontWeight.Medium
                )
                Divider(modifier = Modifier.weight(1f), color = colors.border)
            }

            // Social sign-in — Bumble-style: phone is the primary method, Google
            // the only alternative. Email lives in Settings → Sign-in methods.
            Spacer(modifier = Modifier.height(20.dp))
            SocialSignInButton(
                label = "Continue with Google",
                modifier = Modifier.fillMaxWidth(),
                backgroundColor = colors.surfaceMedium,
                borderColor = colors.border,
                textColor = colors.textPrimary,
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    onGoogleSignIn()
                }
            ) {
                GoogleIcon(modifier = Modifier.size(20.dp))
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SocialSignInButton(
    label: String,
    modifier: Modifier = Modifier,
    backgroundColor: Color,
    borderColor: Color,
    textColor: Color,
    onClick: () -> Unit,
    icon: @Composable () -> Unit
) {
    Surface(
        modifier = modifier
            .height(48.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = ripple(),
                onClick = onClick
            ),
        shape = RoundedCornerShape(AppTheme.radiusMd),
        color = backgroundColor,
        border = if (borderColor != Color.Transparent) {
            androidx.compose.foundation.BorderStroke(1.dp, borderColor)
        } else null
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            icon()
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                label,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = textColor
            )
        }
    }
}

// Multicolor Google "G" logo drawn with Canvas
@Composable
private fun GoogleIcon(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val s = size.width / 24f
        // Blue arc (right side)
        val bluePath = Path().apply {
            moveTo(22.56f * s, 12.25f * s)
            cubicTo(22.56f * s, 11.47f * s, 22.49f * s, 10.72f * s, 22.36f * s, 10f * s)
            lineTo(12f * s, 10f * s)
            lineTo(12f * s, 14.26f * s)
            lineTo(17.92f * s, 14.26f * s)
            cubicTo(17.66f * s, 15.63f * s, 16.89f * s, 16.79f * s, 15.72f * s, 17.58f * s)
            lineTo(15.72f * s, 20.35f * s)
            lineTo(19.29f * s, 20.35f * s)
            cubicTo(21.37f * s, 18.43f * s, 22.56f * s, 15.61f * s, 22.56f * s, 12.25f * s)
            close()
        }
        drawPath(bluePath, color = Color(0xFF4285F4))

        // Green arc (bottom)
        val greenPath = Path().apply {
            moveTo(12f * s, 23f * s)
            cubicTo(14.97f * s, 23f * s, 17.46f * s, 22.02f * s, 19.28f * s, 20.34f * s)
            lineTo(15.71f * s, 17.57f * s)
            cubicTo(14.73f * s, 18.23f * s, 13.48f * s, 18.63f * s, 12f * s, 18.63f * s)
            cubicTo(9.14f * s, 18.63f * s, 6.71f * s, 16.7f * s, 5.84f * s, 14.1f * s)
            lineTo(2.18f * s, 14.1f * s)
            lineTo(2.18f * s, 16.94f * s)
            cubicTo(3.99f * s, 20.53f * s, 7.7f * s, 23f * s, 12f * s, 23f * s)
            close()
        }
        drawPath(greenPath, color = Color(0xFF34A853))

        // Yellow arc (bottom-left)
        val yellowPath = Path().apply {
            moveTo(5.84f * s, 14.09f * s)
            cubicTo(5.62f * s, 13.43f * s, 5.49f * s, 12.73f * s, 5.49f * s, 12f * s)
            cubicTo(5.49f * s, 11.27f * s, 5.62f * s, 10.57f * s, 5.84f * s, 9.91f * s)
            lineTo(5.84f * s, 7.07f * s)
            lineTo(2.18f * s, 7.07f * s)
            cubicTo(1.43f * s, 8.55f * s, 1f * s, 10.22f * s, 1f * s, 12f * s)
            cubicTo(1f * s, 13.78f * s, 1.43f * s, 15.45f * s, 2.18f * s, 16.93f * s)
            lineTo(5.84f * s, 14.09f * s)
            close()
        }
        drawPath(yellowPath, color = Color(0xFFFBBC05))

        // Red arc (top-left)
        val redPath = Path().apply {
            moveTo(12f * s, 5.38f * s)
            cubicTo(13.62f * s, 5.38f * s, 15.06f * s, 5.94f * s, 16.21f * s, 7.02f * s)
            lineTo(19.36f * s, 3.87f * s)
            cubicTo(17.45f * s, 2.09f * s, 14.97f * s, 1f * s, 12f * s, 1f * s)
            cubicTo(7.7f * s, 1f * s, 3.99f * s, 3.47f * s, 2.18f * s, 7.07f * s)
            lineTo(5.84f * s, 9.91f * s)
            cubicTo(6.71f * s, 7.31f * s, 9.14f * s, 5.38f * s, 12f * s, 5.38f * s)
            close()
        }
        drawPath(redPath, color = Color(0xFFEA4335))
    }
}

// Email envelope icon drawn with Canvas
@Composable
private fun EmailIcon(modifier: Modifier = Modifier, tint: Color = Color.Gray) {
    Canvas(modifier = modifier) {
        val s = size.width / 24f
        val strokeW = 2f * s
        // Envelope body (rounded rect)
        val rectPath = Path().apply {
            moveTo(4f * s, 4f * s)
            lineTo(20f * s, 4f * s)
            cubicTo(21.1f * s, 4f * s, 22f * s, 4.9f * s, 22f * s, 6f * s)
            lineTo(22f * s, 18f * s)
            cubicTo(22f * s, 19.1f * s, 21.1f * s, 20f * s, 20f * s, 20f * s)
            lineTo(4f * s, 20f * s)
            cubicTo(2.9f * s, 20f * s, 2f * s, 19.1f * s, 2f * s, 18f * s)
            lineTo(2f * s, 6f * s)
            cubicTo(2f * s, 4.9f * s, 2.9f * s, 4f * s, 4f * s, 4f * s)
            close()
        }
        drawPath(
            rectPath,
            color = tint,
            style = Stroke(width = strokeW, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )
        // Envelope flap (V shape)
        val flapPath = Path().apply {
            moveTo(22f * s, 7f * s)
            lineTo(13.03f * s, 12.7f * s)
            cubicTo(12.39f * s, 13.09f * s, 11.61f * s, 13.09f * s, 10.97f * s, 12.7f * s)
            lineTo(2f * s, 7f * s)
        }
        drawPath(
            flapPath,
            color = tint,
            style = Stroke(width = strokeW, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )
    }
}
