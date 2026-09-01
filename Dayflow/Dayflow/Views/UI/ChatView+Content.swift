import AppKit
import Charts
import SwiftUI

extension ChatView {
  var chatContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      chatHeaderBar
      messagesArea

      Divider()
        .background(Color(hex: "ECECEC"))

      // Input area
      inputArea
    }
    .background(TaktColor.surface)
  }

  // MARK: - Header buttons

  var chatHeaderBar: some View {
    HStack(spacing: 8) {
      Spacer()

      // New chat button (only show if there are messages)
      if !chatService.messages.isEmpty {
        Button(action: { resetConversation() }) {
          Text("Neuer Chat")
            .font(TaktFont.ui(12, .semibold))
            .foregroundColor(TaktColor.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .fill(TaktColor.accentSoft)
            )
            .overlay(
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .stroke(TaktColor.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Neuen Chat starten (der aktuelle wird im Verlauf gespeichert)")
        .pointingHandCursor()
      }

      // History toggle
      Button(
        action: {
          showHistoryPanel.toggle()
          if showHistoryPanel {
            chatService.refreshConversationList()
          }
        }
      ) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 14))
          .foregroundColor(showHistoryPanel ? Color(hex: "F96E00") : Color(hex: "999999"))
      }
      .buttonStyle(.plain)
      .help("Chat-Verlauf anzeigen")
      .pointingHandCursor()

      Button(
        action: {
          showMemoryPanel.toggle()
          if showMemoryPanel {
            syncMemoryFromStoreIfNeeded()
            AnalyticsService.shared.capture("chat_memory_panel_opened")
          }
        }
      ) {
        Image(systemName: showMemoryPanel ? "brain.head.profile.fill" : "brain.head.profile")
          .font(.system(size: 14))
          .foregroundColor(showMemoryPanel ? Color(hex: "F96E00") : Color(hex: "999999"))
      }
      .buttonStyle(.plain)
      .help("Notiz-Panel anzeigen")
      .pointingHandCursor()
    }
    .padding(.trailing, 12)
    .padding(.top, 8)
  }

  // MARK: - Messages area

  // Scroll behavior follows shadcn's message-scroller rules: a new user turn
  // anchors near the top and the reply streams into the space below;
  // auto-follow only runs while the reader is at the live edge.
  var messagesArea: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .bottom) {
        transcriptScrollView(proxy)
        if scrollModel.showJumpToLatest {
          JumpToLatestPill(isStreaming: chatService.isProcessing) {
            scrollModel.jumpToLatest(using: proxy, bottomID: bottomID)
          }
          .padding(.bottom, 14)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .animation(.easeOut(duration: 0.18), value: scrollModel.showJumpToLatest)
      .onChange(of: chatService.messages.count) {
        if let last = chatService.messages.last, last.role == .user {
          scrollModel.queueAnchor(for: last.id)
        }
      }
      .onChange(of: chatService.isProcessing) {
        if chatService.isProcessing {
          showWorkDetails = false
        }
      }
    }
    .onChange(of: chatService.messages.isEmpty) { _, isEmpty in
      if isEmpty {
        didAnimateWelcome = false
        resetChatFeedbackState()
        scrollModel.resetForNewConversation()
      }
    }
  }

  /// The scrollable transcript, with geometry reporting and scroll-model wiring.
  func transcriptScrollView(_ proxy: ScrollViewProxy) -> some View {
    ScrollView {
      transcript
        .background(
          GeometryReader { geometry in
            Color.clear.preference(
              key: ChatContentFrameKey.self,
              value: geometry.frame(in: .named(ChatScrollCoordinateSpace.viewport))
            )
          }
        )
        .coordinateSpace(name: ChatScrollCoordinateSpace.content)
    }
    .coordinateSpace(name: ChatScrollCoordinateSpace.viewport)
    .scrollIndicators(.automatic)
    .background(
      GeometryReader { geometry in
        Color.clear
          .onAppear { scrollModel.updateViewportHeight(geometry.size.height) }
          .onChange(of: geometry.size.height) { _, height in
            scrollModel.updateViewportHeight(height)
          }
      }
    )
    .onChatScrollWheel {
      scrollModel.noteUserGesture()
    }
    .onPreferenceChange(ChatContentFrameKey.self) { frame in
      MainActor.assumeIsolated {
        scrollModel.updateContentFrame(frame)
        scrollModel.followIfNeeded(using: proxy, bottomID: bottomID)
      }
    }
    .onPreferenceChange(ChatRowFramesKey.self) { frames in
      MainActor.assumeIsolated {
        scrollModel.updateRowFrames(frames)
        scrollModel.anchorPendingTurnIfReady(using: proxy)
        scrollModel.applyOpeningPositionIfNeeded(
          lastUserMessageID: chatService.messages.last(where: { $0.role == .user })?.id,
          using: proxy,
          bottomID: bottomID
        )
      }
    }
  }

  /// The transcript rows. Each row reports its frame so the scroll model can
  /// anchor turns, detect hidden content, and restore opening positions.
  var transcript: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Welcome message if empty
      if chatService.messages.isEmpty {
        welcomeView
      }

      // Messages
      ForEach(Array(chatService.messages.enumerated()), id: \.element.id) { index, message in
        if index == statusInsertionIndex {
          workStatusRow
        }
        transcriptRow(for: message)
      }
      if statusInsertionIndex == chatService.messages.count {
        workStatusRow
      }

      // Follow-up suggestions (show after last assistant message when not processing)
      if !chatService.isProcessing && !chatService.currentSuggestions.isEmpty {
        followUpSuggestions
          .chatRowFrame(id: "suggestions")
      }

      // Tail spacer: reserves space below the newest turn so it can anchor near
      // the top of the viewport. Doubles as the scroll target for the live edge.
      Color.clear
        .frame(height: max(1, scrollModel.tailSpacerHeight))
        .id(bottomID)
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 20)
  }

  @ViewBuilder
  var workStatusRow: some View {
    if let status = chatService.workStatus {
      WorkStatusCard(status: status, showDetails: $showWorkDetails)
        .chatRowFrame(id: "workStatus")
    }
  }

  /// One transcript row plus its anchor marker: a scroll target 64pt above a
  /// user turn, so scrolling it to .top leaves the previous turn peeking above
  /// the newly anchored message.
  func transcriptRow(for message: ChatMessage) -> some View {
    ChatMessageRow(
      message: message,
      showsAssistantFooter: shouldShowAssistantFeedbackFooter(for: message),
      selectedDirection: chatVoteSelections[message.id],
      showsThanks: thankedMessageIDs.contains(message.id),
      onCopy: { copyAssistantMessage(message) },
      onRate: { direction in handleAssistantRating(direction, for: message) }
    )
    .id(message.id)
    .chatRowFrame(id: message.id)
    .overlay(alignment: .top) {
      if message.role == .user {
        Color.clear
          .frame(height: 1)
          .offset(y: -ChatScrollModel.previousTurnPeek)
          .id(ChatAnchorMarkerID(messageID: message.id))
          .allowsHitTesting(false)
      }
    }
  }

  // MARK: - Memory Panel

  var memoryPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Notizen")
          .font(.custom("Figtree", size: 12).weight(.bold))
          .foregroundColor(Color(hex: "666666"))
        Spacer()
        Text("\(memoryCharacterCount)/\(DashboardChatMemoryStore.maxCharacters)")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "999999"))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(TaktColor.surfaceSunken)

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("Wird automatisch aus den Antworten des Assistenten aktualisiert. Du kannst es manuell bearbeiten.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(TaktColor.textMuted)

        TextEditor(text: $memoryDraft)
          .font(.custom("Figtree", size: 12))
          .padding(8)
          .background(TaktColor.surface)
          .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
          .overlay(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .stroke(TaktColor.borderGrid, lineWidth: 1)
          )
          .onChange(of: memoryDraft) { _, newValue in
            guard newValue.count > DashboardChatMemoryStore.maxCharacters else { return }
            memoryDraft = String(newValue.prefix(DashboardChatMemoryStore.maxCharacters))
          }

        HStack {
                  Text("Zuletzt aktualisiert: \(memoryUpdatedLabel)")
                    .font(.custom("Figtree", size: 10))
                    .foregroundColor(TaktColor.textTertiary)
                  Spacer()
                }

                HStack(spacing: 8) {
                  Button("Speichern") { saveMemoryDraft() }
                    .buttonStyle(.plain)
                    .font(.custom("Figtree", size: 11).weight(.bold))
                    .foregroundColor(isMemoryDirty ? TaktColor.accent : TaktColor.textTertiary)
                    .disabled(!isMemoryDirty)
                    .pointingHandCursor()

                  Button("Neu laden") { reloadMemoryDraft() }
                    .buttonStyle(.plain)
                    .font(.custom("Figtree", size: 11).weight(.bold))
                    .foregroundColor(isMemoryDirty ? TaktColor.textSecondary : TaktColor.textMuted)
                    .disabled(!isMemoryDirty)
                    .pointingHandCursor()

                  Spacer()

                  Button("Leeren") { clearMemoryDraft() }
                    .buttonStyle(.plain)
                    .font(.custom("Figtree", size: 11).weight(.bold))
                    .foregroundColor(storedMemoryBlob.isEmpty ? Color(hex: "AAAAAA") : Color(hex: "C85A4B"))
                    .disabled(storedMemoryBlob.isEmpty)
                    .pointingHandCursor()
                }
      }
      .padding(12)
    }
    .frame(width: 360)
    .background(TaktColor.surface)
    .overlay(
      Rectangle()
        .fill(TaktColor.borderGrid)
        .frame(width: 1),
      alignment: .leading
    )
  }

  // MARK: - Welcome View

  var welcomeView: some View {
    VStack(spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .fill(TaktColor.surface)
          .overlay(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .stroke(TaktColor.borderGrid, lineWidth: 1)
          )

        VStack(spacing: 16) {
          HStack(alignment: .center, spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .fill(TaktColor.accentSoft)
              Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(TaktColor.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
              Text("Frage zu deinen TAKT-Daten")
                .font(.custom("Figtree-SemiBold", size: 24))
                .foregroundColor(TaktColor.textPrimary)

              Text("Stelle Fragen, analysiere deine Timeline und erzeuge Diagramme.")
                .font(.custom("Figtree", size: 13).weight(.semibold))
                .foregroundColor(TaktColor.textSecondary)

              Text("Ich merke mir deine Antwort-Präferenzen — bring mir gerne deinen Stil bei.")
                .font(.custom("Figtree", size: 12))
                .foregroundColor(TaktColor.textTertiary)
            }

            Spacer(minLength: 0)
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("Frag mich zum Beispiel")
              .font(.custom("Figtree", size: 12).weight(.bold))
              .foregroundColor(TaktColor.textSecondary)

            ForEach(Array(welcomePrompts.enumerated()), id: \.offset) { index, prompt in
              WelcomeSuggestionRow(prompt: prompt) {
                sendMessage(prompt.text)
              }
              .opacity(didAnimateWelcome ? 1 : 0)
              .offset(y: didAnimateWelcome ? 0 : 8)
              .animation(welcomeSuggestionAnimation(at: index), value: didAnimateWelcome)
            }
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 24)
      }
      .frame(maxWidth: 760)
      .opacity(didAnimateWelcome ? 1 : 0)
      .scaleEffect(reduceMotion ? 1 : (didAnimateWelcome ? 1 : 0.985))
      .blur(radius: reduceMotion || didAnimateWelcome ? 0 : 6)
      .onAppear {
        guard !didAnimateWelcome else { return }
        withAnimation(welcomeHeroAnimation) {
          didAnimateWelcome = true
        }
      }

      Spacer(minLength: 8)
    }
    .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
    .padding(.bottom, 24)
  }

  // MARK: - Beta Lock Screen

  var betaLockScreen: some View {
    VStack(spacing: 16) {
      Spacer()

      // Header: "Unlock Beta" with BETA badge
      HStack(alignment: .top, spacing: 4) {
        Text("Chat freischalten")
          .font(.custom("Figtree-SemiBold", size: 30))
          .foregroundColor(TaktColor.textPrimary)

        Text("BETA")
          .font(.custom("Figtree-Bold", size: 11))
          .foregroundColor(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(TaktColor.accent)
          )
          .rotationEffect(.degrees(-12))
          .offset(x: -4, y: -4)
      }

      // Feature description (below title)
      VStack(spacing: 6) {
        Text(
          "Der Chat lässt dich Fragen zu deiner TAKT-Aktivität stellen und liefert Zusammenfassungen, Vergleiche und Einblicke."
        )
        .font(.custom("Figtree-Regular", size: 14))
        .foregroundColor(TaktColor.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 600)

        Text("Bitte melde Fehler oder unerwartetes Verhalten!")
          .font(.custom("Figtree-SemiBold", size: 14))
          .foregroundColor(TaktColor.textPrimary)
          .multilineTextAlignment(.center)
      }

      // Main content card
      VStack(spacing: 16) {
        // Runtime requirement section
        VStack(spacing: 12) {
          Image(
            systemName: hasChatMinimumAccess && anyRuntimeAvailable
              ? "checkmark.circle.fill"
              : "bolt.horizontal.circle"
          )
          .font(.system(size: 32))
          .foregroundColor(
            hasChatMinimumAccess && anyRuntimeAvailable
              ? TaktColor.positive : TaktColor.accent
          )
          .contentTransition(.symbolEffect(.replace))
          .animation(.easeOut(duration: 0.2), value: anyRuntimeAvailable)
          .animation(.easeOut(duration: 0.2), value: hasChatMinimumAccess)

          if !hasChatMinimumAccess {
            Text("10 Stunden Zeitverlaufsdaten erforderlich")
              .font(.custom("Figtree-SemiBold", size: 15))
              .foregroundColor(TaktColor.textPrimary)

            Text(
              "Der Chat wird freigeschaltet, sobald TAKT genug Aktivität analysiert hat. \(chatAccessProgressText)"
            )
            .font(.custom("Figtree-Regular", size: 13))
            .foregroundColor(TaktColor.textSecondary)
            .multilineTextAlignment(.center)
          } else if anyRuntimeAvailable {
            Text("LLM-Anbieter konfiguriert")
              .font(.custom("Figtree-SemiBold", size: 15))
              .foregroundColor(TaktColor.positive)
              .transition(.opacity.combined(with: .scale(scale: 0.95)))
          } else {
            Text("LLM-Anbieter erforderlich")
              .font(.custom("Figtree-SemiBold", size: 15))
              .foregroundColor(TaktColor.textPrimary)

            Text(
              "Richte deinen LLM-Anbieter unter Einstellungen → LLM-Anbieter ein."
            )
            .font(.custom("Figtree-Regular", size: 13))
            .foregroundColor(TaktColor.textSecondary)
            .multilineTextAlignment(.center)
          }
        }
        .animation(.easeOut(duration: 0.25), value: anyRuntimeAvailable)
        .animation(.easeOut(duration: 0.25), value: hasChatMinimumAccess)

        // Continue button
        Button(action: {
          refreshChatAccessProgress()
          guard hasChatMinimumAccess && anyRuntimeAvailable else { return }

          withAnimation(.easeOut(duration: 0.25)) {
            hasBetaAccepted = true
          }
        }) {
          Text(chatUnlockButtonTitle)
            .font(.custom("Figtree-SemiBold", size: 15))
            .foregroundColor(
              hasChatMinimumAccess && anyRuntimeAvailable
                ? TaktColor.textPrimary
                : TaktColor.textMuted
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .fill(
                  hasChatMinimumAccess && anyRuntimeAvailable
                    ? TaktColor.accentSoft
                    : TaktColor.surfaceSunken
                )
                .overlay(
                  RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                    .stroke(
                      hasChatMinimumAccess && anyRuntimeAvailable
                        ? TaktColor.accent.opacity(0.4)
                        : TaktColor.borderGrid,
                      lineWidth: 1
                    )
                )
            )
        }
        .buttonStyle(BetaButtonStyle(isEnabled: hasChatMinimumAccess && anyRuntimeAvailable))
        .disabled(!hasChatMinimumAccess || !anyRuntimeAvailable)
      }
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .fill(TaktColor.surface)
          .overlay(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .stroke(TaktColor.borderGrid, lineWidth: 1)
          )
      )
      .frame(maxWidth: 420)

      // Privacy Note (at bottom)
      VStack(spacing: 4) {
        Text("Datenschutz-Hinweis")
          .font(.custom("Figtree-SemiBold", size: 12))
          .foregroundColor(TaktColor.textTertiary)

        Text(
          "Während der Beta werden deine Fragen protokolliert, um das Produkt zu verbessern. Antworten werden nicht protokolliert — deine Privatsphäre bleibt gewahrt."
        )
        .font(.custom("Figtree-Regular", size: 12))
        .foregroundColor(TaktColor.textMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 600)
      }
      .padding(.top, 4)

      Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(TaktColor.surface)
  }

  var chatUnlockButtonTitle: String {
    if !hasChatMinimumAccess {
      return "Nimm weiter auf, um freizuschalten"
    }

    if !anyRuntimeAvailable {
      return "LLM-Anbieter konfigurieren"
    }

    return "Chat freischalten"
  }

  // MARK: - Input Area

  var inputArea: some View {
    VStack(spacing: 0) {
      // Text input
      AppKitComposerTextField(
        text: $inputText,
        isFocused: $isInputFocused,
        focusToken: composerFocusToken,
        placeholder: "Frage zu deinen TAKT-Daten...",
        onSubmit: submitCurrentInputIfAllowed
      )
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle()
        .fill(Color(hex: "EEE4D8"))
        .frame(height: 1)

      // Bottom toolbar
      HStack(spacing: 8) {
        Spacer()

        if chatService.isProcessing {
          HStack(spacing: 6) {
            ProgressView()
              .scaleEffect(0.55)
              .tint(TaktColor.accent)
            Text("Antwortet…")
              .font(TaktFont.ui(11, .semibold))
              .foregroundColor(TaktColor.textTertiary)
          }
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .fill(TaktColor.accentSoft)
          )
          .overlay(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .stroke(TaktColor.accent.opacity(0.35), lineWidth: 1)
          )
        }

        // Send button
        Button(action: { submitCurrentInputIfAllowed() }) {
          ZStack {
            if chatService.isProcessing {
              ProgressView()
                .scaleEffect(0.6)
                .tint(Color.white)
            } else {
              Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            }
          }
          .frame(width: 32, height: 32)
          .background(
            canSubmitCurrentInput ? TaktColor.accent : TaktColor.borderGrid
          )
          .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
        }
        .buttonStyle(PressScaleButtonStyle(isEnabled: canSubmitCurrentInput))
        .disabled(!canSubmitCurrentInput)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .frame(minHeight: 48)
    }
    .background(
      RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
        .fill(TaktColor.surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
        .stroke(composerBorderColor, lineWidth: isInputFocused ? 1.2 : TaktMetrics.hairline)
    )
    .animation(TaktMotion.stateChange, value: isInputFocused)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  /// TAKT: Der Chat nutzt den Standard-LLM-Anbieter aus den Einstellungen.
  var standardChatProvider: DashboardChatProvider {
    DashboardChatProvider.fromRoutingStore()
  }

  var statusInsertionIndex: Int? {
    guard chatService.workStatus != nil else { return nil }
    // Always show at the end (after the latest user message)
    return chatService.messages.count
  }

  // MARK: - Follow-up Suggestions

  var followUpSuggestions: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Vorschläge")
        .font(.custom("Figtree", size: 11).weight(.semibold))
        .foregroundColor(Color(hex: "999999"))

      ChatFlowLayout(spacing: 8) {
        ForEach(chatService.currentSuggestions, id: \.self) { suggestion in
          SuggestionChip(text: suggestion) {
            inputText = suggestion
            isInputFocused = true
            composerFocusToken += 1
          }
        }
      }
    }
    .padding(.top, 4)
  }

}
