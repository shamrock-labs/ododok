import SwiftUI
import WidgetKit

/// 위젯 익스텐션 진입점. 현재는 식사 측정 Live Activity 하나만 노출한다.
@main
struct OdodokWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealLiveActivity()
    }
}
