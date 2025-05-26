//
//  ChatViewModel.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/25/25.
//


import Foundation
import Combine

// Message model to represent chat messages
struct Message: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUserMessage: Bool
    let timestamp = Date()
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isModelLoading: Bool = true
    @Published var isThinking: Bool = false

    private var model: OnDeviceModel?
    private var chat: Chat?

    // Initialize the model and chat when the view model is created
    func initialize() async {
        isModelLoading = true
        do {
            model = try OnDeviceModel()
            chat = try Chat(model: model!)
            // Add a welcome message
            messages.append(Message(content: "Hello! How can I help you today?", isUserMessage: false))
        } catch {
            messages.append(Message(content: "Error initializing chat: \(error.localizedDescription)", isUserMessage: false))
        }
        isModelLoading = false
    }

    // Start chat with initial setup
    func startChat() {
        Task {
            await initialize()
        }
    }

    // Send a message from the user to the LLM
    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Add user message to the chat
        let userMessage = Message(content: text, isUserMessage: true)
        messages.append(userMessage)

        // Clear input field
        inputText = ""

        // Send message to LLM and process response
        Task {
            do {
                guard let chat = chat else {
                    messages.append(Message(content: "Chat not initialized", isUserMessage: false))
                    return
                }

                // Add a placeholder for the AI response
                let responseIndex = messages.count
                messages.append(Message(content: "thinking...", isUserMessage: false))
                isThinking = true

                // Get response stream from LLM
                let stream = try await chat.sendMessage(text)
                var fullResponse = ""

                // Process each chunk of the response
                for try await chunk in stream {
                    fullResponse += chunk
                    // Update the placeholder message with the accumulated response
                    if responseIndex < messages.count {
                        messages[responseIndex] = Message(content: fullResponse, isUserMessage: false)
                    }
                }

                isThinking = false
            } catch {
                messages.append(Message(content: "Error: \(error.localizedDescription)", isUserMessage: false))
                isThinking = false
            }
        }
    }
}
