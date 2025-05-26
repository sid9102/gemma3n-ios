//
//  LlmInference.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/23/25.
//

import MediaPipeTasksGenAI
import Foundation
import ZIPFoundation
import CoreGraphics // For CGImage

/// Represents the available LLM models, their bundled filenames, and display names.
public enum ModelIdentifier: String, CaseIterable, Identifiable {
    case gemma2B = "gemma-3n-E2B-it-int4"
    case gemma4B = "gemma-3n-E4B-it-int4"

    public var id: String { self.rawValue }
    public var fileName: String { "\(self.rawValue).task" }
    
    public var displayName: String {
        switch self {
        case .gemma2B: return "Gemma 3N (2B)"
        case .gemma4B: return "Gemma 3N (4B)"
        }
    }

    /// Checks which of the defined models are actually present in the app's main bundle.
    /// - Returns: An array of `ModelIdentifier` cases that have corresponding `.task` files in the bundle.
    public static func availableInBundle() -> [ModelIdentifier] {
        return ModelIdentifier.allCases.filter { modelId in
            Bundle.main.path(forResource: modelId.rawValue, ofType: "task") != nil
        }
    }
}

/// Manages the on-device LLM, including its initialization, model file handling, and vision component extraction.
struct OnDeviceModel {
    private(set) var inference: LlmInference
    let identifier: ModelIdentifier // Identifier for the loaded model (e.g., 2B or 4B)
    
    /// Initializes the `OnDeviceModel` with the specified `ModelIdentifier`.
    /// This involves copying the model `.task` file from the bundle to a cache directory,
    /// extracting necessary vision components from the `.task` file, and setting up
    /// the `LlmInference.Options`.
    ///
    /// - Parameter modelIdentifier: The identifier of the model to load.
    /// - Throws: An error if the model file is not found in the bundle, if copying/extraction fails,
    ///           or if `LlmInference` initialization fails.
    init(modelIdentifier: ModelIdentifier) throws {
        self.identifier = modelIdentifier
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)

        // Use modelIdentifier to get the correct model file
        guard let bundleModelPath = Bundle.main.path(forResource: modelIdentifier.rawValue, ofType: "task") else {
            let errorMessage = "Critical Error: Model file '\(modelIdentifier.fileName)' not found in the app bundle. Please ensure it's added to the project and target."
            NSLog(errorMessage)
            throw NSError(domain: "ModelSetupError", code: 1001, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        let modelCopyPath = cacheDir.appendingPathComponent(modelIdentifier.fileName)
        
        NSLog("Selected model: \(modelIdentifier.displayName)")
        NSLog("Bundle path: \(bundleModelPath)")
        NSLog("Cache path: \(modelCopyPath.path)")

        if !FileManager.default.fileExists(atPath: modelCopyPath.path) {
            try FileManager.default.copyItem(atPath: bundleModelPath, toPath: modelCopyPath.path)
        }

        // Define internal filenames for vision components expected within the .task archive
        let visionEncoderFileName = "TF_LITE_VISION_ENCODER" // Assumed internal name for the vision encoder
        let visionAdapterFileName = "TF_LITE_VISION_ADAPTER" // Assumed internal name for the vision adapter

        let extractedVisionEncoderPath = cacheDir.appendingPathComponent(visionEncoderFileName)
        let extractedVisionAdapterPath = cacheDir.appendingPathComponent(visionAdapterFileName)

        // Extract vision models if they don't already exist in the cache
        if !fileManager.fileExists(atPath: extractedVisionEncoderPath.path) ||
           !fileManager.fileExists(atPath: extractedVisionAdapterPath.path) {
            NSLog("Extracting vision models from .task file...")
            do {
                try OnDeviceModel.extractVisionModels( // Call as a static method
                    fromArchive: modelCopyPath,
                    toDirectory: cacheDir,
                    filesToExtract: [visionEncoderFileName, visionAdapterFileName]
                )
                NSLog("Successfully extracted vision models.")
            } catch {
                let extractionErrorMessage = "Error extracting vision components from '\(modelCopyPath.lastPathComponent)': \(error.localizedDescription). Vision features may not work."
                NSLog(extractionErrorMessage)
                // For now, we log the error and continue. If visionEncoderPath or visionAdapterPath
                // are invalid as a result, LlmInference initialization might fail if vision is strictly required,
                // or it might proceed with vision disabled if the main model can run without them.
                // Consider re-throwing if vision components are absolutely mandatory for all operations:
                // throw NSError(domain: "ModelSetupError", code: 1002, userInfo: [NSLocalizedDescriptionKey: extractionErrorMessage, NSUnderlyingErrorKey: error])
            }
        } else {
            NSLog("Vision models already exist in cache.")
        }


        let options = LlmInference.Options(modelPath: modelCopyPath.path)
        options.maxTokens = 1000

        // Configure options for vision modality.
        // These paths must point to the extracted model files in the cache directory.
        options.visionEncoderPath = extractedVisionEncoderPath.path
        options.visionAdapterPath = extractedVisionAdapterPath.path
        options.maxImages = 1 // Initial support for single image

        inference = try LlmInference(options: options)
    }

    /// Extracts specified files from a zip archive (the .task file) to a destination directory.
    /// This is primarily used for extracting vision model components.
    private static func extractVisionModels(fromArchive archiveURL: URL, toDirectory destinationURL: URL, filesToExtract: [String]) throws {
        let fileManager = FileManager.default
        let archive = try Archive(url: archiveURL, accessMode: .read) // Use throwing initializer

        for fileName in filesToExtract {
            guard let entry = archive[fileName] else {
                // Log a warning if a specific component is not found in the archive.
                // Depending on requirements, you might throw an error here if a component is mandatory.
                NSLog("Warning: Vision component '\(fileName)' not found in archive '\(archiveURL.lastPathComponent)'.")
                continue
            }
            
            let destinationFilePath = destinationURL.appendingPathComponent(fileName)
            
            // Ensure a fresh extraction by removing any existing file.
            if fileManager.fileExists(atPath: destinationFilePath.path) {
                try fileManager.removeItem(at: destinationFilePath)
            }

            NSLog("Extracting '\(fileName)' to '\(destinationFilePath.path)'")
            _ = try archive.extract(entry, to: destinationFilePath) // Acknowledge potential return value
        }
    }
}

/// Represents a chat session with the loaded on-device LLM.
final class Chat {
    private let model: OnDeviceModel
    private var session: LlmInference.Session
    
