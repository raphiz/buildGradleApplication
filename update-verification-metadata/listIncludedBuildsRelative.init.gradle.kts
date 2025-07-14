gradle.rootProject {
    tasks.register("listIncludedBuilds") {
        doLast {
            val rootPath = rootDir.toPath().toAbsolutePath().normalize()
            gradle.includedBuilds.forEach { build ->
                val includedPath = build.projectDir.toPath().toAbsolutePath().normalize()
                println(rootPath.relativize(includedPath))
            }
        }
    }
}