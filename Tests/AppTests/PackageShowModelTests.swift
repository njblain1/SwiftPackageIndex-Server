@testable import App

import XCTVapor


class PackageShowModelTests: AppTestCase {
    
    func test_init_no_title() throws {
        // Tests behaviour when we're lacking data
        // setup package without package name
        var pkg = try savePackage(on: app.db, "1".url)
        try Repository(package: pkg,
                       summary: "summary",
                       defaultBranch: "main",
                       license: .mit,
                       name: "bar",
                       owner: "foo",
                       stars: 17,
                       forks: 42).save(on: app.db).wait()
        let version = try App.Version(package: pkg,
                                      packageName: nil,
                                      reference: .branch("main"))
        try version.save(on: app.db).wait()
        try Product(version: version,
                    type: .library, name: "lib 1").save(on: app.db).wait()
        // reload via query to ensure relationships are loaded
        pkg = try Package.query(on: app.db, owner: "foo", repository: "bar").wait()
        
        // MUT
        let m = PackageShow.Model(package: pkg, readme: "This is the README")
        
        // validate
        XCTAssertNil(m)
    }
    
    func test_query_builds() throws {
        // Ensure the builds relationship is loaded
        // setup
        var pkg = try savePackage(on: app.db, "1".url)
        try Repository(package: pkg,
                       summary: "summary",
                       defaultBranch: "main",
                       license: .mit,
                       name: "bar",
                       owner: "foo",
                       stars: 17,
                       forks: 42).save(on: app.db).wait()
        let version = try App.Version(package: pkg,
                                      packageName: "test package",
                                      reference: .branch("main"))
        try version.save(on: app.db).wait()
        try Build(version: version,
                  platform: .macosXcodebuild,
                  status: .ok,
                  swiftVersion: .init(5, 2, 2))
            .save(on: app.db)
            .wait()
        // re-load repository relationship (required for updateLatestVersions)
        try pkg.$repositories.load(on: app.db).wait()
        // update versions
        _ = try updateLatestVersions(on: app.db, package: pkg).wait()
        // reload via query to ensure pkg is in the same state it would normally be
        pkg = try Package.query(on: app.db, owner: "foo", repository: "bar").wait()

        // MUT
        let m = PackageShow.Model(package: pkg, readme: "This is the README")
        
        // validate
        XCTAssertNotNil(m?.swiftVersionBuildInfo?.latest)
    }

