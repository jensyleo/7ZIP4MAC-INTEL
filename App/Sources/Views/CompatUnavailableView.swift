//
//  CompatUnavailableView.swift
//  7ZIP4MAC — native macOS GUI for the 7-Zip engine
//
//  Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

/// Drop-in replacement for `ContentUnavailableView` (macOS 14+) so the app can
/// target macOS 13 (needed for Intel Mac compatibility).
struct CompatUnavailableView<Label: View, Description: View, Actions: View>: View {
    private var label: Label
    private var description: Description
    private var actions: Actions

    init(@ViewBuilder label: () -> Label,
         @ViewBuilder description: () -> Description,
         @ViewBuilder actions: () -> Actions) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label.font(.title2).foregroundStyle(.secondary)
            description.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension CompatUnavailableView where Actions == EmptyView {
    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension CompatUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == EmptyView, Actions == EmptyView {
    init(_ title: String, systemImage: String) {
        self.init(label: { Label(title, systemImage: systemImage) }, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension CompatUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text, Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text) {
        self.init(label: { Label(title, systemImage: systemImage) }, description: { description }, actions: { EmptyView() })
    }
}
