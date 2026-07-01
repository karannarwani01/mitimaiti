package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.*
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.services.MessageRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

class ChatViewModel : ViewModel() {
    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()
    private val _messageText = MutableStateFlow("")
    val messageText: StateFlow<String> = _messageText.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _isSending = MutableStateFlow(false)
    val isSending: StateFlow<Boolean> = _isSending.asStateFlow()
    private val _isOtherTyping = MutableStateFlow(false)
    val isOtherTyping: StateFlow<Boolean> = _isOtherTyping.asStateFlow()
    private val _match = MutableStateFlow<Match?>(null)
    val match: StateFlow<Match?> = _match.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _chatUnlocked = MutableStateFlow(false)
    val chatUnlocked: StateFlow<Boolean> = _chatUnlocked.asStateFlow()

    /**
     * Callback to notify InboxViewModel when a match becomes active (reply received).
     * Called with (matchId, lastMessage).
     */
    var onMatchActivated: ((String, String) -> Unit)? = null

    fun updateMessageText(value: String) { _messageText.value = value }
    val isLockedForMe: Boolean get() = _match.value?.let { it.firstMsgLocked && it.firstMsgByMe } ?: false
    val awaitingFirstMessage: Boolean get() = _match.value?.let { it.firstMsgBy == null } ?: true
    val showCountdown: Boolean get() = _match.value?.showCountdown ?: false
    val inputDisabled: Boolean get() = isLockedForMe
    val inputPlaceholder: String get() = when { isLockedForMe -> "Waiting for reply..."; awaitingFirstMessage -> "Send the first message!"; else -> "Type a message..." }
    val callsUnlocked: Boolean get() = _match.value?.callsUnlocked ?: false

    data class LockBanner(val title: String, val subtitle: String, val isLocked: Boolean)
    val lockBannerMessage: LockBanner? get() {
        val m = _match.value ?: return null
        return when {
            isLockedForMe -> LockBanner("Message sent!", "Waiting for ${m.otherUser.displayName} to reply before you can send another", true)
            awaitingFirstMessage -> LockBanner("New Match!", "Send the first message to start the conversation", false)
            m.showCountdown && !m.callsUnlocked -> LockBanner("Keep chatting!", "Exchange messages to unlock calls & video", false)
            else -> null
        }
    }

    fun loadMessages(match: Match) {
        _match.value = match
        // Check MessageRepository first (persists across navigation)
        val cached = MessageRepository.getMessages(match.id)
        if (cached.isNotEmpty()) {
            _messages.value = cached.sortedBy { it.createdAt }
            _isLoading.value = false
            checkAndUnlockIfReplied()
            return
        }
        // Fetch from API/mock
        viewModelScope.launch {
            _isLoading.value = true
            APIService.fetchMessages(match.id)
                .onSuccess {
                    _messages.value = it.sortedBy { m -> m.createdAt }
                    // Save to repository
                    MessageRepository.setMessages(match.id, _messages.value)
                    checkAndUnlockIfReplied()
                }
                .onFailure { _error.value = "Failed to load messages" }
            _isLoading.value = false
        }
    }

    fun sendChatPhoto(bytes: ByteArray) {
        val currentMatch = _match.value ?: return
        if (isLockedForMe) return
        viewModelScope.launch {
            _isSending.value = true
            APIService.sendChatMedia(currentMatch.id, bytes).onSuccess { msg ->
                _messages.value = _messages.value + msg
                MessageRepository.addMessage(currentMatch.id, msg)
                if (currentMatch.firstMsgBy == null) {
                    _match.value = currentMatch.copy(
                        firstMsgBy = "current-user-id", firstMsgByMe = true,
                        firstMsgLocked = true,
                        firstMsgAt = System.currentTimeMillis()
                    )
                }
            }.onFailure { _error.value = "Photo upload failed" }
            _isSending.value = false
        }
    }

    fun sendMessage() {
        // If we're editing, route to saveEdit instead of sending a new message
        if (_editingMessageId.value != null) {
            saveEdit()
            return
        }
        val text = _messageText.value.trim()
        if (text.isEmpty() || isLockedForMe) return
        val currentMatch = _match.value ?: return

        viewModelScope.launch {
            _isSending.value = true
            _messageText.value = ""

            val newMsg = Message(
                matchId = currentMatch.id,
                senderId = "current-user-id",
                content = text,
                status = MessageStatus.SENT
            )
            _messages.value = _messages.value + newMsg
            MessageRepository.addMessage(currentMatch.id, newMsg)

            // Mark as first message if none sent yet
            if (currentMatch.firstMsgBy == null) {
                _match.value = currentMatch.copy(
                    firstMsgBy = "current-user-id", firstMsgByMe = true,
                    firstMsgLocked = true,
                    firstMsgAt = System.currentTimeMillis()
                )
            }

            APIService.sendMessage(currentMatch.id, text)
            _isSending.value = false

            // Simulate a reply after delay
            simulateReply(currentMatch.id)
        }
    }

    fun sendIcebreaker(question: String) {
        _messageText.value = question
        sendMessage()
    }

    private val _editingMessageId = MutableStateFlow<String?>(null)
    val editingMessageId: StateFlow<String?> = _editingMessageId.asStateFlow()

    fun startEdit(message: Message) {
        if (message.msgType != MessageType.TEXT) return
        _editingMessageId.value = message.id
        _messageText.value = message.content.removeSuffix(" [edited]").trimEnd()
    }

    fun cancelEdit() {
        _editingMessageId.value = null
        _messageText.value = ""
    }

