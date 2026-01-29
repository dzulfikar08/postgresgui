//
//  NavigationState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Manages navigation and modal presentation state
@Observable
@MainActor
class NavigationState {
    // Navigation
    var navigationPath: NavigationPath = NavigationPath()

    // Modal/Sheet state
    var isShowingConnectionForm: Bool = false
    var connectionToEdit: ConnectionProfile? = nil
    var isShowingCreateDatabase: Bool = false
    var isShowingKeyboardShortcuts: Bool = false
    var isShowingHelp: Bool = false

    // Sheet management helpers
    func showConnectionForm() {
        isShowingConnectionForm = true
    }

    func showCreateDatabase() {
        isShowingCreateDatabase = true
    }
}
