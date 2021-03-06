import Combine
import ExposureNotification
import Foundation
import SnapKit
import UIKit

enum RadarStatus: Int, Codable {
    case on
    case off
    case locked
    case btOff
    case apiDisabled
}

extension RadarStatus {
    init(from status: ENStatus) {
        switch status {
        case .active:
            self = .on
        case .bluetoothOff:
            self = .btOff
        case .disabled:
            self = .off
        default:
            self = .apiDisabled
        }
    }
}

final class RadarAnimation : UIImageView {
    init() {
        super.init(image: UIImage(named: "radar-background"))
        render()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func render() {
        contentMode = .scaleAspectFit
        
        let animated = UIImageView(image: UIImage(named: "radar-animated"))
        addSubview(animated)
        
        animated.snp.makeConstraints { make in
            make.center.width.height.equalToSuperview()
        }
        
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
        rotationAnimation.fromValue = 0.0
        rotationAnimation.toValue = Double.pi * 2
        rotationAnimation.duration = 9.0
        rotationAnimation.repeatCount = .infinity
        animated.layer.add(rotationAnimation, forKey: nil)
        
        let foreground = UIImageView(image: UIImage(named: "radar-foreground"))
        addSubview(foreground)
        
        foreground.snp.makeConstraints { make in
            make.center.width.height.equalToSuperview()
        }
        
        for bar in 1...3 {
            let barImg = UIImageView(image: UIImage(named: "radar-bar-\(bar)"))
            barImg.layer.opacity = 0
            foreground.addSubview(barImg)
            barImg.snp.makeConstraints { make in
                make.center.width.height.equalToSuperview()
            }
            let fadeInOut = CAKeyframeAnimation(keyPath: "opacity")
            fadeInOut.beginTime = CACurrentMediaTime() + CFTimeInterval(bar - 1) / 4.0
            fadeInOut.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            fadeInOut.values = [0.0, 0.0, 1.0, 0.0, 0.0]
            fadeInOut.autoreverses = true
            fadeInOut.duration = 2.0
            fadeInOut.repeatCount = .infinity
            barImg.layer.add(fadeInOut, forKey: nil)
        }
    }
}

final class StatusHeaderView: UIView {
    enum Text : String, Localizable {
        case TitleEnabled
        case TitleDisabled
        case TitleLocked

        case BodyEnabled
        case BodyDisabled
        case BodyLocked
        case BodyBTOff
        
        case EnableButton
    }

    var radarStatus: RadarStatus?
    var radarContainer: UIView!
    var titleLabel: UILabel!
    var bodyLabel: UILabel!
    var button: UIButton!
    var buttonConstraint: Constraint!
    let exposureRepository = Environment.default.exposureRepository
    var updateTask: AnyCancellable? = nil
    var openSettingsHandler: ((_ type: OpenSettingsType) -> Void)? = nil
    
    let verticalPadding = CGFloat(30)
    let imageHeight = CGFloat(122)
    
