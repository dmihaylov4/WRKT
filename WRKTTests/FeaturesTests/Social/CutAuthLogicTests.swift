import Foundation
import Testing
@testable import WRKT

/// The Cut sign-in screens mirror LoginView, SignupView, ForgotPasswordView and SetNewPasswordView.
/// Fixture addresses only (example.com).
@MainActor
@Suite struct CutAuthLogicTests {
    // MARK: Email

    @Test func emailPatternIsLegacys() {
        #expect(CutAuthValidation.isValidEmail("fixture@example.com"))
        #expect(CutAuthValidation.isValidEmail("a.b+c_d%e-f@sub.example.co"))
        #expect(!CutAuthValidation.isValidEmail("fixture@example"))
        #expect(!CutAuthValidation.isValidEmail("fixture example.com"))
        #expect(!CutAuthValidation.isValidEmail("@example.com"))
        #expect(!CutAuthValidation.isValidEmail("fixture@example.c"))
        #expect(!CutAuthValidation.isValidEmail(""))
    }

    // MARK: Log in

    @Test func logInNeedsAValidEmailAndAPassword() {
        #expect(!CutLoginLogic.canLogIn(email: "", password: ""))
        #expect(!CutLoginLogic.canLogIn(email: "fixture@example.com", password: ""))
        #expect(!CutLoginLogic.canLogIn(email: "fixture@", password: "secret"))
        #expect(CutLoginLogic.canLogIn(email: "fixture@example.com", password: "x"))
        #expect(CutLoginLogic.submitsFromPassword(email: "fixture@example.com", password: "x"))
        #expect(!CutLoginLogic.submitsFromPassword(email: "fixture@", password: "x"))
        #expect(CutLoginLogic.next(after: .email) == .password)
        #expect(CutLoginLogic.next(after: .password) == nil)
    }

    @Test func loadingTurnsEveryButtonOffAndKeepsTheError() {
        let idle = CutLoginLogic.model(email: "fixture@example.com", password: "x", isLoading: false, error: nil)
        #expect(idle.logInEnabled); #expect(idle.providersEnabled); #expect(idle.error == nil)
        let loading = CutLoginLogic.model(email: "fixture@example.com", password: "x", isLoading: true, error: nil)
        #expect(!loading.logInEnabled); #expect(!loading.providersEnabled); #expect(loading.canLogIn); #expect(loading.isLoading)
        let empty = CutLoginLogic.model(email: "", password: "", isLoading: false, error: "Invalid login credentials")
        #expect(!empty.logInEnabled); #expect(empty.providersEnabled)
        #expect(empty.error == "Invalid login credentials")
    }

    @Test func loginWordingIsSentenceCase() {
        #expect(CutLoginLogic.title == "Train with friends")
        #expect(CutLoginLogic.logIn == "Log in")
        #expect(CutLoginLogic.createAccount == "Create an account")
        #expect(CutLoginLogic.withoutAccount == "Use the app without an account")
        #expect(CutLoginLogic.forgotPassword == "Forgot password?")
    }

    // MARK: Sign up

    static let valid = CutSignupForm(username: "fixture_user", name: "", email: "fixture@example.com",
                                     password: "Fixture12", confirm: "Fixture12", agreedToTerms: true)

    @Test func usernameRuleIsThreeToThirtyLettersNumbersOrUnderscores() {
        #expect(CutSignupLogic.isValidUsername("abc"))
        #expect(CutSignupLogic.isValidUsername("A_1"))
        #expect(CutSignupLogic.isValidUsername(String(repeating: "a", count: 30)))
        #expect(!CutSignupLogic.isValidUsername("ab"))
        #expect(!CutSignupLogic.isValidUsername(String(repeating: "a", count: 31)))
        #expect(!CutSignupLogic.isValidUsername("fixture.user"))
        #expect(!CutSignupLogic.isValidUsername("fixture user"))
        #expect(!CutSignupLogic.isValidUsername("fixture-user"))
    }

