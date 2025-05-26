//
//  LlmInference.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/23/25.
//

import MediaPipeTasksGenAI
import Foundation

struct OnDeviceModel {
    private(set) var inference: LlmInference

    init() throws {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        let bundleModelPath = Bundle.main.path(forResource: "gemma3n4B", ofType: "task")!
        let modelCopyPath = cacheDir.appendingPathComponent("gemma3n4B.task")
        NSLog("bundle path: \(bundleModelPath)")
        NSLog("cache path: \(modelCopyPath.path)")

        if !FileManager.default.fileExists(atPath: modelCopyPath.path) {
            try FileManager.default.copyItem(atPath: bundleModelPath, toPath: modelCopyPath.path)
        }
        let options = LlmInference.Options(modelPath: modelCopyPath.path)

        options.maxTokens = 1000
        inference = try LlmInference(options: options)
    }
}

final class Chat {
    private let model: OnDeviceModel
    private var session: LlmInference.Session

    init(model: OnDeviceModel) throws {
        self.model = model

        let options = LlmInference.Session.Options()
        options.topk = 40
        options.topp = 0.9
        options.temperature = 0.9

        session = try LlmInference.Session(llmInference: model.inference, options: options)
        let systemPrompt = """
                           You are a helpful assistant embedded in an iOS app for generating SVG images via a chat interface.

                           IMPORTANT RULES — FOLLOW THESE STRICTLY:
                           1. Your output MUST be a valid JSON object with the following structure:
                              {
                                "svg": "<svg>...</svg>",  // optional
                                "response": "Your response text."  // REQUIRED
                              }
                           2. NEVER output anything outside this JSON object. No prose, no markdown, no code blocks.
                           3. The "response" field is ALWAYS required. The "svg" field is OPTIONAL — include it ONLY if the user asked for a drawing.
                           4. The "svg" field must contain a valid, renderable SVG string when used.

                           You may respond freely in the "response" field. If the user asks you to "draw" something, generate an SVG and include it in the "svg" field. Otherwise, omit the "svg" field.

                           ALWAYS output a valid JSON object with AT LEAST the "response" field. NO CODE BLOCKS, NO MARKDOWN, JUST VALID JSON.
                           """
        try session.addQueryChunk(inputText: systemPrompt)
    }

    func sendMessageSync(_ text: String) throws -> String {
        try session.addQueryChunk(inputText: text)
        return try session.generateResponse()
    }

    func sendMessage(_ text: String) async throws -> AsyncThrowingStream<String, any Error> {
        try session.addQueryChunk(inputText: text)
        let resultStream = session.generateResponseAsync()
        return resultStream
    }
}

func attemptResponse() -> String {
    var model: OnDeviceModel
    do {
        model = try OnDeviceModel()
    } catch {
        return "OnDeviceModel threw: \(error)"
    }

    var chat: Chat
    do {
        chat = try Chat(model: model)
    } catch {
        return "Chat init threw: \(error)"
    }

    var output: String
    do {
        output = try chat.sendMessageSync("Hello, what are your abilities?")
    } catch {
        return "sendMessageSync threw: \(error)"
    }

    NSLog(output)
    return "Hello, world!"
}

