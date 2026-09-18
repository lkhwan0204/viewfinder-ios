import SwiftUI

struct HomeSearchStartContent: View {
    let recentQueries: [String]
    let onSelectQuery: (String) -> Void
    let onClearRecentQueries: () -> Void
    let onDeleteRecentQuery: (String) -> Void
    let onFocusSearch: () -> Void

    var body: some View {
        Group {
            if recentQueries.isEmpty {
                emptyHistoryView
            } else {
                recentHistoryView
            }
        }
    }

    private var recentHistoryView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("최근 검색")
                    .font(.headline)
                    .foregroundStyle(AppColors.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button("전체 삭제", action: onClearRecentQueries)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
            .frame(minHeight: 44)

            VStack(spacing: 0) {
                ForEach(recentQueries, id: \.self) { query in
                    recentQueryRow(query)
                }
            }
        }
    }

    private func recentQueryRow(_ query: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    onSelectQuery(query)
                } label: {
                    Text(query)
                        .font(.body)
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(query) 검색")

                Button {
                    onDeleteRecentQuery(query)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 삭제")
                .accessibilityHint("\(query) 검색어를 삭제합니다")
            }
            .frame(minHeight: 48)

            Divider()
                .overlay(AppColors.divider.opacity(0.7))
        }
    }

    private var emptyHistoryView: some View {
        Button(action: onFocusSearch) {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .offset(x: 3, y: 3)
                }

                Text("담고 싶은 장소를 찾아보세요")
                    .font(.callout)
                    .foregroundStyle(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("검색어 입력")
        .padding(.top, 32)
    }
}
