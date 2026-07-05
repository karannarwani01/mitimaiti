package com.mitimaiti.app.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
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
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.AuthViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SignInMethodsScreen(viewModel: AuthViewModel, onBack: () -> Unit) {
    val colors = LocalAdaptiveColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val inProgress by viewModel.linkInProgress.collectAsState()
    val result by viewModel.linkResult.collectAsState()

    var status by remember { mutableStateOf<APIService.LinkStatus?>(null) }
    var loading by remember { mutableStateOf(true) }
    var showEmailDialog by remember { mutableStateOf(false) }
    var showPhoneDialog by remember { mutableStateOf(false) }
    var emailInput by remember { mutableStateOf("") }
    var phoneInput by remember { mutableStateOf("") }
    var codeInput by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }
    val otpSent by viewModel.linkEmailOtpSent.collectAsState()
    val pendingEmail by viewModel.pendingLinkEmail.collectAsState()
    val phoneOtpSent by viewModel.linkPhoneOtpSent.collectAsState()

    suspend fun refresh() {
        loading = true
        APIService.linkStatus().onSuccess { status = it }
        loading = false
    }
    LaunchedEffect(Unit) { refresh() }
    // Re-load after a successful link and close the dialog.
    LaunchedEffect(result) {
        when (result) {
            "success" -> {
                showEmailDialog = false; showPhoneDialog = false
                emailInput = ""; phoneInput = ""; codeInput = ""
                viewModel.resetLinkEmailOtp(); viewModel.resetLinkPhoneOtp()
                refresh(); viewModel.clearLinkResult()
            }
            "merged" -> {
                // The contact belonged to another (empty) account; this one was
                // absorbed into it. The session is now stale — prompt re-login.
                showEmailDialog = false; showPhoneDialog = false
                emailInput = ""; phoneInput = ""; codeInput = ""
                viewModel.resetLinkEmailOtp(); viewModel.resetLinkPhoneOtp()
                localError = "We found and merged your other account. Please sign in again."
                viewModel.clearLinkResult()
            }
        }
    }
    DisposableEffect(Unit) { onDispose { viewModel.clearLinkResult() } }

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
            } catch (e: NoCredentialException) {
                localError = "No Google account on this device. Add one in Settings."
            } catch (e: GetCredentialException) {
                localError = e.localizedMessage ?: "Google sign-in failed. Please try again."
            }
        }
    }

    val errorMsg = localError ?: result?.takeIf { it != "success" }

    Scaffold(
        containerColor = colors.background,
        topBar = {
            TopAppBar(
                title = { Text("Sign-in methods", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary)
            )
        }
    ) { pad ->
        Column(
            modifier = Modifier.padding(pad).fillMaxSize().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "Add more ways to sign in so you always keep this profile.",
                fontSize = 14.sp, color = colors.textSecondary, modifier = Modifier.padding(vertical = 8.dp)
            )

            if (loading && status == null) {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AppColors.Rose)
                }
            } else {
                MethodRow(
                    icon = Icons.Default.Phone, label = "Phone",
                    value = status?.phone?.let { "•••• " + it.takeLast(4) } ?: "Not linked",
                    linked = status?.phone != null, colors = colors, enabled = !inProgress,
                    onAdd = {
                        localError = null; phoneInput = ""; codeInput = ""
                        viewModel.resetLinkPhoneOtp(); showPhoneDialog = true
                    }
                )
                MethodRow(
                    icon = Icons.Default.Email, label = "Email",
                    value = status?.email ?: "Not linked",
                    linked = status?.email != null, colors = colors, enabled = !inProgress,
                    onAdd = { localError = null; emailInput = ""; showEmailDialog = true }
                )
                MethodRow(
                    icon = Icons.Default.CheckCircle, label = "Google",
                    value = if (status?.google == true) "Linked" else "Not linked",
                    linked = status?.google == true, colors = colors, enabled = !inProgress,
                    onAdd = onGoogle
                )

                if (inProgress) {
                    Spacer(Modifier.height(4.dp))
                    CircularProgressIndicator(color = AppColors.Rose, modifier = Modifier.size(22.dp))
                }
                errorMsg?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
                }
            }
        }
    }

    if (showEmailDialog) {
        val closeDialog = { showEmailDialog = false; codeInput = ""; viewModel.resetLinkEmailOtp() }
        AlertDialog(
            onDismissRequest = { if (!inProgress) closeDialog() },
            title = { Text(if (otpSent) "Enter the code" else "Add your email") },
            text = {
                Column {
                    if (!otpSent) {
                        Text("We'll send a code to verify it, then link it to your account.",
                            fontSize = 13.sp, color = colors.textSecondary)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = emailInput, onValueChange = { emailInput = it.trim() }, singleLine = true,
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
                        Spacer(Modifier.height(8.dp)); Text(it, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                if (!otpSent) {
                    TextButton(onClick = { viewModel.linkEmailStart(emailInput) },
                        enabled = !inProgress && emailInput.isNotBlank()) {
                        Text(if (inProgress) "Sending…" else "Send code", color = AppColors.Rose)
                    }
                } else {
                    TextButton(onClick = { viewModel.linkEmailVerify(codeInput) },
                        enabled = !inProgress && codeInput.length >= 4) {
                        Text(if (inProgress) "Verifying…" else "Verify", color = AppColors.Rose)
                    }
                }
            },
            dismissButton = { TextButton(onClick = { closeDialog() }, enabled = !inProgress) { Text("Cancel") } }
        )
    }

    if (showPhoneDialog) {
        val closePhoneDialog = { showPhoneDialog = false; codeInput = ""; viewModel.resetLinkPhoneOtp() }
        AlertDialog(
            onDismissRequest = { if (!inProgress) closePhoneDialog() },
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
                            singleLine = true, placeholder = { Text("+971501234567") },
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
                        Spacer(Modifier.height(8.dp)); Text(it, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = {
                if (!phoneOtpSent) {
                    TextButton(onClick = { viewModel.linkPhoneStart(phoneInput) },
                        enabled = !inProgress && phoneInput.length >= 8) {
                        Text(if (inProgress) "Sending…" else "Send code", color = AppColors.Rose)
                    }
                } else {
                    TextButton(onClick = { viewModel.linkPhoneVerify(codeInput) },
                        enabled = !inProgress && codeInput.length >= 4) {
                        Text(if (inProgress) "Verifying…" else "Verify", color = AppColors.Rose)
                    }
                }
            },
            dismissButton = { TextButton(onClick = { closePhoneDialog() }, enabled = !inProgress) { Text("Cancel") } }
        )
    }
}

@Composable
private fun MethodRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    linked: Boolean,
    colors: com.mitimaiti.app.ui.theme.AdaptiveColors,
    enabled: Boolean = true,
    onAdd: (() -> Unit)?
) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = colors.surface,
        border = androidx.compose.foundation.BorderStroke(1.dp, colors.borderSubtle),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, null, tint = if (linked) AppColors.Rose else colors.textMuted, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(value, fontSize = 13.sp, color = colors.textMuted)
            }
            if (linked) {
                Icon(Icons.Default.CheckCircle, "Linked", tint = Color(0xFF2FB672), modifier = Modifier.size(20.dp))
            } else if (onAdd != null) {
                TextButton(onClick = onAdd, enabled = enabled) { Text("Add", color = AppColors.Rose, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}
