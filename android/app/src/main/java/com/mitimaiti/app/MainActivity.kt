@file:Suppress("DEPRECATION")
package com.mitimaiti.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.mitimaiti.app.models.AppThemeMode
import com.mitimaiti.app.navigation.Screen
import com.mitimaiti.app.navigation.SplashDestination
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.ui.auth.EmailAuthScreen
import com.mitimaiti.app.ui.auth.LinkAccountScreen
import com.mitimaiti.app.ui.auth.OTPVerificationScreen
import com.mitimaiti.app.ui.auth.PhoneAuthScreen
import com.mitimaiti.app.ui.auth.SplashScreen
import com.mitimaiti.app.ui.auth.WelcomeScreen
import com.mitimaiti.app.ui.main.*
import com.mitimaiti.app.ui.onboarding.OnboardingScreen
import com.mitimaiti.app.ui.pages.GuidelinesScreen
import com.mitimaiti.app.ui.pages.PrivacyScreen
import com.mitimaiti.app.ui.pages.TermsScreen
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.ui.theme.MitiMaitiTheme
import com.mitimaiti.app.viewmodels.*

class MainActivity : ComponentActivity() {

    companion object {
        /** matchId from a tapped push notification, consumed by Screen.Main. */
        val pendingChatMatchId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    }

