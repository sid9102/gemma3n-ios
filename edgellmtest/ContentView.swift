//
//  ContentView.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/22/25.
//

import SwiftUI
import PhotosUI
struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var selectedPhotosPickerItem: PhotosPickerItem?
    @State private var selectedSwiftUIImage: Image?
    @State private var presentingPhotosPicker = false
    @State private var showingCameraPicker = false
    @State private var showingSettingsSheet = false

    var body: some View {
        Group {
            if let criticalError = viewModel.criticalError {
                VStack {
                    Spacer()
                    Text("Error")
                        .font(.headline)
                    Text(criticalError)
                        .padding()
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                chatInterfaceView
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                HStack(alignment: .center, spacing: 4) {
                    Picker("Model", selection: $viewModel.selectedModelIdentifier) {
                        ForEach(viewModel.availableModels) { modelId in
                            Text(modelId.displayName).tag(modelId)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.availableModels.count <= 1 || viewModel.isModelLoading)
                    
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.medium)
                    }
                    .disabled(viewModel.isModelLoading)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    viewModel.clearChat()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.isModelLoading)
            }
        }
        .onAppear {
        }
        .onChange(of: viewModel.selectedModelIdentifier) {
            Task {
                await viewModel.switchModel(to: viewModel.selectedModelIdentifier)
            }
        }
        .onChange(of: selectedPhotosPickerItem) {
            Task {
                if let data = try? await selectedPhotosPickerItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedSwiftUIImage = Image(uiImage: uiImage)
                    viewModel.setSelectedImage(uiImage: uiImage)
                } else {

                    if selectedPhotosPickerItem == nil {
                        selectedSwiftUIImage = nil
                        viewModel.setSelectedImage(uiImage: nil)
                    }
                }
            }
        }

        .onChange(of: viewModel.selectedUIImage) { oldValue, newValue in
            if newValue == nil {
                selectedSwiftUIImage = nil
                selectedPhotosPickerItem = nil
            }
        }

        .photosPicker(
            isPresented: $presentingPhotosPicker,
            selection: $selectedPhotosPickerItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .sheet(isPresented: $showingSettingsSheet) {
            InferenceSettingsView(viewModel: viewModel)
        }
    }

    // Extracted main chat interface to a new computed property
    private var chatInterfaceView: some View {
        VStack(spacing: 0) {
            // Show the stats block once model init time is available and no critical error.
            if viewModel.modelInitializationTime > 0 && viewModel.criticalError == nil {
                statsDisplayView
            }
            chatMessagesView
                .padding(.bottom, 10)
            inputAreaView
        }
    }

    // MARK: - Chat Messages View
    private var chatMessagesView: some View {
        AutoScrollingScrollView(messages: $viewModel.messages, isAutoScrollEnabled: $viewModel.isAutoScrollEnabled) {
            // The content for AutoScrollingScrollView is what was previously in chatContentView
            Group {
                if shouldShowLoadingView {
                    loadingView
                } else {
                    messagesListView
                }
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
                .id(message.id)
            }
        }
        .padding(.horizontal)
        .padding(.top, 15)
        .padding(.bottom, 15)
    }

    private func isMessageThinking(_ message: Message) -> Bool {
        return viewModel.isThinking &&
            message == viewModel.messages.last &&
            !message.isUserMessage
    }

    // MARK: - Input Area View
    private var inputAreaView: some View {
        VStack(spacing: 5) {
            if let selectedImage = selectedSwiftUIImage {
                ZStack(alignment: .topTrailing) {
                    selectedImage
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .cornerRadius(8)
                    
                    Button {
                        selectedPhotosPickerItem = nil
                        selectedSwiftUIImage = nil
                        viewModel.setSelectedImage(uiImage: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .padding(4)

                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            HStack {
                Menu {
                    Button {
                        presentingPhotosPicker = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.stack")
                    }
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showingCameraPicker = true
                        } else {
                            print("Camera not available on this device.")
                        }
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .padding(.leading, 5)

                messageTextField
                sendButton
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .shadow(radius: 1)
        .opacity(viewModel.isModelLoading ? 0.5 : 1.0)
        .sheet(isPresented: $showingCameraPicker) {
            ImagePicker(selectedImage: Binding(
                get: { viewModel.selectedUIImage }, // Read from ViewModel
                set: { newImage in // Write to ViewModel and update local UI
                    viewModel.setSelectedImage(uiImage: newImage)
                    if let uiImg = newImage {
                        selectedSwiftUIImage = Image(uiImage: uiImg)
                    } else {
                        selectedSwiftUIImage = nil
                    }
                }
            ), sourceType: .camera)
        }
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
        Group {
            if viewModel.isThinking {
                Button(action: {
                    viewModel.stopGeneration()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red) // Or another color to indicate "stop"
                }
                .disabled(viewModel.isModelLoading) // Only disable if model is loading, allow stopping otherwise
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                .disabled(isSendButtonDisabled)
            }
        }
    }

    private var isSendButtonDisabled: Bool {
        // isThinking is now handled by the button's visual state, so remove it from here
        let hasContent = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedUIImage != nil
        return !hasContent || viewModel.isModelLoading
    }

    // MARK: - Helper Methods
    private func sendMessage() {
        viewModel.sendMessage(viewModel.inputText)
        isInputFocused = false
    }

    // MARK: - Stats Display View
    private var statsDisplayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Loading:")
                    .font(.caption.weight(.semibold))
                Text(String(format: "Initialization Time: %.3f s", viewModel.modelInitializationTime))
                    .font(.caption)
            }

            // Last Response Section
            if viewModel.showStats {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Response:")
                        .font(.caption.weight(.semibold))
                    Text("Tokens: \(viewModel.lastResponseTokenCount)")
                        .font(.caption)
                    Text(String(format: "Engine Inference Time: %.3f s", viewModel.lastResponseLibraryTime))
                        .font(.caption)
                    Text(String(format: "Tokens/sec (Engine): %.2f", viewModel.lastResponseTokensPerSecond))
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 5)
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
            if let uiImage = message.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(10)
                    .padding(.bottom, message.content.isEmpty ? 0 : 6)
            }

            if !message.content.isEmpty || shouldShowThinkingBubble {
                 messageBubble
            }
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
