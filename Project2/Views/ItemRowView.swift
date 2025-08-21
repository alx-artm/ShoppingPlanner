//
//  ExtractedView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//


import SwiftUI
import UIKit

struct ItemRowView: View {
    @Bindable var item: ItemModel
    @State private var showDetails: Bool = false
    @State var showPicker: Bool = false
    @Environment(\.modelContext) var context
    
    var body: some View {
        VStack (alignment: .leading, spacing: nil) {
            HStack {
                Button {
                    withAnimation {
                        item.isComplete.toggle()
                        try? context.save()
                    }
                } label: {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .frame(width: 28)
                
                HStack {
                    Text(item.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clear.contentShape(Rectangle()))
                        .lineLimit(3)
                    Group {
                        if !item.url.isEmpty {
                            Image(systemName: "link")
                        }
                        
                        if !item.notes.isEmpty {
                            Image(systemName: "text.justify.left")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    
                    Spacer()
                    
                    Button {
                        showPicker.toggle()
                    } label: {
                        Text(item.quantity.formatted())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .sheet(isPresented: $showPicker) {
                        Picker("Quantity", selection: $item.quantity) {
                            ForEach(1...99, id: \.self) { tag in
                                Text("\(tag)").tag(tag)
                            }
                        }
                        .pickerStyle(.wheel)
                        .presentationDetents([.fraction(0.3), .medium])
                    }
      
                    //                // Custom Quantity "Button" with tap and swipe - ЭТИ СВАЙПЫ НЕОЧЕВИДНЫ ДЛЯ ЮЗЕРА, ПОТОМУ УБРАНЫ
                    //                // UIKit нужен для HAPTIC
                    //                ZStack {
                    //                    RoundedRectangle(cornerRadius: 8)
                    //                        .fill(Color.gray.quaternary)
                    //  MARK: - это еще погуглить почему тут ДВА ВОПРОСА ??
                    //                    Text(Self.quantityFormatter.string(from: NSNumber(value: item.quantity)) ?? "")
                    //                        .multilineTextAlignment(.center)
                    //                }
                    //                .frame(width: 44, height: 28)
                    //                .contentShape(Rectangle())
                    //                .highPriorityGesture(
                    //                    TapGesture()
                    //                        .onEnded {
                    //                            let haptic = UIImpactFeedbackGenerator(style: .light)
                    //                            haptic.prepare()
                    //                            item.quantity += 1
                    //                            haptic.impactOccurred()
                    //                        }
                    //                )
                    //                .gesture(
                    //                    DragGesture(minimumDistance: 5)
                    //                        .onEnded { value in
                    //                            if value.translation.width > 12 {
                    //                                if item.quantity > 0 {
                    //                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    //                                    haptic.prepare()
                    //                                    item.quantity -= 1
                    //                                    haptic.impactOccurred()
                    //                                }
                    //                            }
                    //                        }
                    //                )
                    
                    Text(item.totalPrice, format: .number)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .lineLimit(1)
                }
                .foregroundColor(item.isComplete ? .secondary : .primary)
        
                .foregroundStyle(.primary)
                .onTapGesture {
                    showDetails.toggle()
                }
            }
            
            
            Group {
                if !item.notes.isEmpty {
                    Text("Note: \(item.notes)")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(3)
                        .padding(.horizontal, 38)
                }
            }
        }
       
        .sheet(isPresented: $showDetails) {
            ItemView(item: item)
        }
    }
    
    
    #warning("take a look")// MARK: - это нигде сейчас не применяется, мб сделать это в стоимости в айтем прайс?
    static let quantityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
