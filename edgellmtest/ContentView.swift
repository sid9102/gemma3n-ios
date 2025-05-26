//
//  ContentView.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/22/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatMessagesView
            inputAreaView
        }
        .onAppear {
            viewModel.startChat()
        }
    }

    // MARK: - Chat Messages View
    private var chatMessagesView: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                chatContentView
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        scrollView.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
                    }
                }
            }
        }
    }

    private var chatContentView: some View {
        Group {
            if shouldShowLoadingView {
                loadingView
            } else {
                messagesListView
            }
        }
    }

    private var shouldShowLoadingView: Bool {
        viewModel.isModelLoading && viewModel.messages.isEmpty
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(2.0)
                .padding()
            Text("Loading model...")
                .font(.headline)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messagesListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.messages) { message in
                MessageBubble(
                    message: message,
                    isThinking: isMessageThinking(message)
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func isMessageThinking(_ message: Message) -> Bool {
        return viewModel.isThinking &&
            message == viewModel.messages.last &&
            !message.isUserMessage
    }

    // MARK: - Input Area View
    private var inputAreaView: some View {
        HStack {
            messageTextField
            sendButton
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .shadow(radius: 1)
        .opacity(viewModel.isModelLoading ? 0.5 : 1.0)
    }

    private var messageTextField: some View {
        TextField("Type a message...", text: $viewModel.inputText)
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .focused($isInputFocused)
        .submitLabel(.send)
        .onSubmit {
            sendMessage()
        }
        .disabled(viewModel.isModelLoading)
    }

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(.blue)
        }
        .disabled(isSendButtonDisabled)
    }

    private var isSendButtonDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            viewModel.isModelLoading
    }

    // MARK: - Helper Methods
    private func sendMessage() {
        viewModel.sendMessage(viewModel.inputText)
        isInputFocused = false
    }
}

// MARK: - Message Bubble Component
struct MessageBubble: View {
    let message: Message
    var isThinking: Bool = false

    var body: some View {
        HStack {
            if message.isUserMessage {
                Spacer()
            }

            messageContent

            if !message.isUserMessage {
                Spacer()
            }
        }
    }

    private var messageContent: some View {
        VStack(alignment: messageAlignment, spacing: 4) {
            messageBubble
            timestampView
        }
    }

    private var messageAlignment: HorizontalAlignment {
        message.isUserMessage ? .trailing : .leading
    }

    private var messageBubble: some View {
        Group {
            if shouldShowThinkingBubble {
                thinkingBubble
            } else {
                regularMessageBubble
            }
        }
    }

    private var shouldShowThinkingBubble: Bool {
        isThinking && message.content == "thinking..."
    }

    private var thinkingBubble: some View {
        HStack {
            Text(message.content)
            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(12)
        .background(Color(.systemGray5))
        .foregroundColor(.primary)
        .cornerRadius(16)
        .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])
    }

    private var regularMessageBubble: some View {
        Text(message.content)
            .padding(12)
            .background(messageBubbleBackground)
            .foregroundColor(messageBubbleForeground)
            .cornerRadius(16)
            .cornerRadius(16, corners: messageBubbleCorners)
    }

    private var messageBubbleBackground: Color {
        message.isUserMessage ? Color.blue : Color(.systemGray5)
    }

    private var messageBubbleForeground: Color {
        message.isUserMessage ? .white : .primary
    }

    private var messageBubbleCorners: UIRectCorner {
        message.isUserMessage ?
            [.topLeft, .topRight, .bottomLeft] :
            [.topLeft, .topRight, .bottomRight]
    }

    private var timestampView: some View {
        Text(formatTimestamp(message.timestamp))
            .font(.caption2)
            .foregroundColor(.gray)
            .padding(.horizontal, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ContentView()
}