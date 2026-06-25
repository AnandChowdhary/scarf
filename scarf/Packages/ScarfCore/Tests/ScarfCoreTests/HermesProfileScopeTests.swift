import Testing
import Foundation
@testable import ScarfCore

/// Unit coverage for ScarfGo per-connection profile scoping (issue #120,
/// Design B): the pure `HermesProfileScope` resolver and the
/// `InMemoryProfileSelectionStore` protocol behavior. Both are Linux-safe
/// (no Apple-only deps), so they run on ScarfCore's CI.
@Suite struct HermesProfileScopeTests {

    // MARK: - resolveHome

    @Test func defaultSelectionReturnsBaseUnchanged() {
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: nil) == "~/.hermes")
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "") == "~/.hermes")
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "   ") == "~/.hermes")
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "default") == "~/.hermes")
    }

    @Test func namedProfileAppendsProfilesPath() {
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "gateway")
                == "~/.hermes/profiles/gateway")
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "admin")
                == "~/.hermes/profiles/admin")
    }

    @Test func customRootIsHonored() {
        // Docker / custom HERMES_HOME layout: profiles live under <root>/profiles.
        #expect(HermesProfileScope.resolveHome(baseHome: "/opt/data", profile: "coder")
                == "/opt/data/profiles/coder")
        #expect(HermesProfileScope.resolveHome(baseHome: "/home/deploy/.hermes", profile: "ci")
                == "/home/deploy/.hermes/profiles/ci")
    }

    @Test func trailingSlashesTrimmed() {
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes/", profile: "gateway")
                == "~/.hermes/profiles/gateway")
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes///", profile: nil) == "~/.hermes")
        // A lone slash is preserved (degenerate but must not crash / become empty).
        #expect(HermesProfileScope.resolveHome(baseHome: "/", profile: nil) == "/")
    }

    @Test func whitespaceAroundNameTrimmed() {
        #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: "  gateway  ")
                == "~/.hermes/profiles/gateway")
    }

    /// The security-critical case: a malformed name must NEVER produce a
    /// path outside `<base>/profiles/<valid-name>`. Anything that fails
    /// Hermes's own id regex fails safe to the base (default profile).
    @Test func invalidNamesFailSafeToBase() {
        let bad = [
            "../etc",            // path traversal
            "foo/bar",           // embedded slash
            "..",                // parent ref
            "Gateway",           // uppercase
            "a b",               // space
            "-leading",          // leading dash
            "a;rm -rf /",        // shell metacharacters
            "$(whoami)",         // command substitution
            "a.b",               // dot
            String(repeating: "a", count: 65), // too long (>64)
        ]
        for name in bad {
            #expect(HermesProfileScope.resolveHome(baseHome: "~/.hermes", profile: name) == "~/.hermes",
                    "expected fail-safe to base for invalid name \(name.debugDescription)")
        }
    }

    // MARK: - isValidName

    @Test func validNamesAccepted() {
        #expect(HermesProfileScope.isValidName("gateway"))
        #expect(HermesProfileScope.isValidName("a"))
        #expect(HermesProfileScope.isValidName("a1_b-c"))
        #expect(HermesProfileScope.isValidName("1abc"))                       // leading digit is allowed
        #expect(HermesProfileScope.isValidName(String(repeating: "a", count: 64)))
    }

    @Test func invalidNamesRejected() {
        #expect(!HermesProfileScope.isValidName(""))
        #expect(!HermesProfileScope.isValidName("A"))
        #expect(!HermesProfileScope.isValidName("-x"))
        #expect(!HermesProfileScope.isValidName("a/b"))
        #expect(!HermesProfileScope.isValidName(String(repeating: "a", count: 65)))
    }

    // MARK: - normalize

    @Test func normalizeMapsDefaultsAndInvalidToNil() {
        #expect(HermesProfileScope.normalize(nil) == nil)
        #expect(HermesProfileScope.normalize("") == nil)
        #expect(HermesProfileScope.normalize("default") == nil)
        #expect(HermesProfileScope.normalize("  default  ") == nil)
        #expect(HermesProfileScope.normalize("Bad Name") == nil)
        #expect(HermesProfileScope.normalize("../x") == nil)
        #expect(HermesProfileScope.normalize("gateway") == "gateway")
        #expect(HermesProfileScope.normalize("  gateway  ") == "gateway")
    }

    // MARK: - InMemoryProfileSelectionStore

    @Test func inMemoryStoreRoundTripAndIsolation() {
        let store = InMemoryProfileSelectionStore()
        let a = ServerID()
        let b = ServerID()

        #expect(store.selectedProfile(for: a) == nil)          // absent → default

        store.setSelectedProfile("admin", for: a)
        store.setSelectedProfile("gateway", for: b)
        #expect(store.selectedProfile(for: a) == "admin")
        #expect(store.selectedProfile(for: b) == "gateway")    // per-server isolation

        store.setSelectedProfile(nil, for: a)
        #expect(store.selectedProfile(for: a) == nil)          // clear → default
        #expect(store.selectedProfile(for: b) == "gateway")    // unaffected
    }

    @Test func inMemoryStoreNormalizesOnWriteAndRead() {
        let store = InMemoryProfileSelectionStore()
        let id = ServerID()
        store.setSelectedProfile("default", for: id)           // sentinel → default
        #expect(store.selectedProfile(for: id) == nil)
        store.setSelectedProfile("Bad Name", for: id)          // invalid → default
        #expect(store.selectedProfile(for: id) == nil)
        store.setSelectedProfile("  gateway ", for: id)        // trimmed
        #expect(store.selectedProfile(for: id) == "gateway")
    }
}
