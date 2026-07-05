package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.User
import com.mitimaiti.app.services.APIError
import com.mitimaiti.app.services.APIService
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthViewModel : ViewModel() {
    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()
    private val _hasCompletedOnboarding = MutableStateFlow(false)
    val hasCompletedOnboarding: StateFlow<Boolean> = _hasCompletedOnboarding.asStateFlow()
    private val _phone = MutableStateFlow("")
    val phone: StateFlow<String> = _phone.asStateFlow()
    private val _email = MutableStateFlow("")
    val email: StateFlow<String> = _email.asStateFlow()
    private val _otpCode = MutableStateFlow("")
    val otpCode: StateFlow<String> = _otpCode.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _otpSent = MutableStateFlow(false)
    val otpSent: StateFlow<Boolean> = _otpSent.asStateFlow()
    private val _resendCooldown = MutableStateFlow(0)
    val resendCooldown: StateFlow<Int> = _resendCooldown.asStateFlow()
    private val _resendCount = MutableStateFlow(0)
    val resendCount: StateFlow<Int> = _resendCount.asStateFlow()
    private val _currentUser = MutableStateFlow<User?>(null)
    val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    // Account linking (post-OTP "add a backup sign-in" screen + Settings)
    private val _linkInProgress = MutableStateFlow(false)
    val linkInProgress: StateFlow<Boolean> = _linkInProgress.asStateFlow()
    /** null = idle, "success" = linked, otherwise a user-facing error message. */
    private val _linkResult = MutableStateFlow<String?>(null)
    val linkResult: StateFlow<String?> = _linkResult.asStateFlow()
    /** true once the email OTP has been sent → show the code step. */
    private val _linkEmailOtpSent = MutableStateFlow(false)
    val linkEmailOtpSent: StateFlow<Boolean> = _linkEmailOtpSent.asStateFlow()
    private val _pendingLinkEmail = MutableStateFlow("")
    val pendingLinkEmail: StateFlow<String> = _pendingLinkEmail.asStateFlow()

    fun updatePhone(value: String) { _phone.value = value }
    fun updateEmail(value: String) { _email.value = value.trim() }
    fun updateOtpCode(value: String) { _otpCode.value = value.take(6) }
    fun clearError() { _error.value = null }
    fun resetOtpState() { _otpSent.value = false; _otpCode.value = ""; _error.value = null }
    fun clearLinkResult() { _linkResult.value = null }

    fun linkEmail(rawEmail: String) {
        val email = rawEmail.trim()
        if (!isValidEmail(email)) { _linkResult.value = "Please enter a valid email address"; return }
        viewModelScope.launch {
            _linkInProgress.value = true
            APIService.linkEmail(email)
                .onSuccess { _linkResult.value = "success" }
                .onFailure {
                    _linkResult.value = when (it) {
                        is APIError.LinkConflict -> "That email is already linked to another account"
                        else -> "Couldn't link that email. Please try again."
                    }
                }
            _linkInProgress.value = false
        }
    }

    /** Step 1: send an OTP to the email the user wants to add. */
    fun linkEmailStart(rawEmail: String) {
        val email = rawEmail.trim()
        if (!isValidEmail(email)) { _linkResult.value = "Please enter a valid email address"; return }
        viewModelScope.launch {
            _linkInProgress.value = true
            APIService.linkEmailStart(email)
                .onSuccess { _pendingLinkEmail.value = email; _linkEmailOtpSent.value = true }
                .onFailure { _linkResult.value = "Couldn't send the code. Please try again." }
            _linkInProgress.value = false
        }
    }

    /** Step 2: verify the emailed code → attaches the email (or auto-merges). */
    fun linkEmailVerify(code: String) {
        viewModelScope.launch {
            _linkInProgress.value = true
            APIService.linkEmailVerify(_pendingLinkEmail.value, code)
                .onSuccess { merged -> _linkResult.value = if (merged) "merged" else "success" }
                .onFailure {
                    _linkResult.value = when (it) {
                        is APIError.InvalidOtp -> "That code is invalid or expired"
                        is APIError.LinkConflict -> "That email belongs to another active account"
                        else -> "Couldn't verify the code. Please try again."
                    }
                }
            _linkInProgress.value = false
        }
    }

    fun resetLinkEmailOtp() { _linkEmailOtpSent.value = false; _pendingLinkEmail.value = "" }

    fun linkGoogle(idToken: String) {
        // Prefill the onboarding name from the Google ID token when we don't
        // have one yet (phone-OTP signup linking Google before onboarding).
        // Never overwrites a name the user already has.
        if (com.mitimaiti.app.services.UserPrefs.firstName.value.isBlank()) {
            nameFromIdToken(idToken)?.takeIf { it.isNotBlank() }?.let {
                com.mitimaiti.app.services.UserPrefs.setFirstName(it)
            }
        }
        viewModelScope.launch {
            _linkInProgress.value = true
            // Google OAuth is trusted directly — no email OTP.
            APIService.linkGoogle(idToken)
                .onSuccess { merged -> _linkResult.value = if (merged) "merged" else "success" }
                .onFailure {
                    _linkResult.value = when (it) {
                        is APIError.LinkConflict -> "That Google account is already linked elsewhere"
                        else -> "Couldn't link Google. Please try again."
                    }
                }
            _linkInProgress.value = false
        }
    }

    /** true once the phone OTP has been sent → show the code step. */
    private val _linkPhoneOtpSent = MutableStateFlow(false)
    val linkPhoneOtpSent: StateFlow<Boolean> = _linkPhoneOtpSent.asStateFlow()
    private val _pendingLinkPhone = MutableStateFlow("")
    val pendingLinkPhone: StateFlow<String> = _pendingLinkPhone.asStateFlow()

    /** Step 1: send an SMS OTP to the phone the user wants to add. */
    fun linkPhoneStart(rawPhone: String) {
        val phone = rawPhone.filter { !it.isWhitespace() }
        if (!phone.matches(Regex("^\\+[1-9]\\d{6,14}$"))) {
            _linkResult.value = "Enter the number with country code, e.g. +971501234567"
            return
        }
        viewModelScope.launch {
            _linkInProgress.value = true
            APIService.linkPhoneStart(phone)
                .onSuccess { _pendingLinkPhone.value = phone; _linkPhoneOtpSent.value = true }
                .onFailure { _linkResult.value = "Couldn't send the code. Please try again." }
            _linkInProgress.value = false
        }
    }

    /** Step 2: verify the SMS code → attaches the phone (or auto-merges). */
    fun linkPhoneVerify(code: String) {
        viewModelScope.launch {
            _linkInProgress.value = true
            APIService.linkPhoneVerify(_pendingLinkPhone.value, code)
                .onSuccess { merged -> _linkResult.value = if (merged) "merged" else "success" }
                .onFailure {
                    _linkResult.value = when (it) {
                        is APIError.InvalidOtp -> "That code is invalid or expired"
                        is APIError.LinkConflict -> "That number belongs to another active account"
                        else -> "Couldn't verify the code. Please try again."
                    }
                }
            _linkInProgress.value = false
        }
    }

    fun resetLinkPhoneOtp() { _linkPhoneOtpSent.value = false; _pendingLinkPhone.value = "" }

    fun sendOTP() {
        if (_phone.value.length < 10) { _error.value = "Please enter a valid phone number"; return }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.sendOTP(_phone.value).onSuccess { _otpSent.value = true; _resendCount.value++; startResendTimer() }.onFailure {
                _error.value = (it as? APIError.MessageRejected)?.reason ?: "Failed to send OTP. Please try again."
            }
            _isLoading.value = false
        }
    }

    fun verifyOTP() {
        if (_otpCode.value.length != 6) { _error.value = "Please enter a 6-digit code"; return }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.verifyOTP(_phone.value, _otpCode.value).onSuccess { (user, isNewUser) ->
                _currentUser.value = user
                _isAuthenticated.value = true
                // Route on the server's authoritative needs_onboarding flag
                // (mirrors iOS). isNewUser guards the case where the flag is
                // absent for a brand-new account.
                _hasCompletedOnboarding.value = !isNewUser && !user.needsOnboarding
            }.onFailure { _error.value = "Invalid OTP. Please try again." }
            _isLoading.value = false
        }
    }

    fun sendEmailOTP() {
        if (!isValidEmail(_email.value)) { _error.value = "Please enter a valid email address"; return }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.sendEmailOTP(_email.value).onSuccess { _otpSent.value = true; _resendCount.value++; startResendTimer() }
                .onFailure { _error.value = "Failed to send code. Please try again." }
            _isLoading.value = false
        }
    }

    fun verifyEmailOTP() {
        if (_otpCode.value.length != 6) { _error.value = "Please enter a 6-digit code"; return }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.verifyEmailOTP(_email.value, _otpCode.value).onSuccess { (user, isNewUser) ->
                _currentUser.value = user
                _isAuthenticated.value = true
                // Route on the server's authoritative needs_onboarding flag
                // (mirrors iOS). isNewUser guards the case where the flag is
                // absent for a brand-new account.
                _hasCompletedOnboarding.value = !isNewUser && !user.needsOnboarding
            }.onFailure { _error.value = "Invalid code. Please try again." }
            _isLoading.value = false
        }
    }

    fun signInWithGoogle(idToken: String) {
        // Prefill the onboarding name field locally from the ID token JWT
        // before we even talk to the backend — works even when the response
        // doesn't echo a name.
        nameFromIdToken(idToken)?.takeIf { it.isNotBlank() }?.let {
            com.mitimaiti.app.services.UserPrefs.setFirstName(it)
        }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.verifyGoogleIdToken(idToken).onSuccess { (user, isNewUser) ->
                _currentUser.value = user
                _isAuthenticated.value = true
                // Route on the server's authoritative needs_onboarding flag
                // (mirrors iOS). isNewUser guards the case where the flag is
                // absent for a brand-new account.
                _hasCompletedOnboarding.value = !isNewUser && !user.needsOnboarding
            }.onFailure { _error.value = "Google sign-in failed. Please try again." }
            _isLoading.value = false
        }
    }

    /**
     * Decode the `name` (or `given_name`) claim out of a Google ID token JWT.
     * Signature is not verified — only used for UI prefill, never for auth.
     */
    private fun nameFromIdToken(idToken: String): String? {
        return try {
            val parts = idToken.split('.')
            if (parts.size < 2) return null
            val payload = android.util.Base64.decode(
                parts[1],
                android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
            )
            val json = org.json.JSONObject(String(payload, Charsets.UTF_8))
            (json.optString("name").takeIf { it.isNotBlank() })
                ?: json.optString("given_name").takeIf { it.isNotBlank() }
        } catch (e: Exception) { null }
    }

    fun setGoogleSignInError(message: String) {
        _error.value = message
    }

    private fun isValidEmail(s: String): Boolean =
        s.isNotBlank() && android.util.Patterns.EMAIL_ADDRESS.matcher(s).matches()

    fun completeOnboarding() { _hasCompletedOnboarding.value = true }
    fun logout() { _isAuthenticated.value = false; _hasCompletedOnboarding.value = false; _phone.value = ""; _email.value = ""; _otpCode.value = ""; _otpSent.value = false; _currentUser.value = null; APIService.clearTokens() }

    /**
     * Hydrate auth state from a session that was already in token storage when
     * the app launched, so the user lands directly on Main / Onboarding instead
     * of bouncing through Welcome.
     */
    fun bootstrapAuthenticated(user: User, hasOnboarded: Boolean) {
        _currentUser.value = user
        _isAuthenticated.value = true
        _hasCompletedOnboarding.value = hasOnboarded
    }

    private fun startResendTimer() {
        viewModelScope.launch { _resendCooldown.value = 30; while (_resendCooldown.value > 0) { delay(1000); _resendCooldown.value-- } }
    }
}
