package com.mitimaiti.app.ui.auth

import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
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
import com.mitimaiti.app.R
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.viewmodels.AuthViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * landing: full-screen brand moment with the auth methods as
 * stacked full-width pills at the bottom — phone number (primary) and Google —
 * plus the legal line. No marketing scroll; signup and sign-in are the same
 * buttons. MitiMaiti branding throughout.
 */
@Composable
fun WelcomeScreen(
    viewModel: AuthViewModel,
    onPhone: () -> Unit,
    onAuthenticated: () -> Unit,
    onGuidelines: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onTerms: () -> Unit = {}
) {
    val colors = com.mitimaiti.app.ui.theme.LocalAdaptiveColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val isAuthenticated by viewModel.isAuthenticated.collectAsState()
    var localError by remember { mutableStateOf<String?>(null) }

    var isVisible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(300); isVisible = true }

    // Google sign-in completes right here on the landing screen.
    LaunchedEffect(isAuthenticated) { if (isAuthenticated) onAuthenticated() }

    val onGoogleSignIn: () -> Unit = {
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
                    viewModel.signInWithGoogle(GoogleIdTokenCredential.createFrom(cred.data).idToken)
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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.backgroundGradient)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.weight(1f))

        // ── Brand moment ──
        androidx.compose.animation.AnimatedVisibility(
            visible = isVisible,
            enter = fadeIn() + slideInVertically { -40 }
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Image(
                    painter = painterResource(id = R.drawable.logo_mark),
                    contentDescription = "MitiMaiti",
                    modifier = Modifier.size(112.dp)
                )
                Spacer(Modifier.height(20.dp))
                Text(
                    "MitiMaiti",
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.Rose
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "Where Sindhi Hearts Connect",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppColors.Gold,
                    textAlign = TextAlign.Center
                )
            }
        }

        Spacer(Modifier.weight(1f))

        // ── Auth methods (stacked pills, standard) ──
        androidx.compose.animation.AnimatedVisibility(
            visible = isVisible,
            enter = fadeIn() + slideInVertically { 60 }
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Button(
                    onClick = onPhone,
                    enabled = !isLoading,
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = RoundedCornerShape(28.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.Rose)
                ) {
                    Icon(Icons.Default.Phone, null, modifier = Modifier.size(20.dp), tint = Color.White)
                    Spacer(Modifier.width(10.dp))
                    Text("Use cell phone number", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
                Spacer(Modifier.height(12.dp))
                SocialSignInButton(
                    label = "Continue with Google",
                    modifier = Modifier.fillMaxWidth(),
                    backgroundColor = colors.surfaceMedium,
                    borderColor = colors.border,
                    textColor = colors.textPrimary,
                    onClick = onGoogleSignIn
                ) {
                    GoogleIcon(modifier = Modifier.size(20.dp))
                }

                if (isLoading) {
                    Spacer(Modifier.height(14.dp))
                    CircularProgressIndicator(color = AppColors.Rose, modifier = Modifier.size(24.dp))
                }
                (localError ?: error)?.let {
                    Spacer(Modifier.height(10.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp, textAlign = TextAlign.Center)
                }

                // ── Legal ──
                Spacer(Modifier.height(18.dp))
                Text(
                    "By signing up, you agree to our Terms. See how we use your data in our Privacy Policy.",
                    fontSize = 11.sp,
                    color = colors.textMuted,
                    textAlign = TextAlign.Center,
                    lineHeight = 15.sp
                )
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = onTerms, contentPadding = PaddingValues(4.dp)) {
                        Text("Terms", fontSize = 12.sp, color = colors.textMuted)
                    }
                    TextButton(onClick = onPrivacy, contentPadding = PaddingValues(4.dp)) {
                        Text("Privacy", fontSize = 12.sp, color = colors.textMuted)
                    }
                    TextButton(onClick = onGuidelines, contentPadding = PaddingValues(4.dp)) {
                        Text("Guidelines", fontSize = 12.sp, color = colors.textMuted)
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}