    @Test func eachValidationMessageShowsOnlyWhenLegacyShowedIt() {
        #expect(CutSignupLogic.emailMessage("") == nil)
        #expect(CutSignupLogic.emailMessage("fixture@") == "Please enter a valid email address")
        #expect(CutSignupLogic.emailMessage("fixture@example.com") == nil)
        #expect(CutSignupLogic.usernameMessage("") == nil)
        #expect(CutSignupLogic.usernameMessage("ab") == "Username must be 3-30 characters (letters, numbers, underscore only)")
        #expect(CutSignupLogic.usernameMessage("fixture_user") == nil)
        #expect(CutSignupLogic.mismatch("Fixture12", "") == nil)
        #expect(CutSignupLogic.mismatch("Fixture12", "Fixture1") == "Passwords do not match")
        #expect(CutSignupLogic.mismatch("Fixture12", "Fixture12") == nil)
    }

    @Test func usernameLineIsTheRuleUntilTheNameBreaksIt() {
        let empty = CutSignupLogic.model(CutSignupForm(), isLoading: false, error: nil, flagged: nil)
        #expect(empty.usernameNote == "3 to 30 letters, numbers or underscores.")
        #expect(!empty.usernameNoteIsWarning)
        var form = CutSignupForm(); form.username = "a!"
        let broken = CutSignupLogic.model(form, isLoading: false, error: nil, flagged: nil)
        #expect(broken.usernameNote == CutSignupLogic.usernameInvalidMessage)
        #expect(broken.usernameNoteIsWarning)
    }

    @Test func passwordStrengthScoresLikeLegacy() {
        #expect(CutSignupLogic.passwordStrength("") == 0)
        #expect(CutSignupLogic.passwordStrength("abcdefgh") == 1)
        #expect(CutSignupLogic.passwordStrength("abcdefg1") == 2)
        #expect(CutSignupLogic.passwordStrength("Abcdefg1") == 3)
        #expect(CutSignupLogic.passwordStrength("Abcdefg1!") == 4)
        // A short password with a number and a capital still scores two, as before.
        #expect(CutSignupLogic.passwordStrength("A1") == 2)
        #expect(CutSignupLogic.strength("") == nil)
        #expect(CutSignupLogic.strength("abc")?.label == "Weak")
        #expect(CutSignupLogic.strength("abcdefg1")?.label == "Fair")
        #expect(CutSignupLogic.strength("Abcdefg1")?.label == "Good")
        #expect(CutSignupLogic.strength("Abcdefg1!")?.label == "Strong")
        #expect(CutSignupLogic.strength("abc")?.tone == .weak)
        #expect(CutSignupLogic.strength("Abcdefg1!")?.tone == .strong)
    }

    @Test func createAccountNeedsEveryRuleAndTheTerms() {
        #expect(CutSignupLogic.canSignUp(Self.valid))
        var form = Self.valid; form.agreedToTerms = false
        #expect(!CutSignupLogic.canSignUp(form))
        form = Self.valid; form.email = "fixture@"
        #expect(!CutSignupLogic.canSignUp(form))
        form = Self.valid; form.username = "ab"
        #expect(!CutSignupLogic.canSignUp(form))
        form = Self.valid; form.confirm = "Fixture13"
        #expect(!CutSignupLogic.canSignUp(form))
        form = Self.valid; form.password = "abcdefgh"; form.confirm = "abcdefgh"
        #expect(!CutSignupLogic.canSignUp(form))
        form = Self.valid; form.name = "Fixture Name"
        #expect(CutSignupLogic.canSignUp(form))
        #expect(CutSignupLogic.model(Self.valid, isLoading: false, error: nil, flagged: nil).buttonEnabled)
        let loading = CutSignupLogic.model(Self.valid, isLoading: true, error: nil, flagged: nil)
        #expect(!loading.buttonEnabled); #expect(loading.canSignUp)
    }

    @Test func aServerErrorFlagsTheFieldItNames() {
        #expect(CutSignupLogic.flaggedField(for: "This username is already taken") == .username)
        #expect(CutSignupLogic.flaggedField(for: "Name already taken") == .username)
        #expect(CutSignupLogic.flaggedField(for: "This email is already registered") == .email)
        #expect(CutSignupLogic.flaggedField(for: "Network down") == nil)
        // Case sensitive, as legacy.
        #expect(CutSignupLogic.flaggedField(for: "Email is invalid") == nil)
        let model = CutSignupLogic.model(Self.valid, isLoading: false, error: "This email is already registered", flagged: .email)
        #expect(model.flagsEmail); #expect(!model.flagsUsername)
        #expect(model.error == "This email is already registered")
    }

