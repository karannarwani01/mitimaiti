package com.mitimaiti.app.ui.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.R
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel

/**
 * Bumble-style "Can we get your number?" — shown after a Google/Apple/email
 * signup so every account ends up anchored to a verified phone. Uses the
 * link/phone/start + verify SMS OTP flow.
 *
 * Flip PHONE_STEP_SKIPPABLE to false once Twilio is upgraded from trial —
 * then the step becomes mandatory, matching Bumble exactly.
 */
private const val PHONE_STEP_SKIPPABLE = true

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LinkAccountScreen(viewModel: AuthViewModel, onDone: () -> Unit) {
    val colors = LocalAdaptiveColors.current

    val inProgress by viewModel.linkInProgress.collectAsState()
    val result by viewModel.linkResult.collectAsState()
    val otpSent by viewModel.linkPhoneOtpSent.collectAsState()
    val pendingPhone by viewModel.pendingLinkPhone.collectAsState()

    var phoneInput by remember { mutableStateOf("") }
    var codeInput by remember { mutableStateOf("") }

    val linked = result == "success" || result == "merged"
    val errorMsg = result?.takeIf { it != "success" && it != "merged" }

    DisposableEffect(Unit) {
        onDispose { viewModel.clearLinkResult(); viewModel.resetLinkPhoneOtp() }
    }

    Box(
        modifier = Modifier.fillMaxSize().background(colors.backgroundGradient).statusBarsPadding(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.logo_mark),
                contentDescription = null,
                modifier = Modifier.size(84.dp)
            )
            Spacer(Modifier.height(24.dp))
            Text(
                if (linked) "Number verified!" else "Can we get your number?",
                fontSize = 26.sp, fontWeight = FontWeight.Bold,
                color = colors.textPrimary, textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(10.dp))

            if (linked) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, tint = Color(0xFF2FB672), modifier = Modifier.size(26.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(
                        if (result == "merged") "We found your existing profile and merged your sign-ins."
                        else "Your account is secured with your phone number.",
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary
                    )
                }
                Spacer(Modifier.height(28.dp))
                Button(
                    onClick = onDone,
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = RoundedCornerShape(AppTheme.radiusLg),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
                ) { Text("Continue", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White) }
            } else {
                Text(
                    if (!otpSent)
                        "We'll text you a code to verify it. It keeps your account secure and makes signing back in easy."
                    else
                        "Enter the 6-digit code we texted to $pendingPhone.",
                    fontSize = 15.sp, color = colors.textSecondary,
                    textAlign = TextAlign.Center, lineHeight = 22.sp
                )
                Spacer(Modifier.height(28.dp))

                if (!otpSent) {
                    OutlinedTextField(
                        value = phoneInput,
                        onValueChange = { phoneInput = it.filter { c -> c.isDigit() || c == '+' }.take(16) },
                        singleLine = true,
                        placeholder = { Text("+971501234567", color = colors.textMuted) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.Rose,
                            unfocusedBorderColor = colors.border,
                            focusedTextColor = colors.textPrimary,
                            unfocusedTextColor = colors.textPrimary
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { viewModel.linkPhoneStart(phoneInput) },
                        enabled = !inProgress && phoneInput.length >= 8,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.Rose,
                            disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                        )
                    ) {
                        Text(if (inProgress) "Sending…" else "Send code",
                            fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                } else {
                    OutlinedTextField(
                        value = codeInput,
                        onValueChange = { codeInput = it.filter { c -> c.isDigit() }.take(6) },
                        singleLine = true,
                        placeholder = { Text("000000", color = colors.textMuted) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.Rose,
                            unfocusedBorderColor = colors.border,
                            focusedTextColor = colors.textPrimary,
                            unfocusedTextColor = colors.textPrimary
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { viewModel.linkPhoneVerify(codeInput) },
                        enabled = !inProgress && codeInput.length >= 4,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.Rose,
                            disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                        )
                    ) {
                        Text(if (inProgress) "Verifying…" else "Verify",
                            fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                    TextButton(
                        onClick = { codeInput = ""; viewModel.resetLinkPhoneOtp(); viewModel.clearLinkResult() },
                        enabled = !inProgress
                    ) { Text("Change number", fontSize = 14.sp, color = colors.textSecondary) }
                }

                Spacer(Modifier.height(12.dp))
                if (inProgress) {
                    CircularProgressIndicator(color = AppColors.Rose, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.height(12.dp))
                }
                errorMsg?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                }
                if (PHONE_STEP_SKIPPABLE) {
                    TextButton(onClick = onDone) {
                        Text("Skip for now", fontSize = 15.sp, color = colors.textSecondary)
                    }
                }
            }
        }
    }
}
