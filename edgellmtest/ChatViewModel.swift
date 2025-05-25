//
//  ChatViewModel.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/25/25.
//


import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var responseText: String = "Hello, world!"
    
    func startChat() {
        Task.detached(priority: .userInitiated) {
            do {
                let model = try OnDeviceModel()
                let chat = try Chat(model: model)
                let stream = try await chat.sendMessage("Give me well formatted JSON for two recipes, one for artichokes (grilled) and one for  a butter based dip involving garlic greens. Make sure to include steps for how to keep the dip from solidifying at room temperature. Your output should be only a JSON list with two elements, one element per recipe. Ensure that the JSON structure is consistent across both elements.")
                
                for try await chunk in stream {
                    await MainActor.run {
                        self.responseText += chunk
                    }
                }
            } catch {
                await MainActor.run {
                    self.responseText = "Error: \(error)"
                }
            }
        }
    }

}