    fun saveEdit() {
        val id = _editingMessageId.value ?: return
        val newText = _messageText.value.trim()
        if (newText.isEmpty()) return
        val withMarker = if (newText.endsWith("[edited]")) newText else "$newText [edited]"
        _messages.value = _messages.value.map { m ->
            if (m.id == id) m.copy(content = withMarker) else m
        }
        // persist
        _match.value?.id?.let { mid ->
            MessageRepository.setMessages(mid, _messages.value)
        }
        _editingMessageId.value = null
        _messageText.value = ""
    }

    fun toggleReaction(message: Message, emoji: String) {
        if (!Message.ALLOWED_REACTIONS.contains(emoji)) return
        val mid = _match.value?.id ?: return
        _messages.value = _messages.value.map { m ->
            if (m.id == message.id) {
                m.copy(reaction = if (m.reaction == emoji) null else emoji)
            } else m
        }
        MessageRepository.setMessages(mid, _messages.value)
    }

    fun deleteMessage(message: Message) {
        _messages.value = _messages.value.filterNot { it.id == message.id }
        _match.value?.id?.let { mid ->
            MessageRepository.setMessages(mid, _messages.value)
        }
        if (_editingMessageId.value == message.id) {
            cancelEdit()
        }
    }

    fun sendVoice(mediaUrl: String, durationSeconds: Int) {
        if (isLockedForMe) return
        val currentMatch = _match.value ?: return

        viewModelScope.launch {
            _isSending.value = true

            val newMsg = Message(
                matchId = currentMatch.id,
                senderId = "current-user-id",
                content = "",
                mediaUrl = mediaUrl,
                msgType = MessageType.VOICE,
                status = MessageStatus.SENT,
                durationSeconds = durationSeconds
            )
            _messages.value = _messages.value + newMsg
            MessageRepository.addMessage(currentMatch.id, newMsg)

            if (currentMatch.firstMsgBy == null) {
                _match.value = currentMatch.copy(
                    firstMsgBy = "current-user-id", firstMsgByMe = true,
                    firstMsgLocked = true,
                    firstMsgAt = System.currentTimeMillis()
                )
            }

            _isSending.value = false
            simulateReply(currentMatch.id)
        }
    }

    fun sendImage(mediaUrl: String) {
        if (isLockedForMe) return
        val currentMatch = _match.value ?: return

        viewModelScope.launch {
            _isSending.value = true

            val newMsg = Message(
                matchId = currentMatch.id,
                senderId = "current-user-id",
                content = "",
                mediaUrl = mediaUrl,
                msgType = MessageType.PHOTO,
                status = MessageStatus.SENT
            )
            _messages.value = _messages.value + newMsg
            MessageRepository.addMessage(currentMatch.id, newMsg)

            if (currentMatch.firstMsgBy == null) {
                _match.value = currentMatch.copy(
                    firstMsgBy = "current-user-id", firstMsgByMe = true,
                    firstMsgLocked = true,
                    firstMsgAt = System.currentTimeMillis()
                )
            }

            _isSending.value = false
            simulateReply(currentMatch.id)
        }
    }

    private fun receiveMessage(message: Message) {
        _messages.value = _messages.value + message
        MessageRepository.addMessage(message.matchId, message)
        val cm = _match.value ?: return

        // If we were waiting for a reply (firstMsgLocked), activate the match
        if (cm.firstMsgLocked || cm.status == MatchStatus.PENDING_FIRST_MESSAGE) {
            _match.value = cm.copy(
                firstMsgLocked = false,
                status = MatchStatus.ACTIVE,
                expiresAt = null,
                lastMessage = message.content
            )
            _chatUnlocked.value = true

            // Notify InboxViewModel — move match to Chats permanently
            onMatchActivated?.invoke(cm.id, message.content)

            viewModelScope.launch {
                delay(3000)
                _chatUnlocked.value = false
            }
        } else {
            // Normal message in an active chat — just update lastMessage
            _match.value = cm.copy(lastMessage = message.content)
        }
    }

    private fun checkAndUnlockIfReplied() {
        val cm = _match.value ?: return
        if ((cm.firstMsgLocked || cm.status == MatchStatus.PENDING_FIRST_MESSAGE) &&
            cm.firstMsgBy == "current-user-id" &&
            _messages.value.any { it.senderId != "current-user-id" }
        ) {
            val lastReply = _messages.value.lastOrNull { it.senderId != "current-user-id" }
            _match.value = cm.copy(
                firstMsgLocked = false,
                status = MatchStatus.ACTIVE,
                expiresAt = null,
                lastMessage = lastReply?.content
            )
            _chatUnlocked.value = true
            onMatchActivated?.invoke(cm.id, lastReply?.content ?: "")
            viewModelScope.launch {
                delay(3000)
                _chatUnlocked.value = false
            }
        }
    }

    private fun simulateReply(matchId: String) {
        viewModelScope.launch {
            delay(3000)
            _isOtherTyping.value = true
            delay(2000)
            _isOtherTyping.value = false
            val replies = listOf(
                "That's so sweet! Tell me more about yourself",
                "Haha I love that! What else are you into?",
                "Oh wow, we have so much in common!",
                "That's interesting! I'd love to hear more",
                "You seem really cool! What do you do for fun?"
            )
            val replyText = replies.random()
            receiveMessage(
                Message(
                    id = UUID.randomUUID().toString(),
                    matchId = matchId,
                    senderId = _match.value?.otherUser?.id ?: "other",
                    content = replyText,
                    status = MessageStatus.DELIVERED
                )
            )
        }
    }

    fun markUnreadMessagesAsRead() {
        _messages.value = _messages.value.map {
            if (!it.isFromMe && it.status != MessageStatus.READ) it.copy(status = MessageStatus.READ) else it
        }
    }
}
