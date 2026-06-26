allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // The integration_test plugin requests androidx.test runner/rules/espresso with
    // dynamic "x.y+" selectors, which force an online version-listing lookup and keep
    // the Android test leg from running offline. Pin them to the concrete versions they
    // already resolve to so resolution needs no network. Bump if the plugin raises its
    // floors past these.
    configurations.all {
        resolutionStrategy.force(
            "androidx.test:runner:1.3.0",
            "androidx.test:rules:1.2.0",
            "androidx.test.espresso:espresso-core:3.3.0",
        )
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
