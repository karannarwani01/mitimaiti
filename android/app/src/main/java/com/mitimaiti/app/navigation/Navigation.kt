package com.mitimaiti.app.navigation

sealed class Screen(val route: String) {
    object Splash : Screen("splash")
    object Welcome : Screen("welcome")
    object PhoneAuth : Screen("phone_auth")
    object OTPVerification : Screen("otp_verification")
    object EmailAuth : Screen("email_auth")
    object LinkAccount : Screen("link_account")
    object Onboarding : Screen("onboarding")
    object Main : Screen("main")
    object Chat : Screen("chat/{matchId}") {
        fun createRoute(matchId: String) = "chat/$matchId"
    }
    object EditProfile : Screen("edit_profile")
    object Settings : Screen("settings")
    object Guidelines : Screen("guidelines")
    object Privacy : Screen("privacy")
    object Terms : Screen("terms")
}

/** Where the splash routes once the stored session has been resolved. */
enum class SplashDestination { WELCOME, ONBOARDING, MAIN }
