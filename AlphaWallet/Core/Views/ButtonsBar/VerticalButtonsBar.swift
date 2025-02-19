//
//  VerticalButtonsBar.swift
//  AlphaWallet
//
//  Created by Jerome Chan on 9/3/22.
//

import UIKit

class VerticalButtonsBar: UIView {
    
    // MARK: - Public properties
    var buttons: [UIButton] = []
    
    // MARK: Private properties
    private var stackView: UIStackView = UIStackView()
    
    // MARK: - Init
    init(numberOfButtons: Int) {
        super.init(frame: .zero)
        setup(numberOfButtons: numberOfButtons)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hideButtonInStack(button: UIButton) {
        stackView.removeArrangedSubview(button)
        button.removeFromSuperview()
    }

    func showButtonInStack(button: UIButton, position: Int) {
        stackView.insertArrangedSubview(button, at: position)
    }

    // MARK: - Setup and creation
    private func setup(numberOfButtons: Int) {
        var buttonViews: [ContainerViewWithShadow<BarButton>] = [ContainerViewWithShadow<BarButton>]()
        guard numberOfButtons > 0 else { return }
        let primaryButton = createButton(viewModel: .primaryButton)
        primaryButton.childView.borderWidth = 0
        buttonViews.append(primaryButton)
        guard numberOfButtons > 1 else { return }
        (1 ..< numberOfButtons).forEach { _ in
            buttonViews.append(createButton(viewModel: .secondaryButton))
        }
        setupStackView(views: buttonViews)
        setupButtons(views: buttonViews)
        setupView(numberOfButtons: numberOfButtons)
    }
    
    private func setupStackView(views: [UIView]) {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.removeAllArrangedSubviews()
        stackView.addArrangedSubviews(views)
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.spacing = 16.0
        addSubview(stackView)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: stackView.topAnchor),
            bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])
    }

    private func setupButtons(views: [ContainerViewWithShadow<BarButton>]) {
        buttons.removeAll()
        views.forEach { view in
            buttons.append(view.childView)
        }
    }

    private func setupView(numberOfButtons: Int) {
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func createButton(viewModel: ButtonsBarViewModel) -> ContainerViewWithShadow<BarButton> {
        let button = BarButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        let containerView = ContainerViewWithShadow(aroundView: button)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        setup(viewModel: viewModel, view: containerView)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 50.0),
        ])
        return containerView
    }

    // TODO: This function duplicates a function in ButtonsBar. Merge these two functions.

    private func setup(viewModel: ButtonsBarViewModel, view: ContainerViewWithShadow<BarButton>) {
        view.configureShadow(color: viewModel.buttonShadowColor, offset: viewModel.buttonShadowOffset, opacity: viewModel.buttonShadowOpacity, radius: viewModel.buttonShadowRadius, cornerRadius: viewModel.buttonCornerRadius)

        let button = view.childView
        button.setBackgroundColor(viewModel.buttonBackgroundColor, forState: .normal)
        button.setBackgroundColor(viewModel.disabledButtonBackgroundColor, forState: .disabled)

        viewModel.highlightedButtonBackgroundColor.flatMap { button.setBackgroundColor($0, forState: .highlighted) }
        viewModel.highlightedButtonTitleColor.flatMap { button.setTitleColor($0, for: .highlighted) }

        button.setTitleColor(viewModel.buttonTitleColor, for: .normal)
        button.setTitleColor(viewModel.disabledButtonTitleColor, for: .disabled)
        button.setBorderColor(viewModel.buttonBorderColor, for: .normal)
        button.setBorderColor(viewModel.disabledButtonBorderColor, for: .disabled)
        button.titleLabel?.font = viewModel.buttonFont
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        //So long titles (that cause font to be adjusted) have some margins on the left and right
        button.contentEdgeInsets = .init(top: 0, left: 3, bottom: 0, right: 3)

        button.cornerRadius = viewModel.buttonCornerRadius
        button.borderColor = viewModel.buttonBorderColor
        button.borderWidth = viewModel.buttonBorderWidth
    }
}
