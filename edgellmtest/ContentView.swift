//
//  ContentView.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/22/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(viewModel.responseText)
        }
        .padding()
        .onAppear {
            viewModel.startChat()
        }
    }
}

#Preview {
    ContentView()
}
