import SwiftUI

struct InferenceSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("LLM Session Options")) {
                    Stepper("Top-K: \(viewModel.topK)", value: $viewModel.topK, in: 1...100)
                    
                    HStack {
                        Text("Top-P: \(String(format: "%.2f", viewModel.topP))")
                        Slider(value: $viewModel.topP, in: 0.0...1.0, step: 0.01)
                    }
                    
                    HStack {
                        Text("Temperature: \(String(format: "%.2f", viewModel.temperature))")
                        Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.01)
                    }
                    
                    Toggle("Enable Vision Modality", isOn: $viewModel.enableVisionModality)
                }
                
                Section(header: Text("UI Settings")) {
                    Toggle("Enable Auto-Scroll", isOn: $viewModel.isAutoScrollEnabled)
                }

                Section {
                    Button("Apply and Reset Chat") {
                        viewModel.applyInferenceSettingsAndReinitializeChat()
                        dismiss()
                    }
                    .disabled(viewModel.isApplyingSettings)
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        viewModel.resetInferenceAndUISettingsToDefaults()
                        dismiss()
                    }
                    .disabled(viewModel.isApplyingSettings) // Also disable if settings are being applied from another action
                }
            }
            .navigationTitle("Inference Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    InferenceSettingsView(viewModel: ChatViewModel())
}