    init(model: OnDeviceModel, topK: Int = 40, topP: Float = 0.9, temperature: Float = 0.9, enableVisionModality: Bool = true) throws {
      self.model = model

      let options = LlmInference.Session.Options()
      options.topk = topK
      options.topp = topP
      options.temperature = temperature
      options.enableVisionModality = enableVisionModality

      session = try LlmInference.Session(llmInference: model.inference, options: options)
    }
    
    func sendMessageSync(_ text: String) throws -> String {
        try session.addQueryChunk(inputText: text)
        return try session.generateResponse()
    }

    /// Adds an image to the current query context of the LLM session.
    /// - Parameter image: The `CGImage` to add.
    /// - Throws: An error if adding the image to the session fails.
    public func addImageToQuery(image: CGImage) throws {
        try self.session.addImage(image: image)
    }
    
    /// Sends a text prompt (and any previously added images) to the LLM and returns an asynchronous stream of response chunks.
    /// - Parameter text: The text prompt.
    /// - Returns: An `AsyncThrowingStream` yielding response string chunks.
    /// - Throws: An error if adding the query or generating the response fails.
    func sendMessage(_ text: String) async throws -> AsyncThrowingStream<String, any Error> {
      try session.addQueryChunk(inputText: text)
      let resultStream = session.generateResponseAsync()
      return resultStream
    }

    public func getLastResponseGenerationTime() -> TimeInterval? {
        return self.session.metrics.responseGenerationTimeInSeconds
    }

    public func sizeInTokens(text: String) throws -> Int {
        return try self.session.sizeInTokens(text: text)
    }
}

func attemptResponse() -> String {
    var model: OnDeviceModel
    do {
        model = try OnDeviceModel(modelIdentifier: .gemma2B) // Default model for test function
    } catch {
        let errorMessage = "attemptResponse: Failed to initialize OnDeviceModel: \(error.localizedDescription)"
        NSLog(errorMessage)
        return errorMessage
    }
    
    var chat: Chat
    do {
        // Pass default values to the updated Chat initializer
        chat = try Chat(model: model, topK: 40, topP: 0.9, temperature: 0.9, enableVisionModality: true)
    } catch {
        let errorMessage = "attemptResponse: Failed to initialize Chat session: \(error.localizedDescription)"
        NSLog(errorMessage)
        return errorMessage
    }
    
    var output: String
    do {
        output = try chat.sendMessageSync("Hello, what are your abilities?")
    } catch {
        let errorMessage = "attemptResponse: sendMessageSync failed: \(error.localizedDescription)"
        NSLog(errorMessage)
        return errorMessage
    }
    
    NSLog(output)
    return "Hello, world!"
}