    @Test func returnMovesDownTheFieldsInScreenOrder() {
        #expect(CutSignupLogic.next(after: .username) == .name)
        #expect(CutSignupLogic.next(after: .name) == .email)
        #expect(CutSignupLogic.next(after: .email) == .password)
        #expect(CutSignupLogic.next(after: .password) == .confirm)
        #expect(CutSignupLogic.next(after: .confirm) == nil)
    }

    // MARK: Reset password

    @Test func sendResetNeedsAnAtSign() {
        #expect(!CutPasswordLogic.canSendReset(""))
        #expect(!CutPasswordLogic.canSendReset("fixture"))
        #expect(CutPasswordLogic.canSendReset("fixture@"))
        let form = CutPasswordLogic.reset(email: "fixture@example.com", sentTo: nil, isLoading: false, error: nil)
        #expect(form.stage == .form); #expect(form.sendEnabled)
        #expect(form.title == "Reset password")
        let sending = CutPasswordLogic.reset(email: "fixture@example.com", sentTo: nil, isLoading: true, error: nil)
        #expect(!sending.sendEnabled); #expect(sending.isLoading)
    }

    @Test func resetErrorsUseLegacysFriendlierMessages() {
        #expect(CutPasswordLogic.resetError("Email rate limit exceeded") == "Too many attempts. Please wait a few minutes before trying again.")
        #expect(CutPasswordLogic.resetError("User not found") == "No account found with this email address.")
        #expect(CutPasswordLogic.resetError("No user with that address") == "No account found with this email address.")
        #expect(CutPasswordLogic.resetError("Network down") == "Network down")
    }

    @Test func sentStateNamesTheAddress() {
        let sent = CutPasswordLogic.reset(email: "fixture@example.com", sentTo: "fixture@example.com", isLoading: false, error: nil)
        #expect(sent.stage == .sent(email: "fixture@example.com"))
        #expect(sent.title == "Check your email")
        #expect(sent.subtitle == "We've sent password reset instructions to:")
    }

    // MARK: Set new password

    @Test func newPasswordNeedsEightCharactersAndAMatch() {
        #expect(!CutPasswordLogic.canSubmit("short", "short", isLoading: false))
        #expect(!CutPasswordLogic.canSubmit("Fixture123", "Fixture12", isLoading: false))
        #expect(CutPasswordLogic.canSubmit("Fixture123", "Fixture123", isLoading: false))
        #expect(!CutPasswordLogic.canSubmit("Fixture123", "Fixture123", isLoading: true))
        #expect(!CutPasswordLogic.passwordsMatch("", ""))
    }

    @Test func checklistShowsLengthThenMatchOnceTheRepeatIsTyped() {
        let empty = CutPasswordLogic.newPassword("", "", updated: false, isLoading: false, error: nil)
        #expect(empty.checks == [.init(text: "At least 8 characters", state: .pending)])
        let mismatch = CutPasswordLogic.newPassword("Fixture123", "Fixture", updated: false, isLoading: false, error: nil)
        #expect(mismatch.checks == [.init(text: "At least 8 characters", state: .met), .init(text: "Passwords don't match", state: .failed)])
        #expect(!mismatch.canSubmit)
        let match = CutPasswordLogic.newPassword("Fixture123", "Fixture123", updated: false, isLoading: false, error: nil)
        #expect(match.checks.last == .init(text: "Passwords match", state: .met))
        #expect(match.canSubmit)
        let done = CutPasswordLogic.newPassword("Fixture123", "Fixture123", updated: true, isLoading: false, error: nil)
        #expect(done.isUpdated); #expect(done.title == "Password updated"); #expect(done.checks.isEmpty)
    }

    @Test func noEmDashesInAnyAuthText() {
        let texts = [CutLoginLogic.title, CutLoginLogic.line, CutSignupLogic.usernameRule,
                     CutSignupLogic.termsText, CutPasswordLogic.resetLine, CutPasswordLogic.newLine, CutPasswordLogic.updatedLine]
        for text in texts { #expect(!text.contains("\u{2014}")) }
    }
}
