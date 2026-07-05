package com.mitimaiti.app.ui.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Phone
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
import androidx.compose.ui.platform.LocalContext
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.mitimaiti.app.BuildConfig
import com.mitimaiti.app.R
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel
import kotlinx.coroutines.launch

/**
 * Shown right after signup. Optional (skippable): secures the OTHER contact
 * method on the account so any of them retrieves this profile on a future
 * login. Phone-first signups are asked for an email (typed or Google — either
 * way the email gets an OTP before it links); email/Google-first signups are
 * asked for a mobile number, verified by SMS OTP.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LinkAccountScreen(viewModel: AuthViewModel, onDone: () -> Unit) {
    val colors = LocalAdaptiveColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val inProgress by viewModel.linkInProgress.collectAsState()
    val result by viewModel.linkResult.collectAsState()
    val emailOtpSent by viewModel.linkEmailOtpSent.collectAsState()
    val pendingEmail by viewModel.pendingLinkEmail.collectAsState()
    val phoneOtpSent by viewModel.linkPhoneOtpSent.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()

    // Which side of the account still needs securing: email-first signups
    // (email present, no phone) are asked for a phone; everyone else for email.
    val securePhone = currentUser?.phone.isNullOrBlank() && !currentUser?.email.isNullOrBlank()

    var showEmailDialog by remember { mutableStateOf(false) }
    var showPhoneDialog by remember { mutableStateOf(false) }
    var emailInput by remember { mutableStateOf("") }
    var phoneInput by remember { mutableStateOf("") }
    var codeInput by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }

    val linked = result == "success" || result == "merged"
    val errorMsg = localError ?: result?.takeIf { it != "success" && it != "merged" }

    DisposableEffect(Unit) {
        onDispose {
            viewModel.clearLinkResult()
            viewModel.resetLinkEmailOtp()
            viewModel.resetLinkPhoneOtp()
        }
    }
    LaunchedEffect(result) {
        if (linked) { showEmailDialog = false; showPhoneDialog = false }
    }
    // Google link sends the code server-side → open the dialog at the code step.
    LaunchedEffect(emailOtpSent) {
        if (emailOtpSent && !showEmailDialog) { codeInput = ""; showEmailDialog = true }
    }

    // Google credential flow (same pattern as PhoneAuthScreen), linking instead of signing in.
    val onGoogle: () -> Unit = {
        localError = null
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank()) {
            localError = "Google sign-in isn't configured on this build."
        } else scope.launch {
            val cm = CredentialManager.create(context)
            val option = GetGoogleIdOption.Builder()
                .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
                .setFilterByAuthorizedAccounts(false)
                .setAutoSelectEnabled(false)
                .build()
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            try {
                val res = cm.getCredential(context, request)
                val cred = res.credential
                if (cred is CustomCredential && cred.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                    viewModel.linkGoogle(GoogleIdTokenCredential.createFrom(cred.data).idToken)
                } else localError = "Unexpected credential type from Google."
            } catch (e: GetCredentialCancellationException) {
                // user dismissed — silent
            } catch (e: NoCredentialException) {
                localError = "No Google account on this device. Add one in Settings."
            } catch (e: GetCredentialException) {
                localError = e.localizedMessage ?: "Google sign-in failed. Please try again."
            }
        }
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
                "Secure your account",
                fontSize = 26.sp, fontWeight = FontWeight.Bold,
                color = colors.textPrimary, textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(10.dp))
            Text(
                if (securePhone)
                    "Add your mobile number as a backup way to sign in. We'll text you a code to verify it."
                else
                    "Add a backup way to sign in, so you keep your profile even if you change your phone number.",
                fontSize = 15.sp, color = colors.textSecondary,
                textAlign = TextAlign.Center, lineHeight = 22.sp
            )
            Spacer(Modifier.height(32.dp))

            if (linked) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, tint = Color(0xFF2FB672), modifier = Modifier.size(26.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(
                        if (result == "merged") "We found your existing profile and merged your sign-ins."
                        else "You're all set — backup sign-in added.",
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
                if (securePhone) {
                    // Add phone (SMS OTP)
                    Button(
                        onClick = {
                            localError = null; codeInput = ""
                            viewModel.resetLinkPhoneOtp(); showPhoneDialog = true
                        },
                        enabled = !inProgress,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
                    ) {
                        Icon(Icons.Default.Phone, null, modifier = Modifier.size(20.dp), tint = Color.White)
                        Spacer(Modifier.width(10.dp))
                        Text("Add a mobile number", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                } else {
                    // Add email (OTP-verified)
                    Button(
                        onClick = {
                            localError = null; codeInput = ""
                            viewModel.resetLinkEmailOtp(); showEmailDialog = true
                        },
                        enabled = !inProgress,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
                    ) {
                        Icon(Icons.Default.MailOutline, null, modifier = Modifier.size(20.dp), tint = Color.White)
                        Spacer(Modifier.width(10.dp))
                        Text("Add an email address", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                    Spacer(Modifier.height(12.dp))
                    // Continue with Google — still OTP-verifies the email
                    OutlinedButton(
                        onClick = onGoogle,
                        enabled = !inProgress,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(AppTheme.radiusLg),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, colors.border)
                    ) {
                        Text("Continue with Google", fontSize = 16.sp, color = colors.textPrimary)
                    }
                }
                Spacer(Modifier.height(20.dp))
                if (inProgress) {
                    CircularProgressIndicator(color = AppColors.Rose, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.height(12.dp))
                }
                errorMsg?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                }
                TextButton(onClick = onDone) {
                    Text("Skip for now", fontSize = 15.sp, color = colors.textSecondary)
                }
            }
        }
    }

    if (showEmailDialog) {
        val closeDialog = {
            showEmailDialog = false; codeInput = ""; viewModel.resetLinkEmailOtp(); viewModel.clearLinkResult()
        }
        AlertDialog(
            onDismissRequest = { if (!inProgress) closeDialog() },
            title = { Text(if (emailOtpSent) "Enter the code" else "Add your email") },
            text = {
                Column {
                    if (!emailOtpSent) {
                        Text("We'll send a code to verify it, then link it to your account.",
                            fontSize = 13.sp, color = colors.textSecondary)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = emailInput,
                            onValueChange = { emailInput = it.trim() },
                            singleLine = true,
                            placeholder = { Text("you@example.com") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        Text("Enter the 6-digit code we sent to ${pendingEmail.ifBlank { emailInput }}.",
                            fontSize = 13.sp, color = colors.textSecondary)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = codeInput,
                            onValueChange = { codeInput = it.filter { c -> c.isDigit() }.take(6) },
                            singleLine = true, placeholder = { Text("000000") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    (result?.takeIf { it != "success" && it != "merged" })?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                if (!emailOtpSent) {
                    TextButton(
                        onClick = { viewModel.linkEmailStart(emailInput) },
                        enabled = !inProgress && emailInput.isNotBlank()
                    ) { Text(if (inProgress) "Sending…" else "Send code", color = AppColors.Rose) }
                } else {
                    TextButton(
                        onClick = { viewModel.linkEmailVerify(codeInput) },
                        enabled = !inProgress && codeInput.length >= 4
                    ) { Text(if (inProgress) "Verifying…" else "Verify", color = AppColors.Rose) }
                }
            },
            dismissButton = {
                TextButton(onClick = { closeDialog() }, enabled = !inProgress) { Text("Cancel") }
            }
        )
    }

    if (showPhoneDialog) {
        val closeDialog = {
            showPhoneDialog = false; codeInput = ""; viewModel.resetLinkPhoneOtp(); viewModel.clearLinkResult()
        }
        AlertDialog(
            onDismissRequest = { if (!inProgress) closeDialog() },
            title = { Text(if (phoneOtpSent) "Enter the code" else "Add your mobile number") },
            text = {
                Column {
                    if (!phoneOtpSent) {
                        Text("Include the country code. We'll text a code to verify it.",
                            fontSize = 13.sp, color = colors.textSecondary)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = phoneInput,
                            onValueChange = { phoneInput = it.filter { c -> c.isDigit() || c == '+' }.take(16) },
                            singleLine = true,
                            placeholder = { Text("+971501234567") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        Text("Enter the 6-digit code we texted to $phoneInput.",
                            fontSize = 13.sp, color = colors.textSecondary)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = codeInput,
                            onValueChange = { codeInput = it.filter { c -> c.isDigit() }.take(6) },
                            singleLine = true, placeholder = { Text("000000") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    (result?.takeIf { it != "success" && it != "merged" })?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                if (!phoneOtpSent) {
                    TextButton(
                        onClick = { viewModel.linkPhoneStart(phoneInput) },
                        enabled = !inProgress && phoneInput.length >= 8
                    ) { Text(if (inProgress) "Sending…" else "Send code", color = AppColors.Rose) }
                } else {
                    TextButton(
                        onClick = { viewModel.linkPhoneVerify(codeInput) },
                        enabled = !inProgress && codeInput.length >= 4
                    ) { Text(if (inProgress) "Verifying…" else "Verify", color = AppColors.Rose) }
                }
            },
            dismissButton = {
                TextButton(onClick = { closeDialog() }, enabled = !inProgress) { Text("Cancel") }
            }
        )
    }
}
