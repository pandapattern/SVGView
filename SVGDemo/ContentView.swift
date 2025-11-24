//
//  ContentView.swift
//  SVGDemo
//
//  Created by Lin GUO on 2025/11/24.
//

import SwiftUI
import SVGView

struct ContentView: View {
    var body: some View {
        SVGView(contentsOf: Bundle.main.url(forResource: "The_Shirt_System_sewing_pattern", withExtension: "svg")!)

    }
}

#Preview {
    ContentView()
}
