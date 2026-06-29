import SwiftUI
import SafariServices

/// 설정 화면 — HomeView 상단 bell 버튼 → sheet.
/// REQ-05: '내 데이터 삭제' 진입점.
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
        default:       return Color.ink100
        }
    }

    private var badgeForeground: Color {
        switch state.loginMethod {
        case "apple":  return .white
        case "kakao":  return .black.opacity(0.85)
        case "google": return Color.googleText
        default:       return Color.ink600
        }
    }

    private var badgeBorder: Color? {
        state.loginMethod == "google" ? Color.googleBorder : nil
    }

    private var providerBadge: some View {
        Text(loginMethodLabel)
            .font(.appFont(.semibold, size: 11))
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.acorn600)
                        .font(.appFont(.semibold, size: 15))
                }
            }
        }
        .appDialog(
            isPresented: $showDeleteConfirmation,
            title: "내 데이터를 삭제할까요?",
            message: "씹기 기록, 도토리, 스트릭 모두 사라져요. 되돌릴 수 없어요.",
            primary: .init("모두 삭제", role: .destructive) {
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
            Text(state.displayName ?? "이름 없음")
                .font(.appFont(.heavy, size: 22))
                .foregroundStyle(Color.ink800)
            providerBadge
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    /// 계정 — 로그아웃, 내 데이터 삭제.
    private var accountSection: some View {
        VStack(spacing: 0) {
            sectionHeader("계정")

            Button {
                Task {
                    await state.logoutFromServer()
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.ink600)
                        .frame(width: 26)

                    Text("로그아웃")
                        .font(.appFont(.semibold, size: 16))
                        .foregroundStyle(Color.ink800)

                    Spacer()
                }
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("Logout")

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.ink600)
                        .frame(width: 26)

                    Text("내 데이터 삭제")
                        .font(.appFont(.semibold, size: 16))
                        .foregroundStyle(Color.ink800)

                    Spacer()
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("DeleteMyData")
        }
    }

    /// 측정 — AirPods 모델 선택.
    private var deviceSection: some View {
        VStack(spacing: 0) {
            sectionHeader("측정")

            Button {
                showAirPodsPicker = true
            } label: {
                settingsRow(
                    icon: "airpodspro",
                    title: "측정 기기",
                    value: airPodsModel.displayName,
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AirPodsModelPicker")
        }
    }

    /// 앱 — 이용약관·개인정보처리방침(앱 내 뷰어)·문의·버전.
    private var appSection: some View {
        VStack(spacing: 0) {
            sectionHeader("앱")

            NavigationLink {
                LegalDocumentView(title: "이용약관", markdown: LegalDocumentView.termsMarkdown)
            } label: {
                linkRow(icon: "doc.text", title: "이용약관")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("TermsOfService")

            NavigationLink {
                LegalDocumentView(title: "개인정보처리방침", markdown: LegalDocumentView.privacyMarkdown)
            } label: {
                linkRow(icon: "hand.raised", title: "개인정보처리방침")
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("PrivacyPolicy")

            Button {
                showFeedback = true
            } label: {
                linkRow(icon: "envelope", title: "문의·피드백", showsChevron: false)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("Feedback")

            HStack {
                Text("버전 \(AppState.appVersion ?? "-")")
                    .font(.appFont(.regular, size: 13))
                    .foregroundStyle(Color.ink400)
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Row builders

    /// 흰 카드 row — 아이콘 + 제목(좌) / 값(우) + (옵션)chevron. 좌우 한 줄 배치.
    private func settingsRow(
        icon: String,
        title: String,
        value: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.appFont(.medium, size: 16))
                .foregroundStyle(Color.ink600)
                .frame(width: 26)

            Text(title)
                .font(.appFont(.semibold, size: 16))
                .foregroundStyle(Color.ink800)

            Spacer()

            Text(value)
                .font(.appFont(.semibold, size: 16))
                .foregroundStyle(Color.ink600)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink600)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    /// 단일 라벨 row — 약관·문의처럼 탭하면 이동/열기만 하는 항목.
    /// `showsChevron`: NavigationLink push면 true, 다이얼로그·외부 링크는 false.
    private func linkRow(icon: String, title: String, showsChevron: Bool = true) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.appFont(.medium, size: 16))
                .foregroundStyle(Color.ink600)
                .frame(width: 26)

            Text(title)
                .font(.appFont(.semibold, size: 16))
                .foregroundStyle(Color.ink800)

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink600)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.appFont(.heavy, size: 17))
                .foregroundStyle(Color.ink800)
            Spacer()
        }
        .padding(.bottom, 10)
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
        .background(Color.cream.ignoresSafeArea())
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
                .font(.appFont(.heavy, size: 20))
                .foregroundStyle(Color.ink800)
                .padding(.top, 24)
                .padding(.bottom, 6)
        case .h2(let text):
            Text(text)
                .font(.appFont(.heavy, size: 17))
                .foregroundStyle(Color.ink800)
                .padding(.top, 20)
                .padding(.bottom, 4)
        case .h3(let text):
            Text(text)
                .font(.appFont(.bold, size: 15))
                .foregroundStyle(Color.ink800)
                .padding(.top, 14)
                .padding(.bottom, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.ink600)
                Text(text)
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.ink600)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        case .numbered(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.ink600)
                Text(text)
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.ink600)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        case .body(let text):
            Text(text)
                .font(.appFont(.regular, size: 14))
                .foregroundStyle(Color.ink600)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .spacer:
            Color.clear.frame(height: 8)
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

    // 개인정보처리방침 초안. 법무 검토 전 초안이며 실제 출시 전 반드시 검토·교체가 필요합니다.
    static let privacyMarkdown = """
# 개인정보처리방침

오도독(Ododok)은 이용자의 개인정보를 소중히 여기며, 「개인정보 보호법」 등 관련 법령을 준수합니다. 본 방침은 회사가 수집하는 정보의 항목·목적·보유 기간·제3자 제공 현황 및 이용자의 권리를 명확히 안내합니다.

## 제1조 총칙

수집 항목 요약: 소셜 로그인 식별자, 닉네임, 익명 기기 식별자, 모션 센서 데이터(가속도·자이로), 식사·씹기 기록 및 통계, 앱 사용·진단 로그.

이용자는 언제든지 앱 내 '내 데이터 삭제' 기능을 통해 본인의 데이터를 즉시 삭제할 수 있습니다.

## 제2조 수집 항목 및 방법

회사는 다음과 같은 정보를 수집합니다.

### 필수 수집 항목

- 소셜 로그인 식별자(Apple, Kakao, Google에서 제공하는 사용자 고유 식별자)
- 닉네임(이용자가 직접 입력)
- 익명 기기 식별자(X-Device-Id, 기기 고유 식별을 위해 앱이 생성하는 임의 값)
- AirPods 모션 센서 데이터(가속도·자이로, 식사 중 씹기 측정용)
- 식사 기록·씹기 횟수·통계 데이터

### 자동 수집 항목

- 앱 사용 로그(기능 이용 이력, Amplitude를 통한 분석 목적)
- 진단 로그(오류 발생 정보, Firebase·Sentry를 통한 안정성 개선 목적)

수집 방법: 이용자의 직접 입력, 소셜 로그인 연동, AirPods 센서 자동 수집, 서비스 이용 과정에서의 자동 생성.

## 제3조 이용 목적

수집된 정보는 다음 목적으로만 이용됩니다.

- 씹기 측정 및 식사 기록 서비스 제공
- 일별 통계·도토리 포인트·스트릭 등 기능 운영
- 소셜(친구 초대·랭킹) 기능 운영
- 서비스 품질 개선 및 오류 분석
- 이용자 문의 응대

## 제4조 보유 및 이용 기간

1. 이용자가 서비스를 탈퇴하거나 '내 데이터 삭제'를 요청한 경우, 수집된 개인정보는 지체 없이 삭제됩니다.
2. 다만, 관련 법령에 따라 보존이 필요한 경우 해당 법령에서 정한 기간 동안 보관 후 삭제합니다.

## 제5조 제3자 제공 및 처리 위탁

회사는 이용자의 개인정보를 원칙적으로 외부에 제공하지 않습니다. 다만, 서비스 운영을 위해 아래와 같이 처리를 위탁합니다.

### 처리 위탁 현황

- Amplitude Inc.: 앱 사용 분석(익명화된 이용 행태 데이터), 미국 소재, 계약 종료 시까지
- Google Firebase(Google LLC): 앱 진단 및 안정성 분석, 미국 소재, 계약 종료 시까지
- Sentry(Functional Software Inc.): 오류 추적 및 진단, 미국 소재, 계약 종료 시까지
- Apple Inc. / Kakao Corp. / Google LLC: 소셜 로그인 인증 처리, 각사 소재지, 로그인 처리 완료 시

### 서버 인프라

이용자 데이터는 회사가 직접 운영하는 PostgreSQL 백엔드 서버에 저장되며, 제3자에게 제공되지 않습니다.

## 제6조 이용자 권리와 행사 방법

이용자는 언제든지 다음 권리를 행사할 수 있습니다.

- 개인정보 열람 요청
- 개인정보 정정·삭제 요청
- 개인정보 처리 정지 요청

삭제 방법: 앱 설정 > 데이터 > '내 데이터 삭제'를 통해 즉시 삭제가 가능합니다. 삭제 요청 시 식사·씹기 기록, 도토리 포인트, 스트릭 등 모든 데이터가 영구 삭제됩니다.

이메일 문의: ododok.team@gmail.com

## 제7조 안전성 확보 조치

회사는 개인정보의 안전한 처리를 위해 다음 조치를 시행합니다.

- 서버와 앱 간 통신 암호화(TLS/HTTPS)
- 접근 권한 최소화 및 관리
- 민감 정보(토큰 등)의 iOS Keychain 저장

## 제8조 만 14세 미만 이용자

본 서비스는 만 14세 미만의 아동을 대상으로 하지 않습니다. 만 14세 미만 이용자의 개인정보가 수집된 사실을 인지한 경우 즉시 삭제 조치합니다.

## 제9조 개인정보 보호책임자 및 문의

개인정보 처리에 관한 문의·불만·권리 행사는 아래 연락처로 접수하시기 바랍니다.

- 이메일: ododok.team@gmail.com

## 부칙

본 방침은 2026년 6월 30일부터 시행합니다.
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
                .font(.appFont(.heavy, size: 17))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)

            divider

            // Radio rows
            VStack(spacing: 0) {
                ForEach(Array(AirPodsModel.allCases.enumerated()), id: \.element.id) { idx, model in
                    row(model)
                    if idx < AirPodsModel.allCases.count - 1 {
                        divider.padding(.leading, 22)
                    }
                }
            }

            divider

            // Footer — 취소 / 확인
            HStack(spacing: 0) {
                Button {
                    onCancel()
                } label: {
                    Text("취소")
                        .font(.appFont(.semibold, size: 16))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Color.hairline.frame(width: 0.5)

                Button {
                    onConfirm(draft)
                } label: {
                    Text("확인")
                        .font(.appFont(.bold, size: 16))
                        .foregroundStyle(Color.acorn700)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 44)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 320)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private var divider: some View {
        Color.hairline.frame(height: 0.5)
    }

    private func row(_ model: AirPodsModel) -> some View {
        let isActive = model == draft
        return Button {
            draft = model
        } label: {
            HStack(spacing: 14) {
                radio(isActive: isActive)
                Text(model.displayName)
                    .font(.appFont(.semibold, size: 15))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// SF Symbol 없이 그린 라디오 버튼 — 외곽 원 + 활성 시 안쪽 닷.
    private func radio(isActive: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isActive ? Color.acorn600 : Color.textTertiary, lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if isActive {
                Circle()
                    .fill(Color.acorn600)
                    .frame(width: 10, height: 10)
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
                Color.black.opacity(0.32)
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
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isPresented)
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
