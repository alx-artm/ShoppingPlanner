//
//  FavoriteCardView.swift
//  Project2
//
//  Created by Alex on 1.07.25.
//

import SwiftUI

struct FavoriteCardView: View {
    
    let list: ListModel

    var body: some View {
        let summary = list.summary

        NavigationLink {
            ListViewInside(list: list)
        } label: {
            VStack(alignment: .leading, spacing: 16)  {
                ZStack(alignment: .center) {
                    
                    Circle()
                    
                        .fill(.gray.gradient.opacity(0.1))
                    
                        .frame(width: 48)

                    ListIconView(list: list)
                        .font(.title)

                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(list.name)
                            .lineLimit(1)
                            .font(.headline)
                            .foregroundStyle(.black) // Changed .tint to .foregroundStyle for text
                    }
                    
                    // Totals come from BudgetCalculator (see ListModel.summary).
                    Gauge(value: summary.boughtFraction.doubleValue) {
                        // Label content
                    } currentValueLabel: {

                        Text(summary.toBuy, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.black.secondary)
                        
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .opacity(summary.planned == 0 ? 0 : 1)
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
        .accessibilityIdentifier("home.listCard.\(list.name)")
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
    .sampleDataEnvironment()
}
