import Foundation

// ODO-56 서버 기반 식사 푸시 DTO. 서버 계약: POST/DELETE /v1/me/push-tokens, GET/PUT /v1/me/meal-notifications.

/// POST /v1/me/push-tokens 요청 본문.
struct PushTokenRegisterRequestDTO: Encodable {
    let token: String
    let platform: String     // "ios"
    let environment: String  // "sandbox" | "production"
}

/// 끼니 알림 슬롯 한 줄. slotIndex 0~4 = 아침/점심/저녁/추가1/추가2(서버와 고정 매핑).
struct MealNotificationSlotDTO: Codable {
    let slotIndex: Int
    let timeOfDay: String   // "HH:mm"
    let enabled: Bool
}

/// PUT /v1/me/meal-notifications 요청 본문.
struct MealNotificationsRequestDTO: Encodable {
    let timeZone: String
    let slots: [MealNotificationSlotDTO]
}

/// GET/PUT /v1/me/meal-notifications 응답 result.
struct MealNotificationsResponseDTO: Decodable {
    let timeZone: String
    let slots: [MealNotificationSlotDTO]
}

extension MealReminderSettings {
    /// 서버 슬롯 배열로 변환(slotIndex 0~4 고정 매핑).
    func toServerSlots() -> [MealNotificationSlotDTO] {
        func dto(_ index: Int, _ slot: MealSlot) -> MealNotificationSlotDTO {
            MealNotificationSlotDTO(
                slotIndex: index,
                timeOfDay: String(format: "%02d:%02d", slot.hour, slot.minute),
                enabled: slot.enabled
            )
        }
        return [dto(0, breakfast), dto(1, lunch), dto(2, dinner), dto(3, extra1), dto(4, extra2)]
    }

    /// 서버 슬롯 배열에서 복원. 누락 슬롯은 기본값 유지.
    init(serverSlots: [MealNotificationSlotDTO]) {
        var settings = MealReminderSettings.default
        for dto in serverSlots {
            let parts = dto.timeOfDay.split(separator: ":")
            let hour = parts.indices.contains(0) ? Int(parts[0]) ?? 0 : 0
            let minute = parts.indices.contains(1) ? Int(parts[1]) ?? 0 : 0
            let slot = MealSlot(enabled: dto.enabled, hour: hour, minute: minute)
            switch dto.slotIndex {
            case 0: settings.breakfast = slot
            case 1: settings.lunch = slot
            case 2: settings.dinner = slot
            case 3: settings.extra1 = slot
            case 4: settings.extra2 = slot
            default: break
            }
        }
        self = settings
    }
}
