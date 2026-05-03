@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel

@Composable
fun EmailAuthScreen(
    viewModel: AuthViewModel,
    onVerified: () -> Unit,
    onBack: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val email by viewModel.email.collectAsState()
    val otpCode by viewModel.otpCode.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val otpSent by viewModel.otpSent.collectAsState()
    val isAuthenticated by viewModel.isAuthenticated.collectAsState()
    val resendCooldown by viewModel.resendCooldown.collectAsState()

    LaunchedEffect(isAuthenticated) { if (isAuthenticated) onVerified() }

    // Reset OTP state when leaving the screen so a fresh visit starts at email entry.
    DisposableEffect(Unit) {
        onDispose { viewModel.resetOtpState() }
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.backgroundGradient)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp)
        ) {
            IconButton(onClick = {
                if (otpSent) viewModel.resetOtpState() else onBack()
            }) {
                Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
            }
            Spacer(modifier = Modifier.height(32.dp))

            if (!otpSent) {
                // ── Phase 1: email entry ──
                Text(
                    "What's your email?",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "We'll send you a 6-digit code to sign in.",
                    fontSize = 16.sp,
                    color = colors.textSecondary
                )
                Spacer(modifier = Modifier.height(40.dp))

                OutlinedTextField(
                    value = email,
                    onValueChange = { viewModel.updateEmail(it) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("you@example.com", color = colors.textMuted, fontSize = 17.sp) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    shape = RoundedCornerShape(AppTheme.radiusMd),
                    textStyle = LocalTextStyle.current.copy(fontSize = 17.sp, color = colors.textPrimary),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.Rose,
                        unfocusedBorderColor = colors.border
                    ),
                    singleLine = true
                )
                error?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(it, color = AppColors.Error, fontSize = 14.sp)
                }

                Spacer(modifier = Modifier.weight(1f))

                Button(
                    onClick = { viewModel.sendEmailOTP() },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    enabled = email.isNotBlank() && !isLoading,
                    shape = RoundedCornerShape(AppTheme.radiusLg),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.Rose,
                        disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                    )
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Text("Continue", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                }
                Spacer(modifier = Modifier.height(32.dp))
            } else {
                // ── Phase 2: OTP entry ──
                Text(
                    "Enter the code",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "We sent a 6-digit code to $email",
                    fontSize = 16.sp,
                    color = colors.textSecondary
                )
                Spacer(modifier = Modifier.height(40.dp))

                OutlinedTextField(
                    value = otpCode,
                    onValueChange = { viewModel.updateOtpCode(it) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text(
                            "000000",
                            color = colors.textMuted,
                            fontSize = 24.sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                            letterSpacing = 12.sp
                        )
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    shape = RoundedCornerShape(AppTheme.radiusMd),
                    textStyle = LocalTextStyle.current.copy(
                        fontSize = 24.sp,
                        textAlign = TextAlign.Center,
                        letterSpacing = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.textPrimary
                    ),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.Rose,
                        unfocusedBorderColor = colors.border
                    ),
                    singleLine = true
                )
                error?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(it, color = AppColors.Error, fontSize = 14.sp)
                }
                Spacer(modifier = Modifier.height(24.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    if (resendCooldown > 0) {
                        Text("Resend code in ${resendCooldown}s", color = colors.textMuted, fontSize = 15.sp)
                    } else {
                        TextButton(onClick = { viewModel.sendEmailOTP() }) {
                            Text("Resend Code", color = AppColors.Rose, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                Spacer(modifier = Modifier.weight(1f))

                Button(
                    onClick = { viewModel.verifyEmailOTP() },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    enabled = otpCode.length == 6 && !isLoading,
                    shape = RoundedCornerShape(AppTheme.radiusLg),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.Rose,
                        disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f)
                    )
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Text("Verify", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                }
                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}
