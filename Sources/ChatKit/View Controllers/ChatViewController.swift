//
//  WriteViewController.swift
//  
//
//  Created by Zachary Shakked on 9/12/22.
//

import UIKit
import SafariServices
import GitMart

public class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate {

    let chatSequence: ChatSequence
    let theme: ChatTheme
    
    enum ChatType {
        case user, app
    }
    
    public var analyticEventBlock: ((String) -> ())? = nil
    
    private var messages: [(String, ChatType)] = [] {
        didSet {
            let count = messages.count
            tableView.insertRows(at: [IndexPath(row: count - 1, section: 0)], with: .fade)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.tableView.contentSize.height > self.tableView.frame.height {
                    self.tableView.scrollToRow(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: true)
                }
            }
        }
    }
    private var currentButtons: [PowerButton] = []
    private var currentChat: Chat?
    
    @IBOutlet weak var cancelButtonTopMargin: NSLayoutConstraint!
    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet var stackViewHeight: NSLayoutConstraint!
    @IBOutlet weak var stackViewBottomMargin: NSLayoutConstraint!
    
    
    @IBAction func cancelButtonPressed(_ sender: Any) {
        dismiss(animated: true)
    }
    
    public init(chatSequence: ChatSequence, theme: ChatTheme) {
        self.chatSequence = chatSequence
        self.theme = theme
        super.init(nibName: "ChatViewController", bundle: Bundle.module)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        cancelButtonTopMargin.constant = modalPresentationStyle == .fullScreen ? 0 : 8
        
        if theme.hidesCancelButtonOnStart {
            cancelButton.alpha = 0.0
            cancelButton.isHidden = true
        }
        
        cancelButton.setTitle("", for: .normal)
        tableView.backgroundColor = theme.chatViewBackgroundColor
        tableView.layer.cornerRadius = theme.chatViewCornerRadius
        backgroundView.backgroundColor = theme.backgroundColor
        cancelButton.tintColor = theme.xButtonTintColor
        
        tableView.register(UINib(nibName: "ChatCell", bundle: Bundle.module), forCellReuseIdentifier: ChatCell.reuseIdentifier)
        tableView.register(UINib(nibName: "UserChatCell", bundle: Bundle.module), forCellReuseIdentifier: UserChatCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        
        setupChatSequenceBlocks()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [unowned self] in
            self.chatSequence.start()
        }
        
        chatSequence.controller = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.chatSequence.dismissed()
    }
    
    @objc func buttonPressed(_ sender: PowerButton) {
        guard let currentChat = currentChat else {
            return
        }
        
        let title = sender.titleLabel?.text ?? ""
        if let conditionalChat = currentChat as? ChatMessageConditional {
            guard let index = conditionalChat.options.firstIndex(of: title) else { return }
            chatSequence.userTappedButton(index: index, buttonText: title, chat: currentChat, controller: self)
        } else if let buttonChat = currentChat as? ChatButtons {
            guard let index = buttonChat.buttons.map({ $0.title }).firstIndex(of: title) else { return }
            chatSequence.userTappedButton(index: index, buttonText: title, chat: currentChat, controller: self)
        } else if let _ = currentChat as? ChatButton {
            chatSequence.userTappedButton(index: 0, buttonText: title, chat: currentChat, controller: self)
        }
    }
    
    // MARK: - UITableViewDataSource
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    var animatedCells: Set<String> = Set<String>()
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        let previous = indexPath.row - 1 >= 0 ? messages[indexPath.row - 1] : nil
        let uniqueID = "\(indexPath.row)"
        switch message.1 {
        case .app:
            let cell: ChatCell = tableView.dequeueReusableCell(withIdentifier: ChatCell.reuseIdentifier) as! ChatCell
            if animatedCells.contains(uniqueID) {
                cell.shouldAnimate = false
            }
            if let prev = previous, prev.1 == message.1 {
                cell.topMarginConstraint.constant = 0
            }
            
            cell.configure(for: theme)
            cell.messageLabel.text = message.0
            animatedCells.insert(uniqueID)
            return cell
        case .user:
            let cell: UserChatCell = tableView.dequeueReusableCell(withIdentifier: UserChatCell.reuseIdentifier) as! UserChatCell
            if animatedCells.contains(uniqueID) {
                cell.shouldAnimate = false
            }
            if let prev = previous, prev.1 == message.1 {
                cell.topMarginConstraint.constant = 0
            }
            cell.messageLabel.text = message.0
            cell.configure(for: theme)
            animatedCells.insert(uniqueID)
            return cell
        }
    }
    
    // MARK: - Config
    
    func setupChatSequenceBlocks() {
        chatSequence.openURL = { [unowned self] (url, withSafariVC) in
            if withSafariVC {
                let sfvc = SFSafariViewController(url: url)
                self.present(sfvc, animated: true)
            } else {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
        }
        chatSequence.showCancelButton = { [unowned self] in
            self.cancelButton.isHidden = false
            UIView.animate(withDuration: 0.35) {
                self.cancelButton.alpha = 1.0
            }
        }
        chatSequence.dismiss = { [unowned self] in
            self.dismiss(animated: true)
        }
        chatSequence.addMessage = { [unowned self] chat in
            self.messages.append((chat, .app))
        }
        chatSequence.addUserMessage = { [unowned self] chat in
            self.messages.append((chat, .user))
        }
        chatSequence.showButtons = { chat in
            self.currentChat = chat

            if let conditionalChat = chat as? ChatMessageConditional {
                let options = conditionalChat.options
                let buttons = options.map { [unowned self] (text: String) -> PowerButton in
                    let button = self.powerButton(title: text)
                    self.stackView.addArrangedSubview(button)
                    NSLayoutConstraint.activate([
                        button.heightAnchor.constraint(equalToConstant: 48.0)
                    ])
                    return button
                }
                self.currentButtons = buttons
                self.stackViewHeight.isActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 1.5, options: [.allowUserInteraction, .curveEaseInOut], animations: { [unowned self] in
                        buttons.forEach({ $0.isHidden = false })
                        self.stackView.layoutIfNeeded()
                    }) { _ in
                        self.scrollToBottomOfTableView()
                    }
                }
            } else if let chat = chat as? ChatButtons {
                let ingredients = chat.buttons
                let buttons = ingredients.map { [unowned self] (ingredients: ChatButton) -> PowerButton in
                    let button = self.powerButton(title: ingredients.title)
                    if let image = ingredients.image {
                        button.setImage(image, for: .normal)
                    }
                    self.stackView.addArrangedSubview(button)
                    NSLayoutConstraint.activate([
                        button.heightAnchor.constraint(equalToConstant: 48.0)
                    ])
                    return button
                }
                self.currentButtons = buttons
                self.stackViewHeight.isActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [unowned self] in
                    self.springAnimation {
                        buttons.forEach({ $0.isHidden = false })
                        self.stackView.layoutIfNeeded()
                    } completion: {
                        self.scrollToBottomOfTableView()
                    }
                }
                
            } else if let chat = chat as? ChatButton {
                let button = self.powerButton(title: chat.title)
                if let image = chat.image {
                    button.setImage(image, for: .normal)
                }
                
                self.stackView.addArrangedSubview(button)
                NSLayoutConstraint.activate([
                    button.heightAnchor.constraint(equalToConstant: 48.0)
                ])
                self.currentButtons = [button]
                self.stackViewHeight.isActive = false
                // This delay is needed or else the stackview animation is weird
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [unowned self] in
                    self.springAnimation {
                        button.isHidden = false
                        self.stackView.layoutIfNeeded()
                    } completion: {
                        self.scrollToBottomOfTableView()
                    }
                }
            }
        }
        
        chatSequence.startTyping = {
            // TODO
        }
        
        chatSequence.stopTyping = {
            // TODO
        }
        
        chatSequence.hideButtons = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [unowned self] in
                self.springAnimation {
                    self.currentButtons.forEach({ $0.isHidden = true; $0.alpha = 0.0 })
                    self.stackView.layoutIfNeeded()
                } completion: {
                    self.stackViewHeight.isActive = true
                }
            }
        }
        
        chatSequence.showTextInput = { [unowned self] chatTextInput in
            let textInputView = TextInputView(chatTextInput: chatTextInput, theme: self.theme)
            textInputView.textField.keyboardType = .emailAddress
            textInputView.textField.returnKeyType = .done
            self.stackViewHeight.isActive = false
            self.stackView.addArrangedSubview(textInputView)
            textInputView.textField.becomeFirstResponder()
            textInputView.finishedWriting = { [unowned self] text in
                self.chatSequence.userEnteredText(text: text, chat: chatTextInput, controller: self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [unowned self] in
                    self.springAnimation {
                        textInputView.isHidden = true
                        textInputView.alpha = 0.0
                        self.stackView.layoutIfNeeded()
                    } completion: {
                        self.stackViewHeight.isActive = true
                    }
                }
            }
            NSLayoutConstraint.activate([
                textInputView.heightAnchor.constraint(greaterThanOrEqualToConstant: 5.33 * theme.textInputFont.pointSize)
            ])
        }
    }
    
    private func powerButton(title: String) -> PowerButton {
        let button = PowerButton()
        button.tintColor = theme.buttonTextColor
        button.backgroundColor = theme.buttonBackgroundColor
        button.setTitle(title, for: .normal)
        button.setTitleColor(theme.buttonTextColor, for: .normal)
        button.cornerRadius = 16.0
        button.clipsToBounds = true
        button.titleLabel?.font = theme.buttonFont
        button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }
    
    private func springAnimation(animations: @escaping () -> (), completion: @escaping () -> ()) {
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 1.5, options: [.allowUserInteraction, .curveEaseInOut], animations: animations, completion: { _ in
            completion()
        })
    }
    
    private func scrollToBottomOfTableView() {
        if messages.count >= 1 {
            self.tableView.scrollToRow(at: IndexPath(item: self.messages.count - 1, section: 0), at: .bottom, animated: true)
        }
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardRectangle = keyboardFrame.cgRectValue
            let keyboardHeight = keyboardRectangle.height
            stackViewBottomMargin.constant = keyboardHeight
            UIView.animate(withDuration: 0.45, animations: { [unowned self] in
                self.view.layoutIfNeeded()
                self.stackView.layoutIfNeeded()
            }) { _ in
                self.scrollToBottomOfTableView()
            }
        }
    }
    
    @objc private func keyboardWillHide() {
        stackViewBottomMargin.constant = 42
        UIView.animate(withDuration: 0.7, animations: { [unowned self] in
            self.view.layoutIfNeeded()
            self.stackView.layoutIfNeeded()
        }) { _ in
            self.scrollToBottomOfTableView()
        }
    }
}
