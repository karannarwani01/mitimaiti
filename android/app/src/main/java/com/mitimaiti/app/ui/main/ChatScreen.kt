@file:Suppress("DEPRECATION")
package com.mitimaiti.app.ui.main

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import com.mitimaiti.app.models.*
import com.mitimaiti.app.ui.theme.AppColors
import com.mitimaiti.app.ui.theme.AppTheme
import com.mitimaiti.app.ui.theme.LocalAdaptiveColors
import com.mitimaiti.app.viewmodels.ChatViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

/** Process-wide set of match IDs we've already warned about expiry, to avoid re-toasting. */
private object ChatExpiryWarnings {
    val shown = mutableSetOf<String>()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel,
    match: Match,
    onBack: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    val messages by viewModel.messages.collectAsState()
    val messageText by viewModel.messageText.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isOtherTyping by viewModel.isOtherTyping.collectAsState()
    val chatMatch by viewModel.match.collectAsState()
    val chatUnlocked by viewModel.chatUnlocked.collectAsState()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Menu state
    var showMenu by remember { mutableStateOf(false) }
    var showUnmatchDialog by remember { mutableStateOf(false) }
    var showReportSheet by remember { mutableStateOf(false) }

    // Image viewer state
    var viewerImageUrl by remember { mutableStateOf<String?>(null) }

    // Long-press action sheet state — which message id has its menu open
    var actionSheetForMessage by remember { mutableStateOf<Message?>(null) }
    val editingMessageId by viewModel.editingMessageId.collectAsState()

    // ── Voice recording state ──
    val context = LocalContext.current
    var isRecording by remember { mutableStateOf(false) }
    var recordingSeconds by remember { mutableIntStateOf(0) }
    val mediaRecorderRef = remember { mutableStateOf<MediaRecorder?>(null) }
    val recordingFileRef = remember { mutableStateOf<java.io.File?>(null) }
    val recordingStartRef = remember { mutableLongStateOf(0L) }

    fun stopVoiceRecording(cancel: Boolean) {
        val recorder = mediaRecorderRef.value ?: return
        try { recorder.stop() } catch (_: Exception) {}
        try { recorder.release() } catch (_: Exception) {}
        mediaRecorderRef.value = null
        val durationSec = ((System.currentTimeMillis() - recordingStartRef.longValue) / 1000L).toInt()
        val file = recordingFileRef.value
        recordingFileRef.value = null
        isRecording = false
        recordingSeconds = 0
        if (cancel || file == null || !file.exists() || durationSec < 1) {
            file?.delete()
            return
        }
        viewModel.sendVoice(Uri.fromFile(file).toString(), durationSec)
    }

