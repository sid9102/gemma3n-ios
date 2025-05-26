# EdgeLLM Test

EdgeLLM Test is an iOS application that demonstrates on-device Large Language Model (LLM) inference using the Gemma 3 4B model. The app provides a chat interface where users can interact with the LLM running entirely on their device, without requiring an internet connection.

## Features

- **On-Device LLM**: Runs the Gemma 3 4B model locally on iOS devices
- **Real-time Chat Interface**: Clean, intuitive chat UI with message bubbles
- **Streaming Responses**: See the AI's response as it's being generated
- **No Internet Required**: All processing happens on-device for privacy and offline use

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- CocoaPods

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/edgellmtest.git
   cd edgellmtest
   ```

2. Install dependencies using CocoaPods:
   ```bash
   pod install
   ```

3. Open the workspace in Xcode:
   ```bash
   open edgellmtest.xcworkspace
   ```
4. Download the Gemma 4B file from [here](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/tree/main) or the 2B file from [here](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/tree/main). Drop the file into the edgellmtest folder and then update the filename in `LlmInference.swift` to match the downloaded file name.
5. Build and run the project on your iOS device or simulator.

## Project Structure

- **ContentView.swift**: Main UI of the application with chat interface
- **ChatViewModel.swift**: Manages the chat state and interaction with the LLM
- **LlmInference.swift**: Handles the integration with MediaPipe and model inference
- 
## Dependencies

- **MediaPipeTasksGenAI**: Google's MediaPipe framework for on-device AI
- **MediaPipeTasksGenAIC**: C implementation of MediaPipe tasks for GenAI

## Usage

1. Launch the app on your iOS device
2. Wait for the model to load (this may take a few moments on first launch)
3. Type your message in the text field at the bottom
4. Tap the send button or press return to send your message
5. Watch as the AI generates a response in real-time

## Development

To modify the model parameters:
- Edit the `Chat` class in `LlmInference.swift` to adjust parameters like temperature, top-k, and top-p
- The default settings are:
  - temperature: 0.9
  - top-k: 40
  - top-p: 0.9
  - max tokens: 1000

## License

[Include license information here]

## Acknowledgements

- Google's MediaPipe team for the on-device LLM inference capabilities
- The Gemma model team for creating the open-source LLM used in this project