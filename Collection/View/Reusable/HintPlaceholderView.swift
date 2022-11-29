//
//  HintPlaceholderView.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/29.
//

import UIKit

class HintPlaceholderView: UIView {

    private lazy var label: UILabel = {
        let label = UILabel()

        let aString = NSMutableAttributedString(
            string: "There is nothing here now\n",
            attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .semibold)])
        let hintString = NSAttributedString(
            string: "Tap the + to get started",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium)])
        aString.append(hintString)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.alignment = .center
        aString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSMakeRange(0, aString.length))

        label.attributedText = aString
        label.numberOfLines = 2
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayout() {
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