    val recordPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            Toast.makeText(context, "Microphone permission needed for voice notes", Toast.LENGTH_SHORT).show()
        }
    }

    fun startVoiceRecording() {
        if (isRecording) return
        // Permission check
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            recordPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            return
        }
        try {
            val outFile = java.io.File(
                context.cacheDir,
                "voice_${System.currentTimeMillis()}.m4a"
            )
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION") MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(64_000)
            recorder.setAudioSamplingRate(44_100)
            recorder.setOutputFile(outFile.absolutePath)
            recorder.prepare()
            recorder.start()
            mediaRecorderRef.value = recorder
            recordingFileRef.value = outFile
            recordingStartRef.longValue = System.currentTimeMillis()
            isRecording = true
            recordingSeconds = 0
        } catch (e: Exception) {
            Toast.makeText(context, "Couldn't start recording", Toast.LENGTH_SHORT).show()
        }
    }

    LaunchedEffect(isRecording) {
        while (isRecording) {
            delay(250)
            recordingSeconds = ((System.currentTimeMillis() - recordingStartRef.longValue) / 1000L).toInt()
            if (recordingSeconds >= 300) {
                // 5 min cap matches backend
                stopVoiceRecording(cancel = false)
            }
        }
    }

    // Cleanup if screen leaves while recording
    DisposableEffect(Unit) {
        onDispose {
            mediaRecorderRef.value?.let {
                try { it.stop() } catch (_: Exception) {}
                try { it.release() } catch (_: Exception) {}
            }
            mediaRecorderRef.value = null
        }
    }

    // Attachment chooser ("Camera" or "Gallery")
    var showAttachmentSheet by remember { mutableStateOf(false) }
    val pendingCameraUri = remember { mutableStateOf<Uri?>(null) }

    // Gallery picker (15MB cap matches backend multer limit)
    val galleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val sizeBytes = runCatching {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: 0L
        }.getOrDefault(0L)
        if (sizeBytes > 15L * 1024 * 1024) {
            Toast.makeText(context, "Image must be under 15MB", Toast.LENGTH_SHORT).show()
            return@rememberLauncherForActivityResult
        }
        viewModel.sendImage(uri.toString())
    }

    // Live camera capture — writes to a FileProvider URI we hand it
    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success: Boolean ->
        val uri = pendingCameraUri.value
        pendingCameraUri.value = null
        if (!success || uri == null) return@rememberLauncherForActivityResult
        viewModel.sendImage(uri.toString())
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val photoFile = java.io.File(context.cacheDir, "chat_photo_${System.currentTimeMillis()}.jpg")
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photoFile)
            pendingCameraUri.value = uri
            cameraLauncher.launch(uri)
        } else {
            Toast.makeText(context, "Camera permission needed to take a live photo", Toast.LENGTH_SHORT).show()
        }
    }

    fun launchCamera() {
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
            return
        }
        val photoFile = java.io.File(context.cacheDir, "chat_photo_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photoFile)
        pendingCameraUri.value = uri
        cameraLauncher.launch(uri)
    }

    // Ice breaker prompts
    var currentPrompts by remember { mutableStateOf(IceBreakerPrompts.getRandomPrompts(3)) }

    LaunchedEffect(match) { viewModel.loadMessages(match) }

    // 1-hour expiry warning — fires once per match per session
    LaunchedEffect(match.id, match.expiresAt) {
        val expiresAt = match.expiresAt ?: return@LaunchedEffect
        val remaining = expiresAt - System.currentTimeMillis()
        val oneHour = 60L * 60L * 1000L
        if (remaining in 1..oneHour) {
            val key = "chat_1h_warned_${match.id}"
            val warned = ChatExpiryWarnings.shown.contains(key)
            if (!warned) {
                ChatExpiryWarnings.shown.add(key)
                Toast.makeText(context, "⏳ Less than 1 hour left to chat!", Toast.LENGTH_LONG).show()
            }
        }
    }
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    // Scroll-to-bottom detection
    val showScrollToBottom by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val totalItems = listState.layoutInfo.totalItemsCount
            totalItems > 0 && lastVisible < totalItems - 2
        }
    }

    // Group messages by date
    val groupedMessages = remember(messages) { groupMessagesByDate(messages) }

    // Chat unlock toast
    var showUnlockToast by remember { mutableStateOf(false) }
    LaunchedEffect(chatUnlocked) {
        if (chatUnlocked) { showUnlockToast = true; delay(3000L); showUnlockToast = false }
    }

    val otherUser = match.otherUser

    Scaffold(
        containerColor = colors.background,
        topBar = {
            // ── Bumble-style header ──
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.clickable { /* open profile detail */ }
                    ) {
                        // Avatar with online dot
                        Box {
                            AsyncImage(
                                model = otherUser.primaryPhoto?.urlThumb ?: otherUser.primaryPhoto?.url ?: "",
                                contentDescription = null,
                                modifier = Modifier.size(40.dp).clip(CircleShape),
                                contentScale = ContentScale.Crop
                            )
                            if (otherUser.isOnline) {
                                Box(
                                    modifier = Modifier
                                        .size(12.dp)
                                        .align(Alignment.BottomEnd)
                                        .clip(CircleShape)
                                        .background(Color.White)
                                        .padding(2.dp)
                                        .clip(CircleShape)
                                        .background(AppColors.Success)
                                )
                            }
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    "${otherUser.displayName}${otherUser.age?.let { ", $it" } ?: ""}",
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = colors.textPrimary
                                )
                                if (otherUser.isVerified) {
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Icon(Icons.Default.Verified, null, tint = AppColors.Info, modifier = Modifier.size(16.dp))
                                }
                            }
                            Text(
                                if (otherUser.isOnline) "Online" else "Offline",
                                fontSize = 12.sp,
                                color = if (otherUser.isOnline) AppColors.Success else colors.textMuted
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back", tint = colors.textPrimary)
                    }
                },
                actions = {
                    // Video call
                    IconButton(onClick = {
                        Toast.makeText(context, "📹 Video calls coming soon", Toast.LENGTH_SHORT).show()
                    }) {
                        Icon(Icons.Default.Videocam, "Video call", tint = AppColors.Rose)
                    }
                    // Voice call
                    IconButton(onClick = {
                        Toast.makeText(context, "📞 Voice calls coming soon", Toast.LENGTH_SHORT).show()
                    }) {
                        Icon(Icons.Default.Phone, "Voice call", tint = AppColors.Rose)
                    }
                    // More menu
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, "More", tint = colors.textSecondary)
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Unmatch") },
                                onClick = { showMenu = false; showUnmatchDialog = true },
                                leadingIcon = { Icon(Icons.Default.HeartBroken, null, tint = colors.textSecondary) }
                            )
                            DropdownMenuItem(
                                text = { Text("Block") },
                                onClick = { showMenu = false; showUnmatchDialog = true },
                                leadingIcon = { Icon(Icons.Default.Block, null, tint = AppColors.Error) }
                            )
                            DropdownMenuItem(
                                text = { Text("Report", color = AppColors.Error) },
                                onClick = { showMenu = false; showReportSheet = true },
                                leadingIcon = { Icon(Icons.Default.Flag, null, tint = AppColors.Error) }
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.surface)
            )
        }
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            Column(modifier = Modifier.fillMaxSize()) {
                // ── Lock banner (only during ice breaker phase) ──
                if (viewModel.isLockedForMe) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        color = AppColors.Rose.copy(alpha = 0.08f)
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Lock, null, tint = AppColors.Rose, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text("Message sent!", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                                Text("Waiting for ${otherUser.displayName.split(" ").first()} to reply...", fontSize = 12.sp, color = colors.textSecondary)
                            }
                        }
                    }
                }

                // ── Chat unlock toast ──
                AnimatedVisibility(
                    visible = showUnlockToast,
                    enter = slideInVertically(initialOffsetY = { -it }) + fadeIn(),
                    exit = slideOutVertically(targetOffsetY = { -it }) + fadeOut()
                ) {
                    Surface(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                        shape = RoundedCornerShape(AppTheme.radiusMd),
                        color = AppColors.Success.copy(alpha = 0.12f)
                    ) {
                        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                            Icon(Icons.Default.LockOpen, null, tint = AppColors.Success, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Chat unlocked! You can now chat freely.", fontSize = 14.sp, color = AppColors.Success, fontWeight = FontWeight.Medium)
                        }
                    }
                }

                // ── Match announcement ──
                MatchAnnouncementCapsule(match = match)

                // ── Messages list ──
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp),
                    state = listState,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    // Ice breaker section (only for new matches with no messages)
                    if (messages.isEmpty() && !isLoading && viewModel.awaitingFirstMessage && match.status == MatchStatus.PENDING_FIRST_MESSAGE) {
                        item {
                            IceBreakerSection(
                                prompts = currentPrompts,
                                onSelect = { viewModel.sendIcebreaker(it) },
                                onShuffle = { currentPrompts = IceBreakerPrompts.getRandomPrompts(3) }
                            )
                        }
                    }

                    // Messages grouped by date
                    groupedMessages.forEach { (dateLabel, dateMessages) ->
                        item(key = "date_$dateLabel") { DateHeader(label = dateLabel) }
                        items(dateMessages, key = { it.id }) { message ->
                            BumbleMessageBubble(
                                message = message,
                                otherUserPhoto = otherUser.primaryPhoto?.urlThumb ?: otherUser.primaryPhoto?.url ?: "",
                                onImageClick = { url -> viewerImageUrl = url },
                                onLongPress = { msg -> actionSheetForMessage = msg }
                            )
                        }
                    }

                    // Typing indicator
                    if (isOtherTyping) {
                        item(key = "typing") {
                            TypingIndicatorBubble(
                                photoUrl = otherUser.primaryPhoto?.urlThumb ?: otherUser.primaryPhoto?.url ?: ""
                            )
                        }
                    }
                }

                // ── Recording banner ──
                if (isRecording) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        color = AppColors.Rose
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(Color.White, CircleShape)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            val mins = recordingSeconds / 60
                            val secs = recordingSeconds % 60
                            Text(
                                "Recording… ${"%d:%02d".format(mins, secs)}",
                                color = Color.White,
                                fontSize = 13.sp,
                                modifier = Modifier.weight(1f)
                            )
                            TextButton(onClick = { stopVoiceRecording(cancel = true) }) {
                                Text("Cancel", color = Color.White, fontSize = 13.sp)
                            }
                        }
                    }
                }

                // ── Editing banner ──
                if (editingMessageId != null) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        color = AppColors.Rose.copy(alpha = 0.06f)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = null,
                                tint = AppColors.Rose,
                                modifier = Modifier.size(14.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                "Editing message",
                                fontSize = 12.sp,
                                color = colors.textPrimary,
                                modifier = Modifier.weight(1f)
                            )
                            TextButton(onClick = { viewModel.cancelEdit() }) {
                                Text("Cancel", color = AppColors.Rose, fontSize = 12.sp)
                            }
                        }
                    }
                }

                // ── Input bar ──
                ChatInputBar(
                    messageText = messageText,
                    onTextChange = { viewModel.updateMessageText(it) },
                    onSend = { viewModel.sendMessage() },
                    onCameraClick = { showAttachmentSheet = true },
                    onMicPressDown = { startVoiceRecording() },
                    onMicPressUp = { cancel -> stopVoiceRecording(cancel) },
                    isRecording = isRecording,
                    disabled = viewModel.inputDisabled && editingMessageId == null,
                    placeholder = when {
                        editingMessageId != null -> "Edit message..."
                        viewModel.isLockedForMe -> "Waiting for reply..."
                        viewModel.awaitingFirstMessage -> "Send the first message!"
                        else -> "Type a message..."
                    },
                    isLocked = viewModel.isLockedForMe && editingMessageId == null
                )
            }

            // ── New message ↓ button ──
            if (showScrollToBottom) {
                Surface(
                    onClick = { scope.launch { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1) } },
                    modifier = Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 80.dp).size(40.dp),
                    color = colors.surface,
                    shape = CircleShape,
                    shadowElevation = 6.dp,
                    border = BorderStroke(1.dp, colors.border)
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Icon(Icons.Default.KeyboardArrowDown, "New messages", tint = AppColors.Rose, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }

    // ── Unmatch confirmation dialog ──
    if (showUnmatchDialog) {
        AlertDialog(
            onDismissRequest = { showUnmatchDialog = false },
            title = { Text("Unmatch?", fontWeight = FontWeight.Bold) },
            text = { Text("Are you sure you want to unmatch with ${otherUser.displayName}? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = { showUnmatchDialog = false; viewModel.unmatch { onBack() } }) {
                    Text("Unmatch", color = AppColors.Error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showUnmatchDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // ── Report sheet ──
    if (showReportSheet) {
        ReportSheet(
            userName = otherUser.displayName,
            onDismiss = { showReportSheet = false },
            onReport = { showReportSheet = false; onBack() }
        )
    }

    // ── Attachment chooser (Camera / Gallery) ──
    if (showAttachmentSheet) {
        AlertDialog(
            onDismissRequest = { showAttachmentSheet = false },
            title = { Text("Send a photo", fontWeight = FontWeight.SemiBold) },
            text = {
                Column {
                    TextButton(
                        onClick = {
                            showAttachmentSheet = false
                            launchCamera()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Default.CameraAlt, null, tint = AppColors.Rose, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Take a live photo", color = colors.textPrimary, fontSize = 16.sp)
                        }
                    }
                    TextButton(
                        onClick = {
                            showAttachmentSheet = false
                            galleryLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Default.PhotoLibrary, null, tint = AppColors.Rose, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Choose from gallery", color = colors.textPrimary, fontSize = 16.sp)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showAttachmentSheet = false }) { Text("Cancel") }
            }
        )
    }

    // ── Long-press action sheet (reactions for any, edit/delete for own) ──
    val sheetMsg = actionSheetForMessage
    if (sheetMsg != null) {
        AlertDialog(
            onDismissRequest = { actionSheetForMessage = null },
            title = null,
            text = {
                Column {
                    // Reactions row (any message)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Message.ALLOWED_REACTIONS.forEach { emoji ->
                            val selected = sheetMsg.reaction == emoji
                            Surface(
                                onClick = {
                                    viewModel.toggleReaction(sheetMsg, emoji)
                                    actionSheetForMessage = null
                                },
                                shape = CircleShape,
                                color = if (selected) AppColors.Rose.copy(alpha = 0.15f) else Color.Transparent,
                                modifier = Modifier.size(40.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                                    Text(emoji, fontSize = 22.sp)
                                }
                            }
                        }
                    }
                    if (sheetMsg.isFromMe) {
                        Divider(modifier = Modifier.padding(vertical = 4.dp))
                        if (sheetMsg.msgType == MessageType.TEXT) {
                            TextButton(
                                onClick = {
                                    viewModel.startEdit(sheetMsg)
                                    actionSheetForMessage = null
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                    Icon(Icons.Default.Edit, null, tint = AppColors.Rose, modifier = Modifier.size(18.dp))
                                    Spacer(modifier = Modifier.width(12.dp))
                                    Text("Edit", color = colors.textPrimary, fontSize = 16.sp)
                                }
                            }
                        }
                        TextButton(
                            onClick = {
                                viewModel.deleteMessage(sheetMsg)
                                actionSheetForMessage = null
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                Icon(Icons.Default.Delete, null, tint = AppColors.Error, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(12.dp))
                                Text("Delete", color = AppColors.Error, fontSize = 16.sp)
                            }
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { actionSheetForMessage = null }) { Text("Cancel") }
            }
        )
    }

    // ── Fullscreen image viewer ──
    val imgUrl = viewerImageUrl
    if (imgUrl != null) {
        Dialog(
            onDismissRequest = { viewerImageUrl = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.92f))
                    .clickable { viewerImageUrl = null },
                contentAlignment = Alignment.Center
            ) {
                AsyncImage(
                    model = imgUrl,
                    contentDescription = "Photo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit
                )
                IconButton(
                    onClick = { viewerImageUrl = null },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(16.dp)
                        .background(Color.White.copy(alpha = 0.15f), CircleShape)
                ) {
                    Icon(Icons.Default.Close, "Close", tint = Color.White)
                }
            }
        }
    }
}

// ───────────────────────────────────────────
// Ice Breaker Section with Dice Shuffle
// ───────────────────────────────────────────

@Composable
private fun IceBreakerSection(
    prompts: List<IceBreakerPrompt>,
    onSelect: (String) -> Unit,
    onShuffle: () -> Unit
) {
    val colors = LocalAdaptiveColors.current
    Column(modifier = Modifier.padding(vertical = 16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text("Break the ice!", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
                Text("Tap a prompt or type your own", fontSize = 14.sp, color = colors.textSecondary)
            }
            // Dice shuffle button
            IconButton(onClick = onShuffle) {
                Icon(Icons.Default.Casino, "Shuffle prompts", tint = AppColors.Rose, modifier = Modifier.size(28.dp))
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        prompts.forEach { prompt ->
            Surface(
                onClick = { onSelect(prompt.text) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                shape = RoundedCornerShape(16.dp),
                color = AppColors.Rose.copy(alpha = 0.06f),
                border = BorderStroke(1.dp, AppColors.Rose.copy(alpha = 0.2f))
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(prompt.category.emoji, fontSize = 20.sp)
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            prompt.category.displayName.uppercase(),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.Rose,
                            letterSpacing = 1.sp
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            prompt.text,
                            fontSize = 14.sp,
                            color = colors.textPrimary,
                            fontWeight = FontWeight.Medium
                        )
                    }
                    Icon(Icons.Default.Send, null, tint = AppColors.Rose.copy(alpha = 0.5f), modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

// ───────────────────────────────────────────
// Bumble-style Message Bubble with Profile Photo
// ───────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BumbleMessageBubble(
    message: Message,
    otherUserPhoto: String,
    onImageClick: (String) -> Unit = {},
    onLongPress: (Message) -> Unit = {}
) {
    val isFromMe = message.isFromMe
    val colors = LocalAdaptiveColors.current
    val timeFormat = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }
    val isPhoto = message.msgType == MessageType.PHOTO && !message.mediaUrl.isNullOrBlank()
    val isVoice = message.msgType == MessageType.VOICE && !message.mediaUrl.isNullOrBlank()
    val isEdited = message.msgType == MessageType.TEXT && message.content.contains("[edited]")
    val displayContent = if (isEdited) message.content.removeSuffix(" [edited]").removeSuffix("[edited]").trimEnd() else message.content

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = if (isFromMe) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom
    ) {
        // Other user's profile photo (left side)
        if (!isFromMe) {
            AsyncImage(
                model = otherUserPhoto,
                contentDescription = null,
                modifier = Modifier.size(32.dp).clip(CircleShape),
                contentScale = ContentScale.Crop
            )
            Spacer(modifier = Modifier.width(8.dp))
        }

        // Message bubble (with optional reaction chip overlay)
        Box {
        Surface(
            shape = RoundedCornerShape(
                topStart = 18.dp,
                topEnd = 18.dp,
                bottomStart = if (isFromMe) 18.dp else 4.dp,
                bottomEnd = if (isFromMe) 4.dp else 18.dp
            ),
            color = if (isPhoto) Color.Transparent else (if (isFromMe) AppColors.Rose else colors.surfaceMedium),
            modifier = Modifier
                .widthIn(max = 260.dp)
                .combinedClickable(
                    onClick = {},
                    onLongClick = { onLongPress(message) }
                )
        ) {
            Column(modifier = if (isPhoto) Modifier else Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                if (isPhoto) {
                    AsyncImage(
                        model = message.mediaUrl,
                        contentDescription = "Photo message",
                        modifier = Modifier
                            .widthIn(max = 240.dp)
                            .heightIn(max = 320.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .clickable { onImageClick(message.mediaUrl!!) },
                        contentScale = ContentScale.Crop
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                } else if (isVoice) {
                    VoiceMessageContent(
                        audioUrl = message.mediaUrl!!,
                        durationSeconds = message.durationSeconds,
                        isFromMe = isFromMe
                    )
                } else {
                    // Ice breaker card styling (if message matches a prompt)
                    val isIceBreaker = IceBreakerPrompts.getAll().any { it.text == message.content }
                    if (isIceBreaker && isFromMe) {
                        Text(
                            "ICE BREAKER",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White.copy(alpha = 0.7f),
                            letterSpacing = 1.sp
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                    }

                    Text(
                        displayContent,
                        fontSize = 15.sp,
                        color = if (isFromMe) Color.White else colors.textPrimary,
                        lineHeight = 20.sp
                    )
                }

                Spacer(modifier = Modifier.height(3.dp))

                // Timestamp + read receipts
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Edited tag
                    if (isEdited) {
                        Text("edited ", fontSize = 10.sp, fontStyle = FontStyle.Italic,
                            color = if (isFromMe) Color.White.copy(alpha = 0.5f) else colors.textMuted)
                    }

                    Text(
                        timeFormat.format(Date(message.createdAt)),
                        fontSize = 10.sp,
                        color = if (isFromMe) Color.White.copy(alpha = 0.6f) else colors.textMuted
                    )

                    // Read receipts (only for sent messages)
                    if (isFromMe) {
                        Spacer(modifier = Modifier.width(4.dp))
                        when (message.status) {
                            MessageStatus.SENT -> Icon(
                                Icons.Default.Check, "Sent",
                                tint = Color.White.copy(alpha = 0.6f),
                                modifier = Modifier.size(14.dp)
                            )
                            MessageStatus.DELIVERED -> Icon(
                                Icons.Default.DoneAll, "Delivered",
                                tint = Color.White.copy(alpha = 0.6f),
                                modifier = Modifier.size(14.dp)
                            )
                            MessageStatus.READ -> Icon(
                                Icons.Default.DoneAll, "Read",
                                tint = Color(0xFF4FC3F7), // Blue ticks
                                modifier = Modifier.size(14.dp)
                            )
                            else -> {}
                        }
                    }
                }
            }
        }
            // Reaction chip overlay
            message.reaction?.let { emoji ->
                Surface(
                    shape = CircleShape,
                    color = colors.surface,
                    border = BorderStroke(0.5.dp, colors.border),
                    shadowElevation = 2.dp,
                    modifier = Modifier
                        .align(if (isFromMe) Alignment.BottomStart else Alignment.BottomEnd)
                        .offset(
                            x = if (isFromMe) (-4).dp else 4.dp,
                            y = 6.dp
                        )
                ) {
                    Text(
                        emoji,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }

        // Spacer for sent messages (no photo on right)
        if (isFromMe) {
            Spacer(modifier = Modifier.width(4.dp))
        }
    }
}

// ───────────────────────────────────────────
// Voice Message Content (play/pause + stylized waveform + duration)
// ───────────────────────────────────────────

private val VOICE_BAR_HEIGHTS = listOf(
    0.55f, 0.78f, 0.42f, 0.92f, 0.65f, 0.38f, 0.85f, 0.58f, 0.72f, 0.46f,
    0.88f, 0.51f, 0.66f, 0.81f, 0.43f, 0.74f, 0.59f, 0.95f, 0.62f, 0.49f
)

@Composable
private fun VoiceMessageContent(
    audioUrl: String,
    durationSeconds: Int,
    isFromMe: Boolean
) {
    val context = LocalContext.current
    var isPlaying by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    val playerRef = remember { mutableStateOf<MediaPlayer?>(null) }

    DisposableEffect(audioUrl) {
        onDispose {
            playerRef.value?.let {
                try { it.stop() } catch (_: Exception) {}
                try { it.release() } catch (_: Exception) {}
            }
            playerRef.value = null
        }
    }

    LaunchedEffect(isPlaying) {
        while (isPlaying) {
            delay(100)
            val p = playerRef.value
            if (p != null && p.isPlaying && p.duration > 0) {
                progress = p.currentPosition.toFloat() / p.duration.toFloat()
            }
        }
    }

    val onTogglePlay: () -> Unit = {
        val existing = playerRef.value
        if (existing == null) {
            try {
                val mp = MediaPlayer()
                mp.setDataSource(context, Uri.parse(audioUrl))
                mp.setOnCompletionListener {
                    isPlaying = false
                    progress = 0f
                }
                mp.setOnPreparedListener { mp.start() }
                mp.prepareAsync()
                playerRef.value = mp
                isPlaying = true
            } catch (_: Exception) {
                Toast.makeText(context, "Couldn't play voice note", Toast.LENGTH_SHORT).show()
            }
        } else if (existing.isPlaying) {
            existing.pause()
            isPlaying = false
        } else {
            existing.start()
            isPlaying = true
        }
    }

    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.widthIn(min = 180.dp)) {
        Surface(
            shape = CircleShape,
            color = if (isFromMe) Color.White.copy(alpha = 0.2f) else AppColors.Rose,
            modifier = Modifier.size(32.dp).clickable(onClick = onTogglePlay)
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                Icon(
                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    tint = if (isFromMe) Color.White else Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        Spacer(modifier = Modifier.width(8.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier.height(24.dp).weight(1f)
        ) {
            VOICE_BAR_HEIGHTS.forEachIndexed { idx, h ->
                val filled = (idx.toFloat() / VOICE_BAR_HEIGHTS.size) <= progress
                val barColor = if (filled) {
                    if (isFromMe) Color.White else AppColors.Rose
                } else {
                    if (isFromMe) Color.White.copy(alpha = 0.4f) else Color.LightGray
                }
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .fillMaxHeight(h)
                        .background(barColor, RoundedCornerShape(1.5.dp))
                )
            }
        }
        Spacer(modifier = Modifier.width(8.dp))
        val mins = durationSeconds / 60
        val secs = durationSeconds % 60
        Text(
            "${"%d:%02d".format(mins, secs)}",
            fontSize = 11.sp,
            color = if (isFromMe) Color.White.copy(alpha = 0.85f) else Color(0xFF666666)
        )
    }
}

// ───────────────────────────────────────────
// Typing Indicator Bubble (iMessage-style)
// ───────────────────────────────────────────

@Composable
private fun TypingIndicatorBubble(photoUrl: String) {
    val colors = LocalAdaptiveColors.current
    val infiniteTransition = rememberInfiniteTransition(label = "typing")

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = Arrangement.Start,
        verticalAlignment = Alignment.Bottom
    ) {
        AsyncImage(
            model = photoUrl,
            contentDescription = null,
            modifier = Modifier.size(32.dp).clip(CircleShape),
            contentScale = ContentScale.Crop
        )
        Spacer(modifier = Modifier.width(8.dp))
        Surface(
            shape = RoundedCornerShape(18.dp, 18.dp, 18.dp, 4.dp),
            color = colors.surfaceMedium
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                repeat(3) { index ->
                    val dotAlpha by infiniteTransition.animateFloat(
                        initialValue = 0.3f,
                        targetValue = 1f,
                        animationSpec = infiniteRepeatable(
                            animation = tween(600, delayMillis = index * 200),
                            repeatMode = RepeatMode.Reverse
                        ),
                        label = "dot$index"
                    )
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(colors.textMuted.copy(alpha = dotAlpha))
                    )
                }
            }
        }
    }
}

// ───────────────────────────────────────────
// Match Announcement Capsule
// ───────────────────────────────────────────

@Composable
private fun MatchAnnouncementCapsule(match: Match) {
    val dateFormat = remember { SimpleDateFormat("MMM d, yyyy", Locale.getDefault()) }
    Box(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(AppTheme.radiusFull),
            color = AppColors.Rose.copy(alpha = 0.08f)
        ) {
            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Favorite, null, tint = AppColors.Rose, modifier = Modifier.size(14.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    "You matched on ${dateFormat.format(Date(match.matchedAt))}",
                    fontSize = 12.sp, color = AppColors.Rose, fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

// ───────────────────────────────────────────
// Date Header
// ───────────────────────────────────────────

@Composable
private fun DateHeader(label: String) {
    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(AppTheme.radiusFull), color = LocalAdaptiveColors.current.surfaceMedium) {
            Text(label, modifier = Modifier.padding(horizontal = 14.dp, vertical = 5.dp), fontSize = 12.sp, fontWeight = FontWeight.Medium, color = LocalAdaptiveColors.current.textMuted)
        }
    }
}

// ───────────────────────────────────────────
// Report Sheet
// ───────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReportSheet(userName: String, onDismiss: () -> Unit, onReport: (String) -> Unit) {
    val colors = LocalAdaptiveColors.current
    val reasons = listOf("Inappropriate behavior", "Fake profile", "Spam", "Underage", "Other")
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text("Report $userName", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
            Spacer(modifier = Modifier.height(4.dp))
            Text("Why are you reporting this person?", fontSize = 14.sp, color = colors.textSecondary)
            Spacer(modifier = Modifier.height(16.dp))
            reasons.forEach { reason ->
                Surface(
                    onClick = { onReport(reason) },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    shape = RoundedCornerShape(AppTheme.radiusMd),
                    color = colors.surfaceMedium
                ) {
                    Text(reason, modifier = Modifier.padding(16.dp), fontSize = 15.sp, color = colors.textPrimary)
                }
            }
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

// ───────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────

// ───────────────────────────────────────────
// Chat Input Bar (with emoji, camera, mic buttons)
// ───────────────────────────────────────────

@Composable
private fun ChatInputBar(
    messageText: String,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit,
    onCameraClick: () -> Unit,
    onMicPressDown: () -> Unit,
    onMicPressUp: (cancel: Boolean) -> Unit,
    isRecording: Boolean,
    disabled: Boolean,
    placeholder: String,
    isLocked: Boolean
) {
    val colors = LocalAdaptiveColors.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = colors.surface,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Camera button
            IconButton(onClick = onCameraClick, enabled = !disabled) {
                Icon(Icons.Default.CameraAlt, "Photo", tint = if (disabled) colors.textMuted.copy(alpha = 0.3f) else AppColors.Rose)
            }

            // Text field
            OutlinedTextField(
                value = messageText,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text(placeholder, fontSize = 14.sp, color = colors.textMuted) },
                enabled = !disabled,
                shape = RoundedCornerShape(24.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.Rose,
                    unfocusedBorderColor = colors.border,
                    disabledBorderColor = colors.border.copy(alpha = 0.3f)
                ),
                singleLine = false,
                maxLines = 4,
                trailingIcon = {
                    // Emoji button
                    IconButton(onClick = { }) {
                        Icon(Icons.Default.EmojiEmotions, "Emoji", tint = if (disabled) colors.textMuted.copy(alpha = 0.3f) else colors.textMuted)
                    }
                }
            )

            Spacer(modifier = Modifier.width(4.dp))

            // Send or Mic button
            if (messageText.isNotBlank()) {
                IconButton(
                    onClick = onSend,
                    modifier = Modifier
                        .size(44.dp)
                        .background(AppColors.Rose, CircleShape)
                ) {
                    Icon(Icons.Default.Send, "Send", tint = Color.White, modifier = Modifier.size(20.dp))
                }
            } else {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .background(
                            color = if (isRecording) AppColors.Rose else Color.Transparent,
                            shape = CircleShape
                        )
                        .pointerInput(disabled) {
                            if (disabled) return@pointerInput
                            detectTapGestures(
                                onPress = {
                                    onMicPressDown()
                                    val released = tryAwaitRelease()
                                    onMicPressUp(!released)
                                }
                            )
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Default.Mic,
                        "Hold to record",
                        tint = when {
                            disabled -> colors.textMuted.copy(alpha = 0.3f)
                            isRecording -> Color.White
                            else -> AppColors.Rose
                        }
                    )
                }
            }
        }
    }
}

// ───────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────

private fun groupMessagesByDate(messages: List<Message>): List<Pair<String, List<Message>>> {
    val cal = Calendar.getInstance()
    val today = Calendar.getInstance()
    val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
    val dateFormat = SimpleDateFormat("MMM d", Locale.getDefault())

    return messages.groupBy { msg ->
        cal.timeInMillis = msg.createdAt
        when {
            cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) && cal.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR) -> "Today"
            cal.get(Calendar.YEAR) == yesterday.get(Calendar.YEAR) && cal.get(Calendar.DAY_OF_YEAR) == yesterday.get(Calendar.DAY_OF_YEAR) -> "Yesterday"
            else -> dateFormat.format(Date(msg.createdAt))
        }
    }.toList()
}
