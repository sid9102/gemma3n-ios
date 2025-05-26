//
//  ChatViewModel.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/25/25.
//


import Foundation
import Combine
import UIKit
import SwiftUI

/// Represents a single message in the chat, including content, sender, timestamp, and an optional image.
struct Message: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUserMessage: Bool
    let timestamp = Date()
    let uiImage: UIImage? // Optional image for the message

    
    init(content: String, isUserMessage: Bool, uiImage: UIImage? = nil) {
        self.content = content
        self.isUserMessage = isUserMessage
        self.uiImage = uiImage

    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUserMessage == rhs.isUserMessage && lhs.timestamp == rhs.timestamp && lhs.uiImage == rhs.uiImage
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isModelLoading: Bool = true
    @Published var isThinking: Bool = false

    @Published var modelInitializationTime: Double = 0.0
    @Published var lastResponseTokenCount: Int = 0
    @Published var lastResponseLibraryTime: Double = 0.0 // For library's responseGenerationTimeInSeconds
    @Published var lastResponseTokensPerSecond: Double = 0.0 // Will use libraryTime for this
    @Published var showStats: Bool = false // To control visibility of the "Last Response" section
    @Published var selectedUIImage: UIImage?
    /// Stores a critical error message if model initialization fails
    @Published public var criticalError: String?
    @Published public var isApplyingSettings: Bool = false // For disabling UI during settings application

    // MARK: - Model Switching State
    /// List of models found in the app bundle.
    @Published public var availableModels: [ModelIdentifier] = []
    /// Persisted preference for the selected model identifier's raw value.
    @AppStorage("selectedModelIdentifierRawValue") private var selectedModelIdentifierRawValue: String = ModelIdentifier.gemma2B.rawValue // Default preference to 2B
    
    /// The currently selected model identifier, derived from `@AppStorage`.
    public var selectedModelIdentifier: ModelIdentifier {
        get { ModelIdentifier(rawValue: selectedModelIdentifierRawValue) ?? .gemma2B }
        set { selectedModelIdentifierRawValue = newValue.rawValue }
    }

    // MARK: - Inference Settings (Session Options)
    @AppStorage("inferenceTopK_v1") public var topK: Int = 40
    @AppStorage("inferenceTopP_v1") public var topP: Double = 0.9 // Store as Double
    @AppStorage("inferenceTemperature_v1") public var temperature: Double = 0.9 // Store as Double
    @AppStorage("inferenceEnableVisionModality_v1") public var enableVisionModality: Bool = true

    // MARK: - UI Settings
    @AppStorage("uiIsAutoScrollEnabled_v1") public var isAutoScrollEnabled: Bool = true
    
    // MARK: - Private LLM State
    private var currentOnDeviceModel: OnDeviceModel?
    private var currentChat: Chat?
    private var generationTask: Task<Void, Error>? // Task for managing LLM response generation
    
    // MARK: - Initialization
    init() {
        self.availableModels = ModelIdentifier.availableInBundle()

        if availableModels.isEmpty {
            let noModelsErrorMessage = "Critical Error: No LLM models found in the app bundle. Please ensure model files (e.g., *.task) are correctly added to the project."
            NSLog(noModelsErrorMessage)
            criticalError = noModelsErrorMessage
            isModelLoading = false
            return
        }

        var initialModelToLoad = ModelIdentifier.gemma2B // Default desired model

        // Determine the actual initial model based on availability and preference
        let preferredModelFromStorage = ModelIdentifier(rawValue: selectedModelIdentifierRawValue)
        if let prefModel = preferredModelFromStorage, availableModels.contains(prefModel) {
            initialModelToLoad = prefModel
        } else if availableModels.contains(.gemma2B) {
            initialModelToLoad = .gemma2B
        } else if let firstAvailable = availableModels.first {
            initialModelToLoad = firstAvailable
        }
        
        self.selectedModelIdentifier = initialModelToLoad

        Task {
            await loadAndInitializeModel(identifier: initialModelToLoad)
        }
    }

    /// Loads and initializes the specified LLM model and chat session.
    /// This is an async operation that updates loading states and messages.
    private func loadAndInitializeModel(identifier: ModelIdentifier) async {
        isModelLoading = true
        messages.removeAll()
        criticalError = nil // Clear any previous critical error
        
        // Provide immediate feedback that loading has started
        messages.append(Message(content: "Initializing \(identifier.displayName)... Please wait.", isUserMessage: false))

        do {
            NSLog("Attempting to load model: \(identifier.displayName)")
            currentOnDeviceModel = try OnDeviceModel(modelIdentifier: identifier)
            currentChat = try Chat(model: currentOnDeviceModel!,
                                   topK: self.topK,
                                   topP: Float(self.topP), // Cast to Float
                                   temperature: Float(self.temperature), // Cast to Float
                                   enableVisionModality: self.enableVisionModality)
            
            messages.removeAll() // Clear "Initializing..." message
            messages.append(Message(content: "Model \(identifier.displayName) loaded. Hello! How can I help?", isUserMessage: false))
            
            if let modelMetrics = self.currentOnDeviceModel?.inference.metrics {
                self.modelInitializationTime = modelMetrics.initializationTimeInSeconds
                NSLog("\(identifier.displayName) initialization time: \(self.modelInitializationTime)s")
            }
        } catch {
            let loadErrorMessage = "Error initializing \(identifier.displayName): \(error.localizedDescription)"
            NSLog(loadErrorMessage)
            messages.removeAll() // Clear "Initializing..." message
            messages.append(Message(content: loadErrorMessage, isUserMessage: false))
            criticalError = loadErrorMessage // Set critical error to be displayed by ContentView
        }
        
        // Reset states after loading attempt
        isModelLoading = false
        isThinking = false
        showStats = false // Stats are for responses, not initial load
        clearSelectedImage()
        inputText = ""
    }

    // Send a message from the user to the LLM
    func sendMessage(_ text: String) {
        // Capture the image before clearing inputText or starting the async task
        let imageToSend = selectedUIImage
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageToSend != nil else { return }

        let userMessage = Message(content: text, isUserMessage: true, uiImage: imageToSend)
        messages.append(userMessage)

        // Clear input field and selected image *after* capturing them and creating the message
        inputText = ""
        clearSelectedImage() // This will set selectedUIImage to nil

        // Send message to LLM and process response
        // Cancel any existing generation task before starting a new one
        generationTask?.cancel()

        generationTask = Task {
            defer {
                // Ensure isThinking is reset and task is cleared when the task finishes or is cancelled
                Task { @MainActor in
                    self.isThinking = false
                    self.generationTask = nil
                }
            }
            do {
                // Check for cancellation before proceeding
                try Task.checkCancellation()
                
                guard let chat = currentChat else {
                    let chatNotReadyMessage = "Chat session is not ready. The selected model might be loading or failed to initialize."
                    NSLog(chatNotReadyMessage)
                    messages.append(Message(content: chatNotReadyMessage, isUserMessage: false))
                    isThinking = false // Ensure thinking indicator is off
                    return
                }

                // Add a placeholder for the AI response
                let responseIndex = messages.count
                messages.append(Message(content: "thinking...", isUserMessage: false))
                isThinking = true

                // Reset response-specific stats
                self.lastResponseTokenCount = 0
                self.lastResponseLibraryTime = 0.0
                self.lastResponseTokensPerSecond = 0.0
                self.showStats = false // Reset for the new response

                // Add image to query if present
                if let capturedImage = imageToSend, let cgImage = capturedImage.cgImage {
                    try chat.addImageToQuery(image: cgImage)
                }

                // Get response stream from LLM
                // Pass the text part of the message. If only an image was sent, text might be empty.
                let stream = try await chat.sendMessage(text)
                var fullResponse = ""

                // Process each chunk of the response
                for try await chunk in stream {
                    try Task.checkCancellation() // Check for cancellation within the loop
                    fullResponse += chunk
                    // Update the placeholder message with the accumulated response
                    if responseIndex < messages.count {
                        messages[responseIndex] = Message(content: fullResponse, isUserMessage: false)
                    }
                }
                

                // Only proceed with stats calculation if not cancelled
                try Task.checkCancellation()

                if let chat = self.currentChat { // Use currentChat
                    if !fullResponse.isEmpty {
                        do {
                            self.lastResponseTokenCount = try chat.sizeInTokens(text: fullResponse)
                        } catch {
                            print("Error getting token count: \(error.localizedDescription)")
                            self.lastResponseTokenCount = 0
                        }
                    }
                    // Get the library's reported generation time
                    if let libraryTime = chat.getLastResponseGenerationTime() {
                         self.lastResponseLibraryTime = libraryTime
                    } else {
                         self.lastResponseLibraryTime = 0 // Or handle error/nil case
                    }
                } else {
                    // Ensure values are zeroed if chat is not available
                    self.lastResponseTokenCount = 0
                    self.lastResponseLibraryTime = 0
                }

                // Calculate Tokens/sec using the library's reported time
                if self.lastResponseLibraryTime > 0 && self.lastResponseTokenCount > 0 {
                    self.lastResponseTokensPerSecond = Double(self.lastResponseTokenCount) / self.lastResponseLibraryTime
                } else {
                    self.lastResponseTokensPerSecond = 0.0
                }
                self.showStats = true // Make the "Last Response" stats section visible
            } catch is CancellationError {
                NSLog("Generation was cancelled.")
                // Message will remain as it was when stopped.
                // isThinking is handled by the defer block.
                self.showStats = false
            } catch {
                let sendMessageError = "Error during message processing: \(error.localizedDescription)"
                NSLog(sendMessageError)
                messages.append(Message(content: sendMessageError, isUserMessage: false))
                // isThinking is handled by the defer block
                self.showStats = false // Ensure stats are not shown on error
            }
        }
    }

    /// Cancels the ongoing LLM response generation, if any.
    public func stopGeneration() {
        generationTask?.cancel()
        // isThinking will be reset by the defer block in the generationTask
        NSLog("Stop generation requested.")
    }

    // MARK: - Image Handling
    func setSelectedImage(uiImage: UIImage?) {
        self.selectedUIImage = uiImage
    }

    func clearSelectedImage() {
        self.selectedUIImage = nil
    }

    // MARK: - Chat Management
    func clearChat() {
        generationTask?.cancel() // Cancel any ongoing generation
        messages.removeAll()
        
        // Re-initialize the chat session to clear LLM context
        if let model = self.currentOnDeviceModel { // Use currentOnDeviceModel
            do {
                self.currentChat = try Chat(model: model,
                                            topK: self.topK,
                                            topP: Float(self.topP), // Cast to Float
                                            temperature: Float(self.temperature), // Cast to Float
                                            enableVisionModality: self.enableVisionModality)
                messages.append(Message(content: "Chat context cleared. Ready for new conversation with \(model.identifier.displayName).", isUserMessage: false))
            } catch {
                let clearChatErrorMessage = "Error re-initializing chat session after clearing: \(error.localizedDescription)"
                NSLog(clearChatErrorMessage)
                messages.append(Message(content: clearChatErrorMessage, isUserMessage: false))
            }
        } else {
            messages.append(Message(content: "Cannot clear chat: No model loaded.", isUserMessage: false))
        }
        // Reset UI states
        isThinking = false
        showStats = false // Hide stats as there's no "last response"
        clearSelectedImage() // Clear any selected image
        inputText = "" // Clear input text
    }

    // MARK: - Model Switching
    public func switchModel(to newIdentifier: ModelIdentifier) async {
        if newIdentifier == self.selectedModelIdentifier && currentOnDeviceModel != nil && currentOnDeviceModel?.identifier == newIdentifier {
            if currentOnDeviceModel != nil {
                 print("Model \(newIdentifier.displayName) is already loaded.")
                 return
            }
        }

        print("Switching model to: \(newIdentifier.displayName)")
        self.selectedModelIdentifier = newIdentifier // This updates @AppStorage
        
        generationTask?.cancel() // Cancel any ongoing generation

        // Clear all chat-related states before loading new model
        messages.removeAll()
        isThinking = false
        showStats = false
        modelInitializationTime = 0.0 // Reset this as a new model is loading
        lastResponseTokenCount = 0
        lastResponseLibraryTime = 0.0
        lastResponseTokensPerSecond = 0.0
        clearSelectedImage()
        inputText = ""

        currentChat = nil // Release old chat session
        currentOnDeviceModel = nil // Release old model instance
        
        // loadAndInitializeModel will set isModelLoading, clear messages, and show loading message.
        await loadAndInitializeModel(identifier: newIdentifier)
    }

    // MARK: - Inference Settings Management
    /// Re-initializes the chat session with the current inference settings.
    /// This will clear the current chat history as the LLM context changes.
    public func applyInferenceSettingsAndReinitializeChat() {
        isApplyingSettings = true // Indicate settings application has started
        defer { isApplyingSettings = false } // Ensure this is reset

        generationTask?.cancel() // Cancel any ongoing generation
        messages.removeAll()
        isThinking = false
        showStats = false
        clearSelectedImage()
        inputText = ""

        guard let model = self.currentOnDeviceModel else {
            let noModelErrorMessage = "Cannot apply settings: No model loaded."
            NSLog(noModelErrorMessage)
            messages.append(Message(content: noModelErrorMessage, isUserMessage: false))
            // Potentially set criticalError if this state is problematic
            return
        }

        do {
            self.currentChat = try Chat(model: model,
                                        topK: self.topK,
                                        topP: Float(self.topP), // Cast to Float
                                        temperature: Float(self.temperature), // Cast to Float
                                        enableVisionModality: self.enableVisionModality)
            messages.append(Message(content: "Inference settings applied. Chat context reset. Ready for new conversation with \(model.identifier.displayName).", isUserMessage: false))
            NSLog("Inference settings applied. topK: \(self.topK), topP: \(self.topP), temp: \(self.temperature), vision: \(self.enableVisionModality)")
        } catch {
            let applySettingsErrorMessage = "Error applying inference settings: \(error.localizedDescription)"
            NSLog(applySettingsErrorMessage)
            messages.append(Message(content: applySettingsErrorMessage, isUserMessage: false))
            // Potentially set criticalError
        }
    }

    public func resetInferenceAndUISettingsToDefaults() {
        NSLog("Resetting all settings to defaults.")
        // Reset inference settings
        topK = 40
        topP = 0.9
        temperature = 0.9
        enableVisionModality = true

        // Reset UI settings
        isAutoScrollEnabled = true
        
        applyInferenceSettingsAndReinitializeChat()
        

    }
}
