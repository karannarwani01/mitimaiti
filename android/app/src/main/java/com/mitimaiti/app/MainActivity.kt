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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as MitiMaitiApp
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
                val familyViewModel: FamilyViewModel = viewModel()
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
                                onGetStarted = { navController.navigate(Screen.PhoneAuth.route) },
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
                                    val dest = if (authViewModel.hasCompletedOnboarding.value) Screen.Main.route else Screen.Onboarding.route
                                    navController.navigate(dest) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onBack = { navController.popBackStack() }
                            )
                        }
                        composable(Screen.OTPVerification.route) {
                            OTPVerificationScreen(
                                viewModel = authViewModel,
                                onVerified = {
                                    val dest = if (authViewModel.hasCompletedOnboarding.value) Screen.Main.route else Screen.Onboarding.route
                                    navController.navigate(dest) { popUpTo(Screen.Welcome.route) { inclusive = true } }
                                },
                                onBack = { navController.popBackStack() }
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
                            MainTabScreen(
                                feedViewModel = feedViewModel,
                                inboxViewModel = inboxViewModel,
                                profileViewModel = profileViewModel,
                                familyViewModel = familyViewModel,
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
                            val match = inboxViewModel.matches.value.firstOrNull { it.id == matchId }
                            if (match != null) {
                                ChatScreen(viewModel = chatViewModel, match = match, onBack = { navController.popBackStack() })
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
                                }
                            )
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
