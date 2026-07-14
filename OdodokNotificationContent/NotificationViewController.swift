import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let cardView = UIView()
    private let avatarView = UIImageView()
    private let appNameLabel = UILabel()
    private let timeLabel = UILabel()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let dividerView = UIView()
    private let actionStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        preferredContentSize = CGSize(width: 0, height: 178)
        buildView()
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let isInterruption = content.categoryIdentifier == "MEAL_INTERRUPTION"

        appNameLabel.text = "오도독"
        timeLabel.text = "지금"
        titleLabel.text = content.title
        bodyLabel.text = content.body

        actionStack.arrangedSubviews.forEach { view in
            actionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if isInterruption {
            actionStack.addArrangedSubview(makePill("그만하기", filled: false))
            actionStack.addArrangedSubview(makePill("계속하기", filled: true))
        } else {
            actionStack.addArrangedSubview(makePill("식사 시작하기", filled: true))
        }
    }

    private func buildView() {
        view.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(red: 1.0, green: 0.97, blue: 0.94, alpha: 0.90)
        cardView.layer.cornerRadius = 22
        cardView.layer.masksToBounds = false
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.09
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.addSubview(cardView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.image = UIImage(named: "RealDaram")
        avatarView.contentMode = .scaleAspectFit
        avatarView.backgroundColor = UIColor(red: 251/255, green: 243/255, blue: 232/255, alpha: 1)
        avatarView.layer.cornerRadius = 12
        avatarView.clipsToBounds = true

        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        appNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        appNameLabel.textColor = UIColor(red: 45/255, green: 36/255, blue: 24/255, alpha: 1)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = UIColor(red: 140/255, green: 123/255, blue: 102/255, alpha: 1)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = UIColor(red: 30/255, green: 25/255, blue: 18/255, alpha: 1)
        titleLabel.numberOfLines = 2

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = UIColor(red: 92/255, green: 79/255, blue: 62/255, alpha: 1)
        bodyLabel.numberOfLines = 3
        bodyLabel.lineBreakMode = .byTruncatingTail

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = UIColor(red: 229/255, green: 224/255, blue: 216/255, alpha: 1)

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.distribution = .fill
        actionStack.spacing = 10

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = UIColor(red: 181/255, green: 130/255, blue: 80/255, alpha: 1)
        dot.layer.cornerRadius = 4

        let header = UIStackView(arrangedSubviews: [appNameLabel, UIView(), timeLabel, dot])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [header, titleLabel, bodyLabel, dividerView, actionStack])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 8

        let rootStack = UIStackView(arrangedSubviews: [avatarView, textStack])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 14
        cardView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            rootStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            rootStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            rootStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -18),

            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dividerView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func makePill(_ title: String, filled: Bool) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textAlignment = .center
        label.textColor = filled ? .white : UIColor(red: 92/255, green: 79/255, blue: 62/255, alpha: 1)
        label.backgroundColor = filled
            ? UIColor(red: 181/255, green: 130/255, blue: 80/255, alpha: 1)
            : UIColor(red: 242/255, green: 237/255, blue: 229/255, alpha: 1)
        label.layer.cornerRadius = 20
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.heightAnchor.constraint(equalToConstant: 40),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: filled ? 126 : 104),
        ])

        let spacer = UIView()
        if actionStack.arrangedSubviews.isEmpty {
            actionStack.addArrangedSubview(spacer)
        }
        return label
    }
}
