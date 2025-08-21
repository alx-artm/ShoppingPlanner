//
//  FavoriteCardView.swift
//  Project2
//
//  Created by Alex on 1.07.25.
//

import SwiftUI

struct FavoriteCardView: View {
    
    @Bindable var list: ListModel
    
    var body: some View {
        
        NavigationLink {
            ListViewInside(list: list)
        } label: {
            VStack(alignment: .leading, spacing: 16)  {
                ZStack(alignment: .center) {
                    
                    // ВОПРОС ЧТО С ЭТИМ ДЕЛАТЬ
                    Circle()
                    
                        .fill(.gray.gradient.opacity(0.1))
                    
                        .frame(width: 48).opacity(list.iconName.isEmpty ? 0 : 1)
                    
                    Text(list.iconName)
                        .font(.title)
                    
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(list.name)
                            .lineLimit(1)
                            .font(.headline)
                            .foregroundStyle(.black) // Changed .tint to .foregroundStyle for text
                        
                        
                    }
                    
                    // Используем свойства ListModel напрямую, которые теперь реактивны
                    Gauge(value: list.totalAmount.doubleValue == 0 ? 0 : list.completedAmount.doubleValue,
                          in: 0...(list.totalAmount.doubleValue == 0 ? 1 : list.totalAmount.doubleValue)) {
                        // Label content
                    } currentValueLabel: {
                        HStack {
                            Text(list.remainingAmount, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.black.secondary)
                        }
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                }
            }
            .padding()
            .background(
                // ЭТО ПОМОГАЕТ СОХРАНИТЬ ЦВЕТ .quaternary В ТЕМНОЙ И СВЕТЛОЙ ТЕМАХ ОДИНАКОВЫМ
                Group {
                        ZStack{
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white)
                            RoundedRectangle(cornerRadius: 12)
                                .fill(list.color.color.quaternary)
                        }
                }
            )
        }
    }
}

#Preview {
    NavigationStack {
        List{
            FavoriteCardView(list: SampleData.shared.victoriaList)
                .listRowSeparator(.hidden)
            
        }
        .listStyle(.plain)
    }
}