    init() {
        super.init(frame: .zero)

        createUI()

        updateTask = LocalStore.shared.$uiStatus.$wrappedValue.sink { [weak self] status in
            guard let self = self else {
                return
            }
            
            UIView.defaultTransition(with: self) {
                self.radarStatus = status
                self.render()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func adjustSize(by: CGFloat) {
        self.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(by < 0 ? by : 0)
        }

        radarContainer.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(by < 0 ? verticalPadding - by / 2 : verticalPadding)
            make.height.equalTo(by < 0 ? imageHeight - by / 2 : imageHeight)
        }
    }
    
    func render() {
        renderRadar()
        titleLabel.text = getTitleText().localized
        titleLabel.textColor = getTitleFontColor()
        bodyLabel.text = getBodyText().localized
        
        if let buttonTitle = getButtonTitle() {
            button.isHidden = false
            button.setTitle(buttonTitle.localized, for: .normal)
            buttonConstraint.activate()
        } else {
            button.isHidden = true
            buttonConstraint.deactivate()
        }
    }
    
    private func renderRadar() {
        radarContainer.removeAllSubviews()
        let radarView = getRadarView()
        radarContainer.addSubview(radarView)
        radarView.snp.makeConstraints { make in
            make.height.centerX.equalToSuperview()
            make.width.equalTo(radarView.snp.height)
        }
    }
    
    private func createUI() {
        backgroundColor = UIColor.Greyscale.white
        
        radarContainer = UIView()
        self.addSubview(radarContainer)
        radarContainer.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(30)
            make.top.equalToSuperview()
            make.height.equalTo(imageHeight)
        }
        
        let container = UIView()
        self.addSubview(container)
        
        container.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 20, bottom: 30, right: 20))
        }
        
        titleLabel = UILabel(label: getTitleText().localized,
                             font: UIFont.heading3,
                             color: getTitleFontColor())
        
        titleLabel.textAlignment = .center
        container.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(radarContainer.snp.bottom).offset(15)
            make.left.right.equalToSuperview().inset(10)
        }
        
        bodyLabel = UILabel(label: getBodyText().localized,
                            font: UIFont.labelTertiary,
                            color: UIColor.Greyscale.black)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        container.addSubview(bodyLabel)
        bodyLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.left.right.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().priority(.medium)
        }
        
        button = RoundedButton(title: "",
                               backgroundColor: UIColor.Primary.red,
                               highlightedBackgroundColor: UIColor.Primary.red,
                               action: buttonAction)
        container.addSubview(button)
        button.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(10)
            make.top.equalTo(bodyLabel.snp.bottom).offset(20)
            buttonConstraint = make.bottom.equalToSuperview().constraint
        }
    }

    private func buttonAction() {
        switch radarStatus {
        case .btOff:
            openSettings(.bluetooth)
        case .apiDisabled:
            // RadarStatus.apiDisabled==ENStatus.restricted which can be used in various situations:
            // app specific EN permission turned off, system level EN (permission) turned off or
            // if another EN app is active. In the last case we can activate our app by calling enable
            // and the user doesn't need to do anything. In the other cases the user needs to go to
            // settings and either enable app or system EN. If enabling fails but the error is "restricted"
            // (user didn't grant permission to switch the app), then don't show the Enable EN instructions.
            exposureRepository.tryEnable { [weak self] errorCode in
                if let code = errorCode, code != .restricted {
                    self?.openSettings(.exposureNotifications)
                }
            }
            
        case .off:
            exposureRepository.setStatus(enabled: true)
        default:
            break
        }
    }
    
    private func openSettings(_ type: OpenSettingsType) {
        guard let handler = self.openSettingsHandler else { return }
        handler(type)
    }
    
    private func getRadarView() -> UIImageView {
        switch(radarStatus) {
        case .on:
            return RadarAnimation()
        case .off, .locked, .apiDisabled, .btOff, .none:
            let imageView = UIImageView(image: UIImage(named: "radar-off"))
            imageView.contentMode = .scaleAspectFit
            return imageView
        }
    }
    
    private func getTitleText() -> Text {
        switch(radarStatus) {
        case .on:
            return .TitleEnabled
        case .off, .apiDisabled, .btOff, .none:
            return .TitleDisabled
        case .locked:
            return .TitleLocked
        }
    }
    
    private func getBodyText() -> Text {
        switch(radarStatus) {
        case .on:
            return .BodyEnabled
        case .off, .apiDisabled, .none:
            return .BodyDisabled
        case .locked:
            return .BodyLocked
        case .btOff:
            return .BodyBTOff
        }
    }
    
    private func getTitleFontColor() -> UIColor {
        switch(radarStatus) {
        case .on:
            return UIColor.Primary.blue
        case .off, .apiDisabled, .btOff, .none:
            return UIColor.Primary.red
        case .locked:
            return UIColor.Greyscale.darkGrey
        }
    }
    
    private func getButtonTitle() -> Text? {
        switch radarStatus {
        case .on, .locked, .none:
            return nil
        case .apiDisabled, .btOff, .off:
            return .EnableButton
        }
    }
}

#if DEBUG
import SwiftUI

struct CollapsibleHeaderViewPreview: PreviewProvider {
    static var previews: some View = createPreview(
        for: StatusHeaderView(),
        width: 375,
        height: 339
    )
}
#endif
