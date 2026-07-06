import SwiftUI
import SafariServices

/// 설정 화면 — HomeView 상단 bell 버튼 → sheet.
/// REQ-05: '계정 삭제' 진입점.
/// 구조: 프로필 헤더 → 측정(기기) → 계정(로그아웃·삭제) → 앱(약관·정책·문의·버전).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AirPodsModel.storageKey) private var airPodsRawValue: String = AirPodsModel.default.rawValue

    @State private var showDeleteConfirmation = false
    @State private var showAirPodsPicker = false
    @State private var showFeedback = false

    private static let feedbackFormURL = URL(string: "https://forms.gle/6AsoDPHhywVpV9Qb6")!

    private var airPodsModel: AirPodsModel {
        AirPodsModel(rawValue: airPodsRawValue) ?? .default
    }

    /// 저장된 loginMethod("apple"/"kakao"/"google")를 사람이 읽는 라벨로 매핑. nil이면 "로그인됨".
    private var loginMethodLabel: String {
        switch state.loginMethod {
        case "apple":  return "Apple"
        case "kakao":  return "카카오"
        case "google": return "Google"
        default:       return "로그인됨"
        }
    }

    private var badgeBackground: Color {
        switch state.loginMethod {
        case "apple":  return .black
        case "kakao":  return .kakaoYellow
        case "google": return .white
        default:       return Color.hairline
        }
    }

    private var badgeForeground: Color {
        switch state.loginMethod {
        case "apple":  return .white
        case "kakao":  return .black.opacity(0.85)
        case "google": return Color.googleText
        default:       return Color.textSecondary
        }
    }

    private var badgeBorder: Color? {
        state.loginMethod == "google" ? Color.googleBorder : nil
    }

    private var providerBadge: some View {
        Text(loginMethodLabel)
            .font(.appFont(.semiboldMicro))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground, in: Capsule())
            .overlay {
                if let border = badgeBorder {
                    Capsule().stroke(border, lineWidth: 1)
                }
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    deviceSection
                    accountSection
                    appSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.gap)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.tintInteractive)
                        .font(.appFont(.semiboldBody))
                }
            }
        }
        .appDialog(
            isPresented: $showDeleteConfirmation,
            title: "계정을 삭제할까요?",
            message: "오도독 계정과 씹기 기록, 도토리, 스트릭이 모두 삭제돼요. 이 작업은 되돌릴 수 없어요.",
            primary: .init("계정 삭제", role: .destructive) {
                Task { await state.eraseAllUserData() }
            },
            secondary: .init("취소", role: .cancel) {}
        )
        .airPodsPickerDialog(
            isPresented: $showAirPodsPicker,
            selected: Binding(
                get: { airPodsModel },
                set: { airPodsRawValue = $0.rawValue }
            )
        )
        .sheet(isPresented: $showFeedback) {
            SafariView(url: Self.feedbackFormURL)
        }
    }

    // MARK: - Sections

    /// 이름 + provider 뱃지를 텍스트 헤더로 표시. 카드/탭 없음.
    private var profileHeader: some View {
        HStack(spacing: 10) {
            Text(state.displayName ?? "닉네임 없음")
                .font(.appFont(.heavyTitleXLarge))
                .foregroundStyle(Color.textPrimary)
            providerBadge
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    /// 계정 — 로그아웃, 계정 삭제.
    private var accountSection: some View {
        VStack(spacing: AppSpacing.none) {
            AppSettingsSectionHeader(title: "계정")

            Button {
                Task {
                    await state.logoutFromServer()
                    dismiss()
                }
            } label: {
                AppSettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "로그아웃")
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.topInsetCompact)
            .accessibilityIdentifier("Logout")

            Button {
                showDeleteConfirmation = true
            } label: {
                AppSettingsRow(icon: "trash.fill", title: "계정 삭제")
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.topInsetCompact)
            .accessibilityIdentifier("DeleteMyData")
        }
    }

    /// 측정 — AirPods 모델 선택.
    private var deviceSection: some View {
        VStack(spacing: 0) {
            AppSettingsSectionHeader(title: "측정")

            Button {
                showAirPodsPicker = true
            } label: {
                AppSettingsRow(icon: "airpodspro", title: "측정 기기", value: airPodsModel.displayName)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AirPodsModelPicker")
        }
    }

    /// 앱 — 이용약관·개인정보처리방침(앱 내 뷰어)·문의·버전.
    private var appSection: some View {
        VStack(spacing: 0) {
            AppSettingsSectionHeader(title: "앱")

            NavigationLink {
                LegalDocumentView(title: "이용약관", markdown: LegalDocumentView.termsMarkdown)
            } label: {
                AppSettingsRow(icon: "doc.text", title: "이용약관", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("TermsOfService")

            NavigationLink {
                LegalDocumentView(title: "개인정보처리방침", markdown: LegalDocumentView.privacyMarkdown)
            } label: {
                AppSettingsRow(icon: "hand.raised", title: "개인정보처리방침", showsChevron: true)
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.topInsetCompact)
            .accessibilityIdentifier("PrivacyPolicy")

            Button {
                showFeedback = true
            } label: {
                AppSettingsRow(icon: "envelope", title: "문의·피드백")
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.topInsetCompact)
            .accessibilityIdentifier("Feedback")

            HStack {
                Text("버전 \(AppState.appVersion ?? "-")")
                    .font(.appFont(.regularCallout))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            .padding(.top, AppSpacing.gap)
        }
    }
}

// MARK: - Legal document viewer

/// 이용약관·개인정보처리방침을 앱 내에서 스크롤로 읽는 경량 뷰어.
/// SettingsView의 NavigationStack 안에서 push되므로 뒤로가기는 자동으로 제공된다.
/// 마크다운을 줄 단위로 경량 렌더한다 — 외부 렌더러 의존성 없음.
private struct LegalDocumentView: View {
    let title: String
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Line model

    private enum LineKind {
        case h1(String)
        case h2(String)
        case h3(String)
        case bullet(String)
        case numbered(String)
        case body(String)
        case spacer
    }

    private var parsedLines: [LineKind] {
        markdown.components(separatedBy: "\n").map { raw in
            let line = raw
            if line.hasPrefix("### ") {
                return .h3(String(line.dropFirst(4)))
            } else if line.hasPrefix("## ") {
                return .h2(String(line.dropFirst(3)))
            } else if line.hasPrefix("# ") {
                return .h1(String(line.dropFirst(2)))
            } else if line.hasPrefix("- ") {
                return .bullet(String(line.dropFirst(2)))
            } else if let rest = numberedPrefix(line) {
                return .numbered(rest)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                return .spacer
            } else {
                return .body(line)
            }
        }
    }

    /// "1. ", "2. " 등 번호 목록 접두사를 제거하고 본문만 반환. 해당 없으면 nil.
    private func numberedPrefix(_ s: String) -> String? {
        let pattern = #"^\d+\.\s+"#
        guard let range = s.range(of: pattern, options: .regularExpression) else { return nil }
        return String(s[range.upperBound...])
    }

    @ViewBuilder
    private func lineView(_ kind: LineKind) -> some View {
        switch kind {
        case .h1(let text):
            Text(text)
                .font(.appFont(.heavyTitle))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 24)
                .padding(.bottom, 6)
        case .h2(let text):
            Text(text)
                .font(.appFont(.heavyHeadline))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 20)
                .padding(.bottom, 4)
        case .h3(let text):
            Text(text)
                .font(.appFont(.boldBody))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 14)
                .padding(.bottom, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.appFont(.regularLabel))
                    .foregroundStyle(Color.textSecondary)
                Text(text)
                    .font(.appFont(.regularLabel))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        case .numbered(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.appFont(.regularLabel))
                    .foregroundStyle(Color.textSecondary)
                Text(text)
                    .font(.appFont(.regularLabel))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        case .body(let text):
            Text(text)
                .font(.appFont(.regularLabel))
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .spacer:
            Color.clear.frame(height: AppSpacing.two)
        }
    }
}

// MARK: - Legal content (법무 검토 전 초안 — 실제 출시 전 법무 검토 및 교체 필요)

private extension LegalDocumentView {

    // 이용약관 초안. 법무 검토 전 초안이며 실제 출시 전 반드시 검토·교체가 필요합니다.
    static let termsMarkdown = """
# 오도독 이용약관

## 제1조 목적

본 약관은 샴록랩스(이하 "회사")가 제공하는 오도독(Ododok) 서비스(이하 "서비스")의 이용 조건 및 절차, 회사와 이용자 간의 권리·의무 및 책임 사항을 규정함을 목적으로 합니다.

## 제2조 정의

본 약관에서 사용하는 용어의 정의는 다음과 같습니다.

- "서비스"란 AirPods(AirPods Pro, AirPods 3·4세대, AirPods Max)의 모션 센서를 활용하여 식사 중 씹기를 측정·기록하고, 통계·도토리 보상·소셜(친구) 기능을 제공하는 오도독 애플리케이션 및 관련 제반 서비스를 의미합니다.
- "이용자"란 본 약관에 동의하고 서비스를 이용하는 자를 의미합니다.
- "계정"이란 이용자가 서비스 이용을 위해 소셜 로그인(Apple, Kakao, Google)을 통해 생성된 식별 정보를 의미합니다.

## 제3조 약관의 효력 및 변경

1. 본 약관은 서비스를 이용하고자 하는 모든 이용자에게 적용됩니다.
2. 회사는 관련 법령을 위반하지 않는 범위에서 본 약관을 변경할 수 있습니다.
3. 약관이 변경되는 경우 회사는 변경 사항을 앱 내 공지사항 또는 알림을 통해 사전 고지합니다.
4. 변경된 약관에 동의하지 않는 이용자는 서비스 이용을 중단하고 계정 삭제를 요청할 수 있습니다.

## 제4조 서비스 내용

회사는 다음과 같은 서비스를 제공합니다.

- AirPods 모션 센서를 통한 식사 중 씹기 측정 및 기록
- 씹기 횟수·통계 및 일별 목표 달성 현황 제공
- 도토리 포인트 적립 및 보상 기능
- 소셜 기능(친구 초대·랭킹)

## 제5조 계정 및 로그인

1. 이용자는 Apple, Kakao, Google 소셜 로그인을 통해 서비스를 이용합니다.
2. 이용자는 자신의 계정 정보를 안전하게 관리할 책임이 있습니다.
3. 이용자는 자신의 계정을 타인에게 양도하거나 공유할 수 없습니다.

## 제6조 이용자의 의무

이용자는 다음 각 호의 행위를 하여서는 안 됩니다.

- 타인의 정보를 도용하거나 허위 정보를 등록하는 행위
- 서비스의 정상적인 운영을 방해하는 행위
- 회사의 사전 동의 없이 서비스를 상업적으로 이용하는 행위
- 관련 법령 또는 본 약관을 위반하는 행위

## 제7조 측정 정확성 및 면책 고지

1. 본 서비스는 의료기기가 아니며, 제공되는 씹기 측정 데이터는 참고 목적으로만 활용하여야 합니다.
2. 서비스의 측정 결과는 착용 상태, 기기 모델, 개인차 등 다양한 요인에 따라 달라질 수 있습니다.
3. 회사는 측정 결과의 의학적 정확성을 보장하지 않으며, 이를 의료적 판단의 근거로 사용하여서는 안 됩니다.

## 제8조 서비스의 변경 및 중단

1. 회사는 운영상·기술상의 필요에 의해 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다.
2. 서비스 중단 시 회사는 사전에 앱 내 공지를 통해 이용자에게 고지합니다. 다만, 불가피한 사유로 인한 긴급 중단의 경우 사후 고지할 수 있습니다.

## 제9조 책임의 한계

1. 회사는 천재지변, 불가항력적 사유로 인한 서비스 제공 불능에 대해 책임을 지지 않습니다.
2. 회사는 이용자의 귀책 사유로 인한 서비스 이용 장애에 대해 책임을 지지 않습니다.
3. 회사는 이용자가 서비스를 통해 얻은 정보·자료 등의 신뢰성·정확성에 대해 보증하지 않습니다.

## 제10조 문의

서비스 이용 관련 문의는 아래 연락처로 접수하시기 바랍니다.

- 이메일: ododok.team@gmail.com

## 부칙

본 약관은 2026년 6월 30일부터 시행합니다.
"""
    // TODO: 시행일(2026-06-30)은 목표 출시일 기준. 실제 출시일이 바뀌면 갱신하고 법무 최종 검토 후 적용할 것.

    static let privacyMarkdown = """
**시행일:** 2026-06-30

오도독(이하 '본 앱')은 이용자의 개인정보를 중요하게 생각하며, 「개인정보 보호법」 등 관련 법령을 준수합니다. 본 방침은 본 앱이 어떤 정보를 어떤 목적으로 수집·이용하며, 어떻게 보호·파기하는지를 안내합니다.

## 1. 수집하는 정보

**계정 정보 (소셜 로그인)**

본 앱은 Apple, Google, Kakao 계정을 통한 소셜 로그인만 제공합니다. 로그인 시 각 제공자로부터 계정을 식별하기 위한 고유 식별자를 전달받으며, 제공자 정책과 이용자 동의 범위에 따라 이메일, 이름(닉네임)이 포함될 수 있습니다. (Apple 로그인은 '이메일 가리기'를 선택할 수 있습니다.)

**서비스 이용 정보**

- 저작(씹기) 세션 기록: 씹기 횟수, 리듬, 측정 시간 등
- 통계 및 도토리 적립 내역
- 이용자가 입력한 호칭(별명)
- 친구·랭킹 기능 이용에 따른 연결 정보

**기기 센서 정보**

식사 중 AirPods 등 기기의 모션(IMU) 신호를 분석해 저작 리듬을 산출합니다. 본 앱은 음성을 녹음하거나 저장하지 않습니다.

**자동 수집 정보 (분석·진단)**

서비스 개선과 오류 대응을 위해 제품 이용 상호작용 데이터, 기기 식별자, 크래시·오류 진단 정보가 자동 수집될 수 있습니다. 이는 분석 도구(Amplitude)와 오류 추적 도구(Sentry)를 통해 처리되며, 광고 식별자(IDFA)를 사용하지 않고 다른 앱·웹사이트에 걸친 이용자 추적을 하지 않습니다.

## 2. 이용 목적

- 계정 식별 및 로그인 유지, 기기 변경·재설치 시 데이터 연속성 보장
- 저작 측정, 통계, 도토리 보상 등 핵심 기능 제공
- 친구·랭킹 기능 제공
- 끼니 리마인더 등 알림 전송
- 서비스 품질 개선 및 오류 진단

## 3. 기기 권한

본 앱은 아래 권한을 기능 제공 목적으로 요청하며, 권한은 기기 설정에서 언제든 거부·철회할 수 있습니다. (거부 시 해당 기능이 제한될 수 있습니다.)

- **동작 및 피트니스(모션):** 식사 중 AirPods 움직임을 분석해 저작 리듬을 시각화합니다.
- **마이크:** AirPods 동작 신뢰성 분석을 위해 요청될 수 있습니다. 음성 녹음·저장은 하지 않습니다.
- **알림:** 끼니 리마인더 등 알림을 전송합니다.

## 4. 제3자 처리 및 위탁

본 앱은 서비스 제공을 위해 아래 사업자에 일부 정보 처리를 위탁하거나 연동합니다.

- **소셜 로그인:** Apple, Google, Kakao (계정 인증)
- **이용 분석:** Amplitude (익명 통계 분석)
- **오류 추적:** Sentry (크래시·진단 데이터)
- **서버 인프라:** Amazon Web Services

## 5. 국외 이전

본 앱은 서비스 제공, 이용 분석, 오류 진단, 소셜 로그인 처리를 위해 Apple, Google, Amplitude, Sentry 등 국외 사업자의 서비스를 이용할 수 있으며, 이 과정에서 계정 식별 정보, 이용 분석 정보, 오류·진단 정보 등이 국외에서 처리될 수 있습니다. 각 사업자는 해당 서비스 제공 및 보안·품질 개선 목적 범위에서 정보를 처리하며, 관련 법령에 따라 필요한 보호 조치를 적용합니다

## 6. 보유 및 파기

이용자가 회원 탈퇴(계정 삭제)를 하면 해당 계정의 서버·기기 내 데이터를 지체 없이 파기합니다. 계정 삭제는 앱 내 **설정 > 계정 삭제**에서 직접 할 수 있습니다. 관련 법령에 따라 보존 의무가 있는 경우에는 해당 기간 동안만 보관 후 파기합니다.

## 7. 이용자의 권리

이용자는 자신의 개인정보에 대해 열람·정정·삭제·처리정지를 요청할 수 있습니다. 앱 내 계정 삭제 기능을 이용하거나 아래 문의처로 연락하면 됩니다.

## 8. 아동의 개인정보

본 앱은 만 14세 미만 아동을 주 대상으로 하지 않으며, 만 14세 미만 아동의 개인정보를 법정대리인 동의 없이 고의로 수집하지 않습니다.

## 9. 안전성 확보 조치

본 앱은 통신 구간 암호화(HTTPS) 및 접근 권한 관리 등 합리적인 보호 조치를 적용합니다.

## 10. 방침 변경

본 방침이 변경되는 경우 앱 또는 본 페이지를 통해 변경 내용을 공지합니다.

## 11. 문의

개인정보 관련 문의는 아래로 연락해 주세요.

- 이메일: ododok.team@gmail.com
"""
    // TODO: 시행일(2026-06-30)은 목표 출시일 기준. 실제 출시일이 바뀌면 갱신하고 법무 최종 검토 후 적용할 것.
}

// MARK: - AirPods Model Picker (dialog overlay)

/// 측정 기기 선택 다이얼로그. AppDialog와 동일한 시각 chrome(320pt, 22/28 padding,
/// 헤어라인 디바이더)에 라디오 리스트와 취소/확인 푸터를 얹은 형태.
private struct AirPodsPickerDialog: View {
    let initial: AirPodsModel
    let onConfirm: (AirPodsModel) -> Void
    let onCancel: () -> Void

    @State private var draft: AirPodsModel

    init(initial: AirPodsModel, onConfirm: @escaping (AirPodsModel) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — title only, no body description.
            Text("사용 중인 AirPods 모델을 선택해요.")
                .font(.appFont(.heavyHeadline))
                .foregroundStyle(Color.textDefault)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.dialogH)
                .padding(.vertical, AppSpacing.dialogV)
                .frame(maxWidth: .infinity)

            divider

            // Radio rows
            VStack(spacing: AppSpacing.none) {
                ForEach(Array(AirPodsModel.allCases.enumerated()), id: \.element.id) { idx, model in
                    row(model)
                    if idx < AirPodsModel.allCases.count - 1 {
                        divider.padding(.leading, AppSpacing.dialogH)
                    }
                }
            }

            divider

            // Footer — 취소 / 확인
            HStack(spacing: AppSpacing.none) {
                Button {
                    onCancel()
                } label: {
                    Text("취소")
                        .font(.appFont(.semiboldBodyLarge))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Color.borderDefault.frame(width: AppSize.hairline)

                Button {
                    onConfirm(draft)
                } label: {
                    Text("확인")
                        .font(.appFont(.boldBodyLarge))
                        .foregroundStyle(Color.textAction)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: AppSize.dialogActionHeight)
        }
        .frame(maxWidth: AppSize.dialogMaxWidth)
        .background(Color.bgPopover, in: RoundedRectangle(cornerRadius: AppRadius.element))
        .appElevation(.high)
    }

    private var divider: some View {
        Color.borderDefault.frame(height: AppSize.hairline)
    }

    private func row(_ model: AirPodsModel) -> some View {
        let isActive = model == draft
        return Button {
            draft = model
        } label: {
            HStack(spacing: AppSpacing.cardH) {
                radio(isActive: isActive)
                Text(model.displayName)
                    .font(.appFont(.semiboldBody))
                    .foregroundStyle(Color.textDefault)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.dialogH)
            .padding(.vertical, AppSpacing.inputV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// SF Symbol 없이 그린 라디오 버튼 — 외곽 원 + 활성 시 안쪽 닷.
    private func radio(isActive: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isActive ? Color.textActionStrong : Color.textSubtle, lineWidth: 1.5)
                .frame(width: Metrics.radioOuter, height: Metrics.radioOuter)
            if isActive {
                Circle()
                    .fill(Color.textActionStrong)
                    .frame(width: Metrics.radioInner, height: Metrics.radioInner)
            }
        }
    }
}

private struct AirPodsPickerDialogOverlay: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selected: AirPodsModel

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.bgOverlayScrim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isPresented = false }
                AirPodsPickerDialog(
                    initial: selected,
                    onConfirm: { chosen in
                        selected = chosen
                        isPresented = false
                    },
                    onCancel: { isPresented = false }
                )
                .padding(.horizontal, AppSpacing.eight)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: AppMotion.springFastResponse, dampingFraction: AppMotion.springDampingFraction), value: isPresented)
    }
}

extension View {
    fileprivate func airPodsPickerDialog(
        isPresented: Binding<Bool>,
        selected: Binding<AirPodsModel>
    ) -> some View {
        modifier(AirPodsPickerDialogOverlay(isPresented: isPresented, selected: selected))
    }
}

// MARK: - Safari in-app browser

/// SFSafariViewController 래퍼. 앱 내 시트로 외부 URL을 보여줄 때 사용.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private enum Metrics {
    static let radioOuter = AppSize.controlTiny
    static let radioInner = AppSpacing.inner
}
