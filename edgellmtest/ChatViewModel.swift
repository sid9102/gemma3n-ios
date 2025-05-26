//
//  ChatViewModel.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/25/25.
//

import Foundation
import Combine

// Message model to represent chat messages
struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isUserMessage: Bool
    let timestamp = Date()
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var currentSvgContent: String = ""

    private var model: OnDeviceModel?
    private var chat: Chat?

    // Initialize the model and chat when the view model is created
    func initialize() async {
        do {
            model = try OnDeviceModel()
            chat = try Chat(model: model!)
            // Add a welcome message
            messages.append(Message(content: "Hello! How can I help you today?", isUserMessage: false))
        } catch {
            messages.append(Message(content: "Error initializing chat: \(error.localizedDescription)", isUserMessage: false))
        }
    }

    // Start chat with initial setup
    func startChat() {
        Task {
            await initialize()
        }
    }

    // Helper function to clean up JSON wrapped in code blocks
    private func cleanupJsonResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it starts with ```json or ``` and ends with ```
        if (trimmed.hasPrefix("```json") || trimmed.hasPrefix("```")) && trimmed.hasSuffix("```") {
            var cleaned = trimmed

            // Remove the opening code block marker
            if cleaned.hasPrefix("```json") {
                cleaned = String(cleaned.dropFirst(7)) // Remove "```json"
            } else if cleaned.hasPrefix("```") {
                cleaned = String(cleaned.dropFirst(3)) // Remove "```"
            }

            // Remove the closing code block marker
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)) // Remove "```"
            }

            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Return original if it doesn't match the pattern
        return response
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

                // Clean up the response to handle code block wrappers
                let cleanedResponse = cleanupJsonResponse(fullResponse)

                // Parse the JSON response
                if let jsonData = cleanedResponse.data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            // Extract the response text
                            if let responseText = json["response"] as? String {
                                // Update the message with the parsed response text
                                if responseIndex < messages.count {
                                    messages[responseIndex] = Message(content: responseText, isUserMessage: false)
                                }

                                // Extract and update SVG content if present
                                if let svgContent = json["svg"] as? String {
                                    currentSvgContent = svgContent
                                }
                            }
                        }
                    } catch {
                        print("Error parsing JSON: \(error.localizedDescription)")
                        // If JSON parsing fails, keep the original response as is
                        // This handles cases where the response might not be valid JSON
                        if responseIndex < messages.count {
                            messages[responseIndex] = Message(content: cleanedResponse, isUserMessage: false)
                        }
                    }
                } else {
                    print("Could not convert response to data")
                    // Fallback to showing the cleaned response
                    if responseIndex < messages.count {
                        messages[responseIndex] = Message(content: cleanedResponse, isUserMessage: false)
                    }
                }
            } catch {
                messages.append(Message(content: "Error: \(error.localizedDescription)", isUserMessage: false))
            }
        }
    }
}