import SwiftUI

struct AutoScrollingScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    @Binding var messages: [Message]
    @Binding var isAutoScrollEnabled: Bool // New binding for auto-scroll toggle
    let content: () -> Content

    @State private var isUserScrolledUp: Bool = false
    @State private var lastViewedItemID: UUID? = nil 
    

    private let bottomContentAnchorID = UUID()

    init(_ axes: Axis.Set = .vertical,
         showsIndicators: Bool = true,
         messages: Binding<[Message]>,
         isAutoScrollEnabled: Binding<Bool>, // Add to initializer
         @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self._messages = messages
        self._isAutoScrollEnabled = isAutoScrollEnabled // Initialize new binding
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axes, showsIndicators: showsIndicators) {
                LazyVStack {
                    content()
                    Color.clear.frame(height: 1).id(bottomContentAnchorID)
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scrollView")).minY)
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(name: "scrollView")
            .scrollPosition(id: $lastViewedItemID, anchor: .bottom)
            .simultaneousGesture(DragGesture(minimumDistance: 1) // Require a small drag to trigger
                .onChanged { value in
                    if !isUserScrolledUp {
                        isUserScrolledUp = true
                    }
                }
            )
            .onChange(of: lastViewedItemID) { oldValue, newValue in
                if isUserScrolledUp {
                    var isNowAtTrueBottom = false
                    if let currentNewValue = newValue {
                        if let lastMessageID = messages.last?.id {
                            if currentNewValue == lastMessageID {
                                isNowAtTrueBottom = true
                            }
                        }
                        if currentNewValue == bottomContentAnchorID {
                            isNowAtTrueBottom = true
                        }
                    }
                    
                    if isNowAtTrueBottom {
                        isUserScrolledUp = false
                    } else {

                    }
                }
            }
            .onChange(of: messages.last?.id) {
                if isAutoScrollEnabled && !isUserScrolledUp {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: messages.last?.content) {
                 if isAutoScrollEnabled && !isUserScrolledUp && messages.last != nil {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isUserScrolledUp {
                    Button {
                        scrollToBottom(proxy: proxy, animated: true)
                        isUserScrolledUp = false
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let targetID = messages.last?.id ?? bottomContentAnchorID
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
