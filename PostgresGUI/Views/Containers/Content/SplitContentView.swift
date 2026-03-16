//
//  SplitContentView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

struct SplitContentView: View {
    @Environment(AppState.self) private var appState
    @State private var resultsPaneHeight: CGFloat = 300
    var onDeleteKeyPressed: (() -> Void)?
    var onSpaceKeyPressed: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let editorPaneHeight = max(300, geometry.size.height - resultsPaneHeight)

            VSplitView {
                // Top pane: Query editor (previously bottom)
                QueryEditorView()
                    .frame(minHeight: 300)
                    .frame(height: editorPaneHeight)
                    .background(
                        GeometryReader { editorGeometry in
                            Color.clear
                                .preference(key: EditorPaneHeightKey.self, value: editorGeometry.size.height)
                        }
                    )

                // Bottom pane: Query results or table data (previously top)
                resultsPaneView
                    .frame(minHeight: 300)
                    .frame(height: resultsPaneHeight)
                    .background(
                        GeometryReader { resultsGeometry in
                            Color.clear
                                .preference(key: ResultsPaneHeightKey.self, value: resultsGeometry.size.height)
                        }
                    )
            }
            .onPreferenceChange(ResultsPaneHeightKey.self) { newHeight in
                // Update state when VSplitView resizes (if it can)
                if newHeight > 0 && abs(newHeight - resultsPaneHeight) > 1 {
                    resultsPaneHeight = newHeight
                }
            }
        }
    }

    @ViewBuilder
    private var resultsPaneView: some View {
        if appState.query.isExecutingQuery {
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.query.showQueryResults {
            QueryResultsView(
                onDeleteKeyPressed: onDeleteKeyPressed,
                onSpaceKeyPressed: onSpaceKeyPressed
            )
        } else {
            ContentUnavailableView {
                Label {
                    Text("No results found")
                        .font(.title3)
                        .fontWeight(.regular)
                } icon: { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Preference keys to track pane heights
struct EditorPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ResultsPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
