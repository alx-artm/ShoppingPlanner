//
//  QuickItemRowView.swift
//  Project2
//
//  Created by Alex on 12.06.25.
//

import SwiftUI
import SwiftData

struct QuickItemRowView: View {
    @Bindable var item: QuickItemModel
    
    var body: some View {
        HStack {
            Button {
                withAnimation {
                    item.isComplete.toggle()
                    item.completedAt = item.isComplete ? Date() : nil
                }
            } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.isComplete ? .accent : .gray)
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
            //MARK: - КАСТОМНАЯ ДЛИНА СЕПАРАТОРА
            .alignmentGuide(.listRowSeparatorLeading) { _ in 32 }
            
            HStack(spacing: 12) {
                TextField("Title", text: Binding(
                    get: { item.name },
                    set: { item.name = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
                
                TextField("1", value: $item.quantity, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 35)
                    .onChange(of: item.quantity) {
                        if item.quantity < 0 {
                            item.quantity = 0
                        }
                    }
                
                Stepper("", value: $item.quantity, in: 0...99)
                    .labelsHidden()
                    .onChange(of: item.quantity) {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.prepare()
                        haptic.impactOccurred()
                    }
            }
        }
    }
}
