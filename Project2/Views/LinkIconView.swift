//
//  LinkIconView.swift
//  Project2
//
//  Created by Alex on 5.08.25.
//

import SwiftUI

struct LinkIconView: View {
    let urlString: String
    
    // Определяем URL для загрузки favicon
    var faviconURL: URL? {
        // Проверяем, что URL валиден и имеет хост
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        
        // Используем сервис Google для получения иконки.
        // Заменяем `host` в шаблоне
        return URL(string: "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=\(host)&size=64")
    }
    
    var body: some View {
        // AsyncImage - встроенное представление SwiftUI для асинхронной загрузки изображений
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .empty:
                // Пока иконка загружается, показываем стандартный индикатор
                ProgressView()
            case .success(let image):
                // Если загрузка успешна, отображаем иконку
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            case .failure:
                // Если загрузка не удалась, показываем иконку-заглушку
                Image(systemName: "link")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            @unknown default:
                // На случай будущих изменений в API, показываем иконку-заглушку
                Image(systemName: "link")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
