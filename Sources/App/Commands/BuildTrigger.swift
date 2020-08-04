import Fluent
import SQLKit
import Vapor


struct BuildTriggerCommand: Command {
    let defaultLimit = 1

    struct Signature: CommandSignature {
        @Option(name: "limit", short: "l")
        var limit: Int?
        @Option(name: "id")
        var id: String?
    }

    var help: String { "Trigger package builds" }

    func run(using context: CommandContext, signature: Signature) throws {
        let limit = signature.limit ?? defaultLimit
        let id = signature.id.flatMap(UUID.init(uuidString:))

        if let id = id {
            context.console.info("Triggering builds (id: \(id)) ...")
            try triggerBuilds(application: context.application, id: id).wait()
        } else {
            context.console.info("Triggering builds (limit: \(limit)) ...")
            try triggerBuilds(application: context.application, limit: limit).wait()
        }
    }
}


func triggerBuilds(application: Application, id: Package.Id) -> EventLoopFuture<Void> {
    triggerBuilds(on: application.db, client: application.client, packages: [id])
}


func triggerBuilds(application: Application, limit: Int) throws -> EventLoopFuture<Void> {
    fetchBuildCandidates(application.db, limit: limit)
        .flatMap { triggerBuilds(on: application.db, client: application.client, packages: $0) }
}


func triggerBuilds(on database: Database,
                   client: Client,
                   packages: [Package.Id]) -> EventLoopFuture<Void> {
    Current.getStatusCount(client, .pending)
        .flatMap { count -> EventLoopFuture<Void> in
            // check if we have capacity to schedule more builds
            if count >= Current.gitlabPipelineLimit() {
                print("too many pending pipelines (\(count))")
                return database.eventLoop.future()
            } else {
                // schedule builds
                return packages.map {
                    findMissingBuilds(database, packageId: $0)
                        .flatMap { triggers in
                            triggers.map { trigger -> EventLoopFuture<Void> in
                                trigger.pairs.map { pair in
                                    Build.trigger(database: database,
                                                  client: client,
                                                  platform: pair.platform,
                                                  swiftVersion: pair.swiftVersion,
                                                  versionId: trigger.versionId)
                                        .flatMap { _ in
                                            Build(versionId: trigger.versionId,
                                                  platform: pair.platform,
                                                  status: .pending,
                                                  swiftVersion: pair.swiftVersion)
                                                .create(on: database)
                                        }
                                        .transform(to: ())
                                }
                                .flatten(on: database.eventLoop)
                            }
                            .flatten(on: database.eventLoop)
                        }
                }
                .flatten(on: database.eventLoop)
            }
        }
}


func fetchBuildCandidates(_ database: Database,
                          limit: Int) -> EventLoopFuture<[Package.Id]> {
    guard let db = database as? SQLDatabase else {
        fatalError("Database must be an SQLDatabase ('as? SQLDatabase' must succeed)")
    }

    struct Row: Decodable {
        var packageId: Package.Id

        enum CodingKeys: String, CodingKey {
            case packageId = "package_id"
        }
    }

    let versions = SQLIdentifier("versions")
    let packageId = SQLIdentifier("package_id")
    let latest = SQLIdentifier("latest")
    let updatedAt = SQLIdentifier("updated_at")

    let swiftVersions = SwiftVersion.allActive
    let platforms = Build.Platform.allActive
    let expectedBuildCount = swiftVersions.count * platforms.count

    let buildUnderCount = SQLBinaryExpression(left: count(SQLRaw("*")),
                                              op: SQLBinaryOperator.lessThan,
                                              right: SQLLiteral.numeric("\(expectedBuildCount)"))

    let query = db
        .select()
        .column(packageId)
        .from(versions)
        .join("builds", method: .left, on: "builds.version_id=versions.id")
        .where(isNotNull(latest))
        .groupBy(packageId)
        .groupBy(latest)
        .groupBy(SQLColumn(updatedAt, table: versions))
        .having(buildUnderCount)
        .orderBy(SQLColumn(updatedAt, table: versions))
        .limit(limit)
    return query
        .all(decoding: Row.self)
        .mapEach(\.packageId)
}


struct BuildPair: Equatable, Hashable {
    var platform: Build.Platform
    var swiftVersion: SwiftVersion

    init(_ platform: Build.Platform, _ swiftVersion: SwiftVersion) {
        self.platform = platform
        self.swiftVersion = swiftVersion
    }
}


struct BuildTriggerInfo: Equatable {
    var versionId: Version.Id
    var pairs: Set<BuildPair>

    init(_ versionId: Version.Id, _ pairs: Set<BuildPair>) {
        self.versionId = versionId
        self.pairs = pairs
    }
}


func findMissingBuilds(_ database: Database,
                       packageId: Package.Id) -> EventLoopFuture<[BuildTriggerInfo]> {
    let versions = Version.query(on: database)
        .with(\.$builds)
        .filter(\.$package.$id == packageId)
        .filter(\.$latest != nil)
        .all()

    let allPairs = Build.Platform.allActive.flatMap { p in
        SwiftVersion.allActive.map { s in
            BuildPair(p, s)
        }
    }

    return versions.mapEachCompact { v in
        guard let versionId = v.id else { return nil }
        let existing = v.builds.map { BuildPair($0.platform, $0.swiftVersion) }
        let pairs = Set(allPairs).subtracting(Set(existing))
        return BuildTriggerInfo(versionId, pairs)
    }
}
