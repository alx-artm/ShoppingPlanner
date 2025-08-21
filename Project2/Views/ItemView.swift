//
//  NewItemView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//


import SwiftUI
import SwiftData

struct ItemView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @Bindable var item: ItemModel
    
    let isNew: Bool
    
    @FocusState private var isFocused: Bool
    
    init(item: ItemModel, isNew: Bool = false) {
        self.item = item
        self.isNew = isNew
    }
    
    var body: some View {
        NavigationStack {
            Form {
                
                Section("Title & Price") {
                    
                    TextField("Title", text: $item.name)
                        .focused($isFocused)
                        .onAppear {
                            if isNew {
                                isFocused = true
                            }
                        }
                    
                    HStack{
                        TextField("Price", value: $item.price, format: .number)
                            .onChange(of: item.price) {
                                item.price = max(0, item.price ?? 0)
                            }
                            .keyboardType(.decimalPad)
                        
                        Text("Total:")
                            .bold()
                        
                        Text("\(item.totalPrice.description)")
                            .bold()
                            .frame(width: 60)
                            .lineLimit(1)
                    }
                }
                
                Section("Quantity") {
                    HStack {
                        TextField("Quantity", value: $item.quantity, format: .number)
                            .keyboardType(.decimalPad)
                        Spacer()
                        Stepper("", value: $item.quantity, in: 0...99)
                            .labelsHidden()
                            .onChange(of: item.quantity) {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.prepare()
                                haptic.impactOccurred()
                            }
                    }
                }
                
                Section("Link") {
                    TextField("", text: $item.url)
                        .keyboardType(.URL)
                }
                
                Section("Note") {
                    TextEditor(text: $item.notes)
                }
                
                //MARK: можно узнать имя листа и таким путем
                //Text("List name: '\(item.group?.list?.name ?? "no List name")'")
                
                // MARK: - Разворачивание опционала и проверка обратной связи (Group → List), УДАЛИТЬ В ФИНАЛЬНОЙ ВЕРСИИ АПКИ
                //Text("Inverse relationship of Item '\(item.name)' with parent-Group '\(item.group?.name ?? "no parent")'")
                
            }
            .toolbar {
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if item.name.isEmpty{
                            item.name = "Untitled item"
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                
                ToolbarItem(placement: .cancellationAction, content: {
                    Button(isNew ? "Cancel" : "Close") {
                        if isNew {
                            context.delete(item)
                            
                            do {
                                try context.save()
                            } catch {
                                print("Cannot save context: \(error)")
                            }
                            dismiss()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(isNew ? .red : .accentColor)
                })
               
                // кнопка удаления айтема внизу
                if !isNew {
                    ToolbarItem(placement: .bottomBar) {
                        Button{
                            context.delete(item)
                            
                            do {
                                try context.save()
                            } catch {
                                print("Cannot save context: \(error)")
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                            Text("Delete item")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "New item" : item.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


#Preview {
    ItemView(item: ItemModel(name:"Puss in boots"))
}
