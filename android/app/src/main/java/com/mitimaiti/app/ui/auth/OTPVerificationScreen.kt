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
import com.mitimaiti.app.BuildConfig
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel

@Composable
fun OTPVerificationScreen(viewModel: AuthViewModel, onVerified: () -> Unit, onBack: () -> Unit) {
    val colors = LocalAdaptiveColors.current
    val otpCode by viewModel.otpCode.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val isAuthenticated by viewModel.isAuthenticated.collectAsState()
    val phone by viewModel.phone.collectAsState()
    val resendCooldown by viewModel.resendCooldown.collectAsState()
    LaunchedEffect(isAuthenticated) { if (isAuthenticated) onVerified() }
    Box(modifier = Modifier.fillMaxSize().background(colors.backgroundGradient)) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp)) {
            IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary) }
            Spacer(modifier = Modifier.height(32.dp))
            Text("Enter the code", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
            Spacer(modifier = Modifier.height(12.dp))
            Text("We sent a 6-digit code to $phone", fontSize = 16.sp, color = colors.textSecondary)
            Spacer(modifier = Modifier.height(40.dp))
            OutlinedTextField(value = otpCode, onValueChange = { viewModel.updateOtpCode(it) }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("000000", color = colors.textMuted, fontSize = 24.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(), letterSpacing = 12.sp) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), shape = RoundedCornerShape(AppTheme.radiusMd), textStyle = LocalTextStyle.current.copy(fontSize = 24.sp, textAlign = TextAlign.Center, letterSpacing = 12.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary), colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = AppColors.Rose, unfocusedBorderColor = colors.border), singleLine = true)
            error?.let { Spacer(modifier = Modifier.height(8.dp)); Text(it, color = AppColors.Error, fontSize = 14.sp) }
            Spacer(modifier = Modifier.height(24.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                if (resendCooldown > 0) Text("Resend code in ${resendCooldown}s", color = colors.textMuted, fontSize = 15.sp)
                else TextButton(onClick = { viewModel.sendOTP() }) { Text("Resend Code", color = AppColors.Rose, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
            }
            Spacer(modifier = Modifier.weight(1f))
            Button(onClick = { viewModel.verifyOTP() }, modifier = Modifier.fillMaxWidth().height(56.dp), enabled = otpCode.length == 6 && !isLoading, shape = RoundedCornerShape(AppTheme.radiusLg), colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose, disabledContainerColor = AppColors.Rose.copy(alpha = 0.4f))) {
                if (isLoading) CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp) else Text("Verify", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
            if (BuildConfig.DEBUG) {
                Spacer(modifier = Modifier.height(16.dp))
                Text("For testing, use code: 123456", fontSize = 13.sp, color = colors.textMuted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}
