import Testing
import UIKit

struct SocialToolbarAssetTests {

    @Test func socialActivityIconAssetIsAvailable() {
        let image = UIImage(named: "social-activity-icon", in: .main, compatibleWith: nil)
        #expect(image != nil)
    }
}
