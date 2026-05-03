package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.User
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

    fun updatePhone(value: String) { _phone.value = value }
    fun updateEmail(value: String) { _email.value = value.trim() }
    fun updateOtpCode(value: String) { _otpCode.value = value.take(6) }
    fun clearError() { _error.value = null }
    fun resetOtpState() { _otpSent.value = false; _otpCode.value = ""; _error.value = null }

    fun sendOTP() {
        if (_phone.value.length < 10) { _error.value = "Please enter a valid phone number"; return }
        viewModelScope.launch {
            _isLoading.value = true; _error.value = null
            APIService.sendOTP(_phone.value).onSuccess { _otpSent.value = true; _resendCount.value++; startResendTimer() }.onFailure { _error.value = "Failed to send OTP. Please try again." }
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
                _hasCompletedOnboarding.value = !isNewUser && user.profileCompleteness >= 50
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
                _hasCompletedOnboarding.value = !isNewUser && user.profileCompleteness >= 50
            }.onFailure { _error.value = "Invalid code. Please try again." }
            _isLoading.value = false
        }
    }

    private fun isValidEmail(s: String): Boolean =
        s.isNotBlank() && android.util.Patterns.EMAIL_ADDRESS.matcher(s).matches()

    fun completeOnboarding() { _hasCompletedOnboarding.value = true }
    fun logout() { _isAuthenticated.value = false; _hasCompletedOnboarding.value = false; _phone.value = ""; _email.value = ""; _otpCode.value = ""; _otpSent.value = false; _currentUser.value = null; APIService.clearTokens() }

    private fun startResendTimer() {
        viewModelScope.launch { _resendCooldown.value = 30; while (_resendCooldown.value > 0) { delay(1000); _resendCooldown.value-- } }
    }
}