    // Test output of some activity variants without firing up a full snapshot test:
    func test_activity_variants__missing_open_issue() throws {
        var model = PackageShow.Model.mock
        model.activity?.openIssues = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">There are <a href="https://github.com/Alamofire/Alamofire/pulls">5 open pull requests</a>. The last issue was closed 5 days ago and the last pull request was merged/closed 6 days ago.</li>
            """)
    }
    
    func test_activity_variants__missing_open_PRs() throws {
        var model = PackageShow.Model.mock
        model.activity?.openPullRequests = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">There are <a href="https://github.com/Alamofire/Alamofire/issues">27 open issues</a>. The last issue was closed 5 days ago and the last pull request was merged/closed 6 days ago.</li>
            """)
    }
    
    func test_activity_variants__missing_open_issues_and_PRs() throws {
        var model = PackageShow.Model.mock
        model.activity?.openIssues = nil
        model.activity?.openPullRequests = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">The last issue was closed 5 days ago and the last pull request was merged/closed 6 days ago.</li>
            """)
    }
    
    func test_activity_variants__missing_last_closed_issue() throws {
        var model = PackageShow.Model.mock
        model.activity?.lastIssueClosedAt = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">There are <a href="https://github.com/Alamofire/Alamofire/issues">27 open issues</a> and <a href="https://github.com/Alamofire/Alamofire/pulls">5 open pull requests</a>. The last pull request was merged/closed 6 days ago.</li>
            """)

    }
    
    func test_activity_variants__missing_last_closed_PR() throws {
        var model = PackageShow.Model.mock
        model.activity?.lastPullRequestClosedAt = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">There are <a href="https://github.com/Alamofire/Alamofire/issues">27 open issues</a> and <a href="https://github.com/Alamofire/Alamofire/pulls">5 open pull requests</a>. The last issue was closed 5 days ago.</li>
            """)
    }
    
    func test_activity_variants__missing_last_closed_issue_and_PR() throws {
        var model = PackageShow.Model.mock
        model.activity?.lastIssueClosedAt = nil
        model.activity?.lastPullRequestClosedAt = nil
        XCTAssertEqual(model.activityListItem().render(), """
            <li class="activity">There are <a href="https://github.com/Alamofire/Alamofire/issues">27 open issues</a> and <a href="https://github.com/Alamofire/Alamofire/pulls">5 open pull requests</a>. </li>
            """)
    }
    
    func test_activity_variants__missing_everything() throws {
        var model = PackageShow.Model.mock
        model.activity?.openIssues = nil
        model.activity?.openPullRequests = nil
        model.activity?.lastIssueClosedAt = nil
        model.activity?.lastPullRequestClosedAt = nil
        XCTAssertEqual(model.activityListItem().render(), "")
    }
    
    func test_stars_formatting() throws {
        var model = PackageShow.Model.mock
        model.stars = 999
        XCTAssertEqual(model.starsListItem().render(), "<li class=\"stars\">999 stars</li>")
        model.stars = 1_000
        XCTAssertEqual(model.starsListItem().render(), "<li class=\"stars\">1,000 stars</li>")
        model.stars = 1_000_000
        XCTAssertEqual(model.starsListItem().render(), "<li class=\"stars\">1,000,000 stars</li>")
    }
    
    func test_groupBuildInfo() throws {
        let result1: BuildResults = .init(status4_2: .compatible,
                                          status5_0: .compatible,
                                          status5_1: .compatible,
                                          status5_2: .compatible,
                                          status5_3: .compatible)
        let result2: BuildResults = .init(status4_2: .incompatible,
                                          status5_0: .incompatible,
                                          status5_1: .incompatible,
                                          status5_2: .incompatible,
                                          status5_3: .incompatible)
        let result3: BuildResults = .init(status4_2: .unknown,
                                          status5_0: .unknown,
                                          status5_1: .unknown,
                                          status5_2: .unknown,
                                          status5_3: .unknown)
        do {  // three distinct groups
            let buildInfo: BuildInfo = .init(stable: .init(referenceName: "1.2.3",
                                                           results: result1),
                                             beta: .init(referenceName: "2.0.0-b1",
                                                         results: result2),
                                             latest: .init(referenceName: "main",
                                                           results: result3))
            
            // MUT
            let res = PackageShow.Model.groupBuildInfo(buildInfo)
            
            // validate
            XCTAssertEqual(res, [
                .init(references: [.init(name: "1.2.3", kind: .release)], results: result1),
                .init(references: [.init(name: "2.0.0-b1", kind: .preRelease)], results: result2),
                .init(references: [.init(name: "main", kind: .defaultBranch)], results: result3),
            ])
        }
        
        do {  // stable and latest share the same result and should be grouped
            let buildInfo: BuildInfo = .init(stable: .init(referenceName: "1.2.3",
                                                           results: result1),
                                             beta: .init(referenceName: "2.0.0-b1",
                                                         results: result2),
                                             latest: .init(referenceName: "main",
                                                           results: result1))
            
            // MUT
            let res = PackageShow.Model.groupBuildInfo(buildInfo)
            
            // validate
            XCTAssertEqual(res, [
                .init(references: [.init(name: "1.2.3", kind: .release),
                                   .init(name: "main", kind: .defaultBranch)], results: result1),
                .init(references: [.init(name: "2.0.0-b1", kind: .preRelease)], results: result2),
            ])
        }
    }

    func test_badgeURL() throws {
        // Test badge url
        Current.siteURL = { "https://spi.com" }
        let model = PackageShow.Model.mock

        XCTAssertEqual(model.badgeURL(for: .swiftVersions),
                       "https://img.shields.io/endpoint?url=https%3A%2F%2Fspi.com%2Fapi%2Fpackages%2FAlamo%2FAlamofire%2Fbadge%3Ftype%3Dswift-versions")
        XCTAssertEqual(model.badgeURL(for: .platforms),
                       "https://img.shields.io/endpoint?url=https%3A%2F%2Fspi.com%2Fapi%2Fpackages%2FAlamo%2FAlamofire%2Fbadge%3Ftype%3Dplatforms")
    }

    func test_badgeMarkdown() throws {
        // Test badge markdown structure
        Current.siteURL = { "https://spi.com" }
        let model = PackageShow.Model.mock

        let badgeURL = model.badgeURL(for: .swiftVersions)
        let packageURL = "https://spi.com/Alamo/Alamofire"
        XCTAssertEqual(model.badgeMarkdown(for: .swiftVersions),
                       "[![](\(badgeURL))](\(packageURL))")
    }
    
    func test_readmeBaseURL() throws {
        var pkg = try savePackage(on: app.db, "https://github.com/Alamofire/Alamofire")
        
        try Repository(
            package: pkg,
            defaultBranch: "default",
            name: "Alamofire",
            owner: "Alamofire",
            readmeUrl: "https://github.com/Alamofire/Alamofire/master/README.md"
        ).save(on: app.db).wait()
        
        try App.Version(
            package: pkg,
            latest: .defaultBranch,
            packageName: "Alamofire",
            reference: .branch("default")
        ).save(on: app.db).wait()

        // reload via query to ensure relationships are loaded
        pkg = try Package.query(on: app.db,
                                owner: "Alamofire",
                                repository: "Alamofire").wait()

        let model = PackageShow.Model(package: pkg, readme: nil)
        XCTAssertEqual(model?.readmeBaseUrl, "https://github.com/Alamofire/Alamofire/master/")
    }

}


// local typealiases / references to make tests more readable
fileprivate typealias Version = PackageShow.Model.Version
fileprivate typealias BuildInfo = PackageShow.Model.BuildInfo
fileprivate typealias BuildResults = PackageShow.Model.SwiftVersionResults
fileprivate typealias BuildStatusRow = PackageShow.Model.BuildStatusRow