    // ── Verification selfie camera, registered at the ACTIVITY level ──
    // The camera can push the app out of memory (esp. on a Fold); the OS then
    // kills the process while the camera is foreground. Compose-scoped
    // `rememberLauncherForActivityResult` inside the AnimatedContent-wrapped
    // ProfileScreen crashed on restore with a ClassCastException in
    // ActivityResultRegistry. Activity-level launchers register with stable
    // keys during construction, before state restore, so they survive it.
    private var selfieResult: ((Boolean) -> Unit)? = null
    private val selfieCameraLauncher =
        registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.TakePicture()) { success ->
            val cb = selfieResult; selfieResult = null; cb?.invoke(success)
        }

    private var cameraPermResult: ((Boolean) -> Unit)? = null
    private val cameraPermissionLauncher =
        registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
            val cb = cameraPermResult; cameraPermResult = null; cb?.invoke(granted)
        }

    /** Take a photo into [uri]; [onResult] gets true on success. If the process
     *  was killed while the camera was open, the callback is simply lost on
     *  return (user retries) — but the app no longer crashes. */
    fun launchSelfieCamera(uri: android.net.Uri, onResult: (Boolean) -> Unit) {
        selfieResult = onResult
        selfieCameraLauncher.launch(uri)
    }

    fun requestCameraPermission(onResult: (Boolean) -> Unit) {
        cameraPermResult = onResult
        cameraPermissionLauncher.launch(android.Manifest.permission.CAMERA)
    }

    private fun consumeNotificationIntent(intent: android.content.Intent?) {
        intent?.getStringExtra(
            com.mitimaiti.app.services.MitiMaitiMessagingService.EXTRA_MATCH_ID
        )?.let { pendingChatMatchId.value = it }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        consumeNotificationIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as MitiMaitiApp
        consumeNotificationIntent(intent)

        // Notification channels the backend targets (safe without Firebase)
        com.mitimaiti.app.services.MitiMaitiMessagingService.createChannels(this)

        // Android 13+ runtime permission for notifications
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            androidx.core.content.ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.POST_NOTIFICATIONS
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 100)
        }

        // Sync the FCM token with the backend. Guarded: the app builds and
        // runs without google-services.json, in which case Firebase never
        // initialises and this quietly no-ops.
        try {
            com.google.firebase.messaging.FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    com.mitimaiti.app.services.FcmTokenRegistrar.register(token)
                }
        } catch (e: Exception) {
            android.util.Log.i("MainActivity", "FCM unavailable (no google-services.json)")
        }
        setContent {
            val themeMode by app.themeManager.themeMode.collectAsState()
            val isDark = when (themeMode) {
                AppThemeMode.LIGHT -> false
                AppThemeMode.DARK -> true
                AppThemeMode.SYSTEM -> isSystemInDarkTheme()
            }
            MitiMaitiTheme(darkTheme = isDark) {
                val colors = LocalAdaptiveColors.current
                val navController = rememberNavController()
                val authViewModel: AuthViewModel = viewModel()
                val feedViewModel: FeedViewModel = viewModel()
                val inboxViewModel: InboxViewModel = viewModel()
                val profileViewModel: ProfileViewModel = viewModel()
                val settingsViewModel: SettingsViewModel = viewModel()

                Surface(modifier = Modifier.fillMaxSize(), color = colors.background) {
                    NavHost(navController = navController, startDestination = Screen.Splash.route) {
                        composable(Screen.Splash.route) {
                            SplashScreen(
                                resolveDestination = {
                                    // No stored session → straight to Welcome.
                                    val token = app.tokenManager.getAccessToken()
                                    if (token.isNullOrBlank()) {
                                        SplashDestination.WELCOME
                                    } else {
                                        // Validate the session by hitting /me. If it succeeds we
                                        // know the JWT is still valid and can route by profile
                                        // completeness. If it fails (401, network blip, etc.) we
                                        // fall back to Welcome — the OTP/Google paths will mint a
                                        // fresh session.
                                        APIService.fetchProfile().fold(
                                            onSuccess = { user ->
                                                val hasOnboarded = !user.needsOnboarding
                                                authViewModel.bootstrapAuthenticated(user, hasOnboarded)
                                                if (hasOnboarded) SplashDestination.MAIN
                                                else SplashDestination.ONBOARDING
                                            },
                                            onFailure = {
                                                app.tokenManager.clearTokens()
                                                APIService.clearTokens()
                                                SplashDestination.WELCOME
                                            }
                                        )
                                    }
                                },
                                onFinished = { destination ->
                                    val route = when (destination) {
                                        SplashDestination.WELCOME -> Screen.Welcome.route
                                        SplashDestination.ONBOARDING -> Screen.Onboarding.route
                                        SplashDestination.MAIN -> Screen.Main.route
                                    }
                                    navController.navigate(route) {
                                        popUpTo(Screen.Splash.route) { inclusive = true }
                                    }
                                }
                            )
                        }
                        composable(Screen.Welcome.route) {
                            WelcomeScreen(
                                viewModel = authViewModel,
                                onPhone = { navController.navigate(Screen.PhoneAuth.route) },
                                onAuthenticated = {
                                    // Google sign-in from the landing screen:
                                    // same routing as the OTP screen.
                                    val dest = when {
                                        authViewModel.hasCompletedOnboarding.value -> Screen.Main.route
                                        authViewModel.currentUser.value?.phone.isNullOrBlank() -> Screen.LinkAccount.route
                                        else -> Screen.Onboarding.route
                                    }
                                    navController.navigate(dest) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onGuidelines = { navController.navigate(Screen.Guidelines.route) },
                                onPrivacy = { navController.navigate(Screen.Privacy.route) },
                                onTerms = { navController.navigate(Screen.Terms.route) }
                            )
                        }
                        composable(Screen.PhoneAuth.route) {
                            PhoneAuthScreen(
                                viewModel = authViewModel,
                                onOTPSent = { navController.navigate(Screen.OTPVerification.route) },
                                onEmailSelected = { navController.navigate(Screen.EmailAuth.route) },
                                onBack = { navController.popBackStack() }
                            )
                        }
                        composable(Screen.EmailAuth.route) {
                            EmailAuthScreen(
                                viewModel = authViewModel,
                                onVerified = {
                                    // Email-first new users get the "secure your
                                    // mobile number" step before onboarding.
                                    val dest = if (authViewModel.hasCompletedOnboarding.value) Screen.Main.route else Screen.LinkAccount.route
                                    navController.navigate(dest) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onBack = { navController.popBackStack() }
                            )
                        }
                        composable(Screen.OTPVerification.route) {
                            OTPVerificationScreen(
                                viewModel = authViewModel,
                                onVerified = {
                                    // Routing: returning users go straight in;
                                    // new users who already verified a phone (phone-first
                                    // signup) go to onboarding; new users WITHOUT a phone
                                    // (Google-first lands here too) get the "Can we get
                                    // your number?" step first.
                                    val dest = when {
                                        authViewModel.hasCompletedOnboarding.value -> Screen.Main.route
                                        authViewModel.currentUser.value?.phone.isNullOrBlank() -> Screen.LinkAccount.route
                                        else -> Screen.Onboarding.route
                                    }
                                    navController.navigate(dest) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onBack = { navController.popBackStack() }
                            )
                        }
                        composable(Screen.LinkAccount.route) {
                            LinkAccountScreen(
                                viewModel = authViewModel,
                                onDone = {
                                    navController.navigate(Screen.Onboarding.route) {
                                        popUpTo(Screen.LinkAccount.route) { inclusive = true }
                                    }
                                }
                            )
                        }
                        composable(Screen.Onboarding.route) {
                            OnboardingScreen(
                                onComplete = {
                                    authViewModel.completeOnboarding()
                                    navController.navigate(Screen.Main.route) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onNavigateToEditProfile = {
                                    navController.navigate(Screen.EditProfile.route)
                                }
                            )
                        }
                        composable(Screen.Main.route) {
                            // Deep link from a tapped push notification
                            val pendingChat by pendingChatMatchId.collectAsState()
                            androidx.compose.runtime.LaunchedEffect(pendingChat) {
                                pendingChat?.let { matchId ->
                                    pendingChatMatchId.value = null
                                    inboxViewModel.loadInbox()
                                    navController.navigate(Screen.Chat.createRoute(matchId))
                                }
                            }
                            MainTabScreen(
                                feedViewModel = feedViewModel,
                                inboxViewModel = inboxViewModel,
                                profileViewModel = profileViewModel,
                                onNavigateToChat = { matchId -> navController.navigate(Screen.Chat.createRoute(matchId)) },
                                onNavigateToEditProfile = { navController.navigate(Screen.EditProfile.route) },
                                onNavigateToSettings = { navController.navigate(Screen.Settings.route) },
                                onLogout = {
                                    authViewModel.logout()
                                    navController.navigate(Screen.Welcome.route) { popUpTo(0) { inclusive = true } }
                                }
                            )
                        }
                        composable(Screen.Chat.route) { backStackEntry ->
                            val matchId = backStackEntry.arguments?.getString("matchId") ?: ""
                            val chatViewModel: ChatViewModel = viewModel()
                            chatViewModel.onMatchActivated = { id, msg -> inboxViewModel.activateMatch(id, msg) }
                            // Reactive: the match may arrive a moment later
                            // (notification deep link, fresh like-back)
                            val matches by inboxViewModel.matches.collectAsState()
                            val match = matches.firstOrNull { it.id == matchId }
                            if (match != null) {
                                ChatScreen(viewModel = chatViewModel, match = match, onBack = { navController.popBackStack() })
                            } else {
                                androidx.compose.runtime.LaunchedEffect(matchId) { inboxViewModel.loadInbox() }
                                androidx.compose.foundation.layout.Box(
                                    modifier = Modifier.fillMaxSize(),
                                    contentAlignment = androidx.compose.ui.Alignment.Center
                                ) {
                                    androidx.compose.material3.CircularProgressIndicator()
                                }
                            }
                        }
                        composable(Screen.EditProfile.route) {
                            EditProfileScreen(viewModel = profileViewModel, onBack = { navController.popBackStack() })
                        }
                        composable(Screen.Settings.route) {
                            SettingsScreen(
                                viewModel = settingsViewModel,
                                themeManager = app.themeManager,
                                onBack = { navController.popBackStack() },
                                onLogout = {
                                    authViewModel.logout()
                                    navController.navigate(Screen.Welcome.route) { popUpTo(0) { inclusive = true } }
                                },
                                onOpenTerms = { navController.navigate(Screen.Terms.route) },
                                onOpenPrivacy = { navController.navigate(Screen.Privacy.route) },
                                onOpenGuidelines = { navController.navigate(Screen.Guidelines.route) },
                                onOpenSignInMethods = { navController.navigate(Screen.SignInMethods.route) }
                            )
                        }
                        composable(Screen.SignInMethods.route) {
                            SignInMethodsScreen(viewModel = authViewModel, onBack = { navController.popBackStack() })
                        }
                        composable(Screen.Guidelines.route) {
                            GuidelinesScreen(onBack = { navController.popBackStack() })
                        }
                        composable(Screen.Privacy.route) {
                            PrivacyScreen(onBack = { navController.popBackStack() })
                        }
                        composable(Screen.Terms.route) {
                            TermsScreen(onBack = { navController.popBackStack() })
                        }
                    }
                }
            }
        }
    }
}